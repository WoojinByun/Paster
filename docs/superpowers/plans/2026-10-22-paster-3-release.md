# Paster 3/3 — 서명 · 번들 · Sparkle · 릴리스 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 자체 서명 인증서로 서명한 `build/Paster.app` 을 만들고(`make cert` / `make app` / `make install`), Sparkle 2 자동 업데이트를 연결하고, `make release VERSION=x.y.z` 한 번으로 GitHub Release(zip + appcast.xml)를 올릴 수 있게 한다.

**Architecture:** 빌드는 계속 SwiftPM(`swift build -c release`)으로 하고, `.app` 조립 · 서명은 셸 스크립트(`scripts/bundle.sh`)가 한다. Sparkle 은 SPM 바이너리 xcframework 로 받아 `Contents/Frameworks` 에 복사하며, 실행 파일의 rpath 는 `Package.swift` 의 `linkerSettings` 로 넣는다. 릴리스는 Sparkle SPM 아티팩트에 함께 들어 있는 `generate_keys` / `generate_appcast` 와 `gh` CLI 로 한다.

**Tech Stack:** Sparkle 2.10.0 (SPM), OpenSSL/LibreSSL, `security`, `codesign`, PlistBuddy, `ditto`, `gh`, GNU make.

**스펙:** `docs/superpowers/specs/2026-10-22-paster-design.md` 12절 · 13절. **선행 조건:** 플랜 1 · 2 완료 (`make test` 117개 통과, `make run` 으로 앱 동작 확인).

---

## 작업 환경

- 작업 디렉터리: `/Users/woojin/work/ridi/worktrees/Paster/Paster` (브랜치 `Paster`). 원격 `origin` = https://github.com/WoojinByun/Paster (**공개 저장소**).
- **`git add` 는 지정한 파일만.** 다른 작업자가 `README.md` 를 커밋할 수 있다 (README 는 Task 7 에서만 고친다). `index.lock` 오류는 재시도. bare `git stash` 금지.
- 커밋 trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- **비밀 정보는 절대 커밋하지 않는다:** 인증서 개인 키 · `.p12` · Sparkle EdDSA 개인 키. `.gitignore` 에 `*.p12`, `*.pem` 이 이미 있다 (플랜 1 Task 1). 커밋하는 것은 Sparkle **공개** 키(`Resources/sparkle-public-key.txt`)뿐이다.
- 대화형 단계(사람이 직접 해야 함): Task 1 의 `make cert`(로그인 암호), Task 3 의 `make sparkle-keys`(키체인 접근 허용), Task 6 의 릴리스(공개 배포이므로 사용자 확인 후).

## 검증해 둔 사실

계획 작성 시 이 Mac(Xcode 27.1, Swift 6.4, macOS 27 arm64)에서 확인했다.

- **Sparkle 2.10.0 SPM 아티팩트:** `swift package resolve` 만으로 `.build/artifacts/sparkle/Sparkle/` 에 `Sparkle.xcframework` 와 `bin/generate_keys`, `bin/generate_appcast`, `bin/sign_update`, `bin/BinaryDelta` 가 받아진다. **별도 tarball 다운로드는 필요 없다.**
- **빌드된 프레임워크 위치:** `swift build -c release` 후 `$(swift build -c release --show-bin-path)/Sparkle.framework` (= `.build/out/Products/Release/Sparkle.framework`, `.build/release` 는 심볼릭 링크). debug 도 같은 방식으로 `Debug/Sparkle.framework`. 프레임워크 안에 심볼릭 링크가 있으므로 `ditto` 로 복사한다. 실행 파일은 `@rpath/Sparkle.framework/Versions/B/Sparkle` 을 링크한다.
- **rpath:** 루트 패키지의 실행 타깃에 `linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]` 를 두면 `otool -l` 에 `LC_RPATH @executable_path/../Frameworks` 가 생기고 빌드 · 테스트가 그대로 된다 (`unsafeFlags` 는 루트 패키지에서 허용). `install_name_tool` 은 쓰지 않는다. `bundle.sh` 가 rpath 존재를 다시 확인한다.
- **중첩 서명 순서:** `XPCServices/Installer.xpc` → `XPCServices/Downloader.xpc`(`--preserve-metadata=entitlements`) → `Autoupdate` → `Updater.app` → `Sparkle.framework` → `Paster.app`. 이 순서로 서명한 앱이 `codesign --verify --deep --strict` 를 통과하고 실행됨을 ad-hoc 서명으로 확인했다. Hardened Runtime(`-o runtime`)은 쓰지 않는다: notarize 하지 않고, Team ID 가 없는 자체 서명 인증서에서 library validation 이 Sparkle 로딩을 막을 수 있기 때문이다.
- **리소스 번들:** `KeyboardShortcuts_KeyboardShortcuts.bundle` 등 `*.bundle` 을 `Contents/Resources/` 에 복사해야 한다 (플랜 2 참고).
- **인증서 p12:** Homebrew `openssl` 은 이 Mac 에서 OpenSSL 4.0.3 이고(`/opt/homebrew/opt/openssl@3` 은 3.5.9), 둘 다 기본 p12 암호화(AES/PBKDF2)를 `security import` 가 읽지 못해 `MAC verification failed` 가 난다. `-legacy` 를 붙이면 된다. macOS 기본 `/usr/bin/openssl` 은 LibreSSL 3.3.6 이라 `-legacy` 옵션이 없고 필요도 없다. 그래서 스크립트는 `openssl version` 이 `OpenSSL` 로 시작할 때만 `-legacy` 를 붙인다. 세 가지 openssl 모두 임시 키체인으로 import 성공을 확인했다.
  - 주의: `set -o pipefail` 에서 `openssl version | grep -q ...` 는 SIGPIPE 로 거짓이 될 수 있어 `case` 로 판별한다.
  - 신뢰 설정 전(`CSSMERR_TP_NOT_TRUSTED`)에도 `codesign` 자체는 된다. 신뢰 설정은 `security find-identity -v -p codesigning` 에 "유효"로 나오게 하기 위한 것이다.
- **generate_appcast:** `--download-url-prefix`, `--embed-release-notes`, `-o`, 같은 이름의 `.md` 릴리스 노트를 지원한다. 임시 EdDSA 키로 실제 실행해 `sparkle:version`(= `CFBundleVersion`), `sparkle:shortVersionString`, `enclosure url=".../releases/download/vX.Y.Z/Paster-X.Y.Z.zip"`, `sparkle:edSignature`, markdown 설명이 든 appcast 가 나오는 것을 확인했다. 실제 릴리스는 키체인 키를 쓰므로 `--ed-key-file` 을 주지 않는다.
- **generate_keys:** `-p` 는 공개 키 base64 한 줄만 출력한다. `-x <file>` 은 개인 키 내보내기(백업).
- **SUEnableAutomaticChecks:** 스펙대로 Info.plist 에 넣지 않는다. 그러면 Sparkle 은 두 번째 실행 때 "자동으로 확인할까요?" 를 묻는데, 스펙의 "기본값 ON" 을 지키기 위해 앱이 처음 실행될 때 (사용자 기본값에 `SUEnableAutomaticChecks` 가 없으면) `automaticallyChecksForUpdates = true` 로 저장한다. 이후는 설정 체크박스가 정한다.

## File Structure

```
scripts/make-cert.sh                        # 생성: "Paster Local Signing" 자체 서명 인증서
scripts/bundle.sh                           # 생성: build/Paster.app 조립 · 버전 주입 · Sparkle 복사 · 서명
scripts/release.sh                          # 생성: zip · appcast · gh release
scripts/dev-bundle.sh                       # 삭제: bundle.sh 로 대체
Resources/Info.plist                        # 생성: 번들 Info.plist 템플릿 (LSUIElement, SUFeedURL, SUPublicEDKey 자리)
Resources/sparkle-public-key.txt            # 생성(make sparkle-keys): EdDSA 공개 키 (커밋)
Makefile                                    # 수정: cert, app, install, test, run, sparkle-keys, release
Package.swift                               # 수정: Sparkle 2.10.0 + rpath
Sources/Paster/Update/UpdaterService.swift  # 생성: SPUStandardUpdaterController 래퍼
Sources/Paster/App/AppDelegate.swift        # 수정: 업데이트 메뉴 연결
Sources/Paster/Settings/SettingsModel.swift # 수정: 자동 업데이트 확인 값
Sources/Paster/Settings/SettingsView.swift  # 수정: 체크박스
Sources/Paster/Settings/SettingsWindowController.swift  # 수정: updater 전달
README.md                                   # 수정(Task 7): "개발 중" / "구현 예정" 표시 제거
```

---

### Task 1: 자체 서명 코드서명 인증서

스펙 12절 `make cert`: ad-hoc 서명은 빌드마다 서명이 바뀌어 손쉬운 사용 권한을 다시 요청한다. 고정 인증서로 서명하면 designated requirement(`identifier "com.wjbyun.Paster" and certificate leaf = H"..."`)가 빌드마다 같아 권한이 유지된다.

**Files:**
- Create: `scripts/make-cert.sh`
- Modify: `Makefile` (전체 교체)

- [ ] **Step 1: 스크립트 작성**

`scripts/make-cert.sh`:

```bash
#!/bin/bash
# 최초 1회: 자체 서명 코드서명 인증서 "Paster Local Signing" 을 로그인 키체인에 만든다.
# 마지막 단계(add-trusted-cert)에서 macOS 가 로그인 암호를 묻는다 (대화형).
set -euo pipefail

NAME="Paster Local Signing"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL="${OPENSSL:-openssl}"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "인증서 '$NAME' 가 이미 있습니다."
    security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf"

# OpenSSL 3 이상의 기본 p12 암호화(AES/PBKDF2)는 security import 가 읽지 못하므로 -legacy 를 쓴다.
# macOS 기본 /usr/bin/openssl (LibreSSL) 은 원래 legacy 형식이라 옵션이 필요 없다.
LEGACY_FLAG=""
case "$("$OPENSSL" version)" in
    OpenSSL*) LEGACY_FLAG="-legacy" ;;
esac
P12_PASSWORD="$(uuidgen)"
"$OPENSSL" pkcs12 -export $LEGACY_FLAG -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout "pass:$P12_PASSWORD"

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

echo "코드서명용으로 신뢰 설정을 추가합니다. macOS 가 로그인 암호를 물으면 입력하세요."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME"
```

Run: `chmod +x scripts/make-cert.sh && bash -n scripts/make-cert.sh && echo syntax-ok`
Expected: `syntax-ok`

- [ ] **Step 2: Makefile 교체 (`cert` 추가)**

```make
.PHONY: cert test run

# 최초 1회: 자체 서명 인증서 "Paster Local Signing" (로그인 암호 입력 필요)
cert:
	./scripts/make-cert.sh

test:
	swift test

# 개발용 실행: debug .app 을 만들어 연다
run:
	./scripts/dev-bundle.sh
	-pkill -x Paster && sleep 1
	open build/debug/Paster.app
```

- [ ] **Step 3: 인증서 만들기 (대화형)**

Run: `make cert`

macOS 가 "신뢰 설정을 변경하려고 합니다" 창에서 로그인 암호를 묻는다 → 입력한다. 사람이 직접 해야 하는 단계다.

Expected 마지막 줄: `  1) <40자 SHA-1> "Paster Local Signing"` (`-v` 목록에 나오면 신뢰 설정까지 된 것). 다시 실행하면 `인증서 'Paster Local Signing' 가 이미 있습니다.`

- [ ] **Step 4: 백업 안내 확인**

키체인 접근 → 로그인 → 내 인증서 → "Paster Local Signing" → 내보내기(.p12)로 백업할 수 있음을 확인한다. **백업 파일은 저장소 밖에 둔다.** 이 인증서를 잃으면 Sparkle 업데이트 서명 검증과 손쉬운 사용 권한이 깨진다 (스펙 13절).

- [ ] **Step 5: 커밋**

```bash
git add scripts/make-cert.sh Makefile
git commit -m "build: add self-signed code signing certificate script" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Sparkle 의존성 · 업데이터 연결

스펙 3.2절 SPUStandardUpdaterController, 3.3절 `업데이트 확인…`, 13절(메뉴 → `checkForUpdates`, 설정 체크박스 ↔ `automaticallyChecksForUpdates`, 기본값 ON).

**Files:**
- Modify: `Package.swift` (전체 교체)
- Create: `Sources/Paster/Update/UpdaterService.swift`
- Modify: `Sources/Paster/App/AppDelegate.swift`
- Modify: `Sources/Paster/Settings/SettingsWindowController.swift`
- Modify: `Sources/Paster/Settings/SettingsModel.swift`
- Modify: `Sources/Paster/Settings/SettingsView.swift`

- [ ] **Step 1: `Package.swift` 교체**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paster",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Paster", targets: ["Paster"]),
        .library(name: "PasterCore", targets: ["PasterCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "PasterCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Paster",
            dependencies: [
                "PasterCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // Sparkle.framework 를 Paster.app/Contents/Frameworks 에서 찾도록
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "PasterCoreTests",
            dependencies: ["PasterCore"]
        ),
    ]
)
```

Run: `swift package resolve && ls .build/artifacts/sparkle/Sparkle/bin`
Expected: `BinaryDelta  generate_appcast  generate_keys  old_dsa_scripts  sign_update`

- [ ] **Step 2: 업데이터 래퍼 작성**

`Sources/Paster/Update/UpdaterService.swift`:

```swift
import AppKit
import Sparkle

/// Sparkle 업데이트 (스펙 13절).
@MainActor
final class UpdaterService {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // 기본값 ON. 한 번도 정한 적 없으면 켜 두어 Sparkle 의 허락 요청 창을 생략한다.
        if UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil {
            controller.updater.automaticallyChecksForUpdates = true
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "업데이트 확인…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        return item
    }
}
```

- [ ] **Step 3: AppDelegate 수정 — updater 보유**

`Sources/Paster/App/AppDelegate.swift` 에서

찾을 코드:

```swift
    private var settingsWindow: SettingsWindowController?
```

바꿀 코드:

```swift
    private var settingsWindow: SettingsWindowController?
    private let updater = UpdaterService()
```

- [ ] **Step 4: AppDelegate 수정 — 설정 창에 updater 전달**

찾을 코드:

```swift
        settingsWindow = SettingsWindowController(environment: environment) { [weak panelController] in
```

바꿀 코드:

```swift
        settingsWindow = SettingsWindowController(environment: environment, updater: updater) { [weak panelController] in
```

- [ ] **Step 5: AppDelegate 수정 — 메뉴 항목 연결**

찾을 코드:

```swift
        menu.addItem(makeUpdateMenuItem())
```

바꿀 코드:

```swift
        menu.addItem(updater.makeMenuItem())
```

그리고 자리표시 메서드를 통째로 지운다. 찾을 코드(아래 블록과 그 뒤 빈 줄 하나):

```swift
    /// Sparkle 연결 전까지는 비활성 항목이다 (플랜 3 에서 연결).
    private func makeUpdateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "업데이트 확인…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
```

바꿀 코드: (없음 — 삭제)

수정 후 `AppDelegate.swift` 전체는 다음과 같아야 한다:

```swift
import AppKit
import PasterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var environment: AppEnvironment?
    private var monitor: ClipboardMonitor?
    private var scheduler: RetentionScheduler?
    private var panelController: PanelController?
    private var settingsWindow: SettingsWindowController?
    private let updater = UpdaterService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment()
        } catch {
            Log.app.fault("저장소를 열 수 없음: \(String(describing: error), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Paster 저장소를 열 수 없습니다"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.environment = environment

        let panelController = PanelController(environment: environment)
        self.panelController = panelController

        let monitor = ClipboardMonitor(store: environment.store, settings: environment.settings)
        monitor.onSaved = { [weak panelController] in panelController?.reloadIfVisible() }
        monitor.start()
        self.monitor = monitor

        let scheduler = RetentionScheduler(service: environment.retention, settings: environment.settings)
        scheduler.onPurged = { [weak panelController] in panelController?.reloadIfVisible() }
        scheduler.start()
        self.scheduler = scheduler

        settingsWindow = SettingsWindowController(environment: environment, updater: updater) { [weak panelController] in
            panelController?.reloadIfVisible()
        }

        HotkeyService.register { [weak panelController] in panelController?.toggle() }
        AccessibilityPermission.requestOnFirstLaunch()
        statusItem = makeStatusItem()
    }

    // MARK: 메뉴바

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Paster")
        item.menu = makeMenu()
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Paster 열기", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let version = NSMenuItem(title: Self.versionTitle, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(updater.makeMenuItem())

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    static var versionTitle: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Paster \(short) (\(build))"
    }

    @objc private func openPanel() {
        panelController?.show()
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }
}
```

- [ ] **Step 6: SettingsWindowController 수정**

`Sources/Paster/Settings/SettingsWindowController.swift` 에서

찾을 코드:

```swift
    init(environment: AppEnvironment, onDataChanged: @escaping () -> Void) {
        model = SettingsModel(environment: environment, onDataChanged: onDataChanged)
```

바꿀 코드:

```swift
    init(environment: AppEnvironment, updater: UpdaterService, onDataChanged: @escaping () -> Void) {
        model = SettingsModel(environment: environment, updater: updater, onDataChanged: onDataChanged)
```

- [ ] **Step 7: SettingsModel 수정**

`Sources/Paster/Settings/SettingsModel.swift` 에서

찾을 코드:

```swift
    private(set) var launchAtLogin: Bool
```

바꿀 코드:

```swift
    private(set) var launchAtLogin: Bool
    var automaticallyChecksForUpdates: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
```

찾을 코드:

```swift
    @ObservationIgnored private let onDataChanged: () -> Void

    init(environment: AppEnvironment, onDataChanged: @escaping () -> Void) {
        settings = environment.settings
        store = environment.store
        self.onDataChanged = onDataChanged
        retention = environment.settings.retention
        launchAtLogin = SMAppService.mainApp.status == .enabled
```

바꿀 코드:

```swift
    @ObservationIgnored private let onDataChanged: () -> Void
    @ObservationIgnored private let updater: UpdaterService

    init(environment: AppEnvironment, updater: UpdaterService, onDataChanged: @escaping () -> Void) {
        settings = environment.settings
        store = environment.store
        self.updater = updater
        self.onDataChanged = onDataChanged
        retention = environment.settings.retention
        launchAtLogin = SMAppService.mainApp.status == .enabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
```

- [ ] **Step 8: SettingsView 수정**

`Sources/Paster/Settings/SettingsView.swift` 에서

찾을 코드:

```swift
                extraGeneralRows
```

바꿀 코드:

```swift
                Toggle("자동으로 업데이트 확인", isOn: $model.automaticallyChecksForUpdates)
```

그리고 자리표시를 지운다. 찾을 코드(아래 블록과 그 뒤 빈 줄 하나):

```swift
    /// 플랜 3 에서 "자동으로 업데이트 확인" 체크박스를 여기에 넣는다.
    @ViewBuilder
    private var extraGeneralRows: some View {
        EmptyView()
    }
```

바꿀 코드: (없음 — 삭제)

- [ ] **Step 9: 빌드 · rpath 확인**

Run: `swift build 2>&1 | grep -E "error|warning:" ; swift build 2>&1 | tail -1 && otool -l "$(swift build --show-bin-path)/Paster" | grep -A2 LC_RPATH | grep Frameworks && ls "$(swift build --show-bin-path)" | grep -E "Sparkle.framework$"`
Expected: `Build complete!`, `path @executable_path/../Frameworks (offset 12)`, `Sparkle.framework`

Run: `swift test 2>&1 | tail -1`
Expected: `✔ Test run with 117 tests in 17 suites passed ...`

이 시점에는 `make run`(dev-bundle.sh)이 Sparkle.framework 를 복사하지 않으므로 앱이 실행되지 않는다. Task 4 에서 `make run` 을 bundle.sh 로 바꾼다.

- [ ] **Step 10: 커밋**

```bash
git add Package.swift Package.resolved Sources/Paster/Update/UpdaterService.swift Sources/Paster/App/AppDelegate.swift Sources/Paster/Settings/SettingsWindowController.swift Sources/Paster/Settings/SettingsModel.swift Sources/Paster/Settings/SettingsView.swift
git commit -m "feat(app): integrate Sparkle updater with menu item and settings toggle" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Sparkle EdDSA 키

스펙 13절: `make sparkle-keys` 가 `generate_keys` 를 1회 실행, 개인 키는 로그인 키체인, Info.plist 에는 공개 키만.

**Files:**
- Modify: `Makefile` (전체 교체)
- Create (명령 출력): `Resources/sparkle-public-key.txt`

- [ ] **Step 1: Makefile 교체 (`sparkle-keys` 추가)**

```make
SPARKLE_BIN := .build/artifacts/sparkle/Sparkle/bin

.PHONY: cert test run sparkle-keys

# 최초 1회: 자체 서명 인증서 "Paster Local Signing" (로그인 암호 입력 필요)
cert:
	./scripts/make-cert.sh

test:
	swift test

# 개발용 실행: debug .app 을 만들어 연다
run:
	./scripts/dev-bundle.sh
	-pkill -x Paster && sleep 1
	open build/debug/Paster.app

# 최초 1회: Sparkle EdDSA 키 생성 (개인 키는 로그인 키체인, 공개 키는 Resources/sparkle-public-key.txt)
sparkle-keys:
	swift package resolve
	$(SPARKLE_BIN)/generate_keys
	$(SPARKLE_BIN)/generate_keys -p > Resources/sparkle-public-key.txt
	@echo "공개 키: $$(cat Resources/sparkle-public-key.txt)"
```

- [ ] **Step 2: 키 생성 (대화형)**

Run: `mkdir -p Resources && make sparkle-keys`

키체인 접근 허용 창이 뜨면 허용한다. 이미 이 Mac 에 Sparkle 키가 있으면 새로 만들지 않고 기존 키를 쓴다 (generate_keys 기본 동작).

Expected 마지막 줄: `공개 키: <44자 base64, = 로 끝남>`. 그리고:

Run: `tr -d '[:space:]' < Resources/sparkle-public-key.txt | wc -c | tr -d ' '`
Expected: `44`

- [ ] **Step 3: 개인 키 백업**

Run: `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/paster-sparkle-private-key.txt && ls -l ~/paster-sparkle-private-key.txt`

이 파일을 안전한 곳(비밀번호 관리자 등)으로 옮기고 홈 디렉터리에서 지운다. **저장소에 절대 넣지 않는다.**

- [ ] **Step 4: 커밋 (공개 키만)**

```bash
git add Makefile Resources/sparkle-public-key.txt
git commit -m "build: add Sparkle EdDSA public key and sparkle-keys target" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Info.plist · bundle.sh · make app / install / run

스펙 12절(`make app`: release 빌드 → `build/Paster.app` 조립(LSUIElement, 번들 ID) → 인증서로 서명, `make install`: `/Applications` 로 복사), 13절(버전: `CFBundleShortVersionString` = `VERSION`, `CFBundleVersion` = `git rev-list --count HEAD`, `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` 미지정).

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`
- Delete: `scripts/dev-bundle.sh`
- Modify: `Makefile` (전체 교체)

- [ ] **Step 1: Info.plist 템플릿 작성**

`Resources/Info.plist` — 버전 두 개와 `SUPublicEDKey` 는 bundle.sh 가 PlistBuddy 로 채운다.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>ko</string>
	<key>CFBundleExecutable</key>
	<string>Paster</string>
	<key>CFBundleIdentifier</key>
	<string>com.wjbyun.Paster</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Paster</string>
	<key>CFBundleDisplayName</key>
	<string>Paster</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.0.0</string>
	<key>CFBundleVersion</key>
	<string>0</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© Woojin Byun</string>
	<key>SUFeedURL</key>
	<string>https://github.com/WoojinByun/Paster/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string></string>
</dict>
</plist>
```

Run: `plutil -lint Resources/Info.plist`
Expected: `Resources/Info.plist: OK`

- [ ] **Step 2: bundle.sh 작성**

`scripts/bundle.sh`:

```bash
#!/bin/bash
# build/Paster.app 을 조립하고 서명한다.
# 사용법: scripts/bundle.sh [release|debug]
# 환경 변수: VERSION (기본 0.0.0), SIGN_IDENTITY (기본 "Paster Local Signing", "-" 면 ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="${VERSION:-0.0.0}"
IDENTITY="${SIGN_IDENTITY:-Paster Local Signing}"
BUILD_NUMBER="$(git rev-list --count HEAD)"
KEY_FILE="Resources/sparkle-public-key.txt"
APP="build/Paster.app"
PLIST_BUDDY=/usr/libexec/PlistBuddy

if [ ! -s "$KEY_FILE" ]; then
    echo "error: $KEY_FILE 가 없습니다. 먼저 'make sparkle-keys' 를 실행하세요." >&2
    exit 1
fi
if [ "$IDENTITY" != "-" ] && ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "error: 인증서 '$IDENTITY' 가 없습니다. 먼저 'make cert' 를 실행하세요." >&2
    exit 1
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Paster" "$APP/Contents/MacOS/Paster"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# 심볼릭 링크를 유지해야 하므로 ditto 로 복사한다
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

cp Resources/Info.plist "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :SUPublicEDKey $(tr -d '[:space:]' < "$KEY_FILE")" "$APP/Contents/Info.plist"

if ! otool -l "$APP/Contents/MacOS/Paster" | grep -q "@executable_path/../Frameworks"; then
    echo "error: 실행 파일에 rpath @executable_path/../Frameworks 가 없습니다 (Package.swift linkerSettings 확인)." >&2
    exit 1
fi

# 안쪽부터 서명: Sparkle XPC 서비스 · 도우미 → 프레임워크 → 앱
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$IDENTITY" "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" "$SPARKLE/Autoupdate"
codesign --force --sign "$IDENTITY" "$SPARKLE/Updater.app"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "$APP ($VERSION, build $BUILD_NUMBER, $CONFIG)"
```

Run: `chmod +x scripts/bundle.sh && bash -n scripts/bundle.sh && echo syntax-ok`
Expected: `syntax-ok`

- [ ] **Step 3: dev-bundle.sh 삭제, Makefile 교체**

Run: `git rm scripts/dev-bundle.sh`

`Makefile`:

```make
VERSION ?= 0.0.0
SPARKLE_BIN := .build/artifacts/sparkle/Sparkle/bin

.PHONY: cert app install test run sparkle-keys

# 최초 1회: 자체 서명 인증서 "Paster Local Signing" (로그인 암호 입력 필요)
cert:
	./scripts/make-cert.sh

# build/Paster.app (release) 빌드 + 서명
app:
	VERSION=$(VERSION) ./scripts/bundle.sh release

# /Applications 로 복사하고 실행
install: app
	-pkill -x Paster && sleep 1
	rm -rf /Applications/Paster.app
	ditto build/Paster.app /Applications/Paster.app
	open /Applications/Paster.app

test:
	swift test

# 개발용 실행: debug 빌드를 같은 인증서로 서명해 연다
run:
	VERSION=$(VERSION) ./scripts/bundle.sh debug
	-pkill -x Paster && sleep 1
	open build/Paster.app

# 최초 1회: Sparkle EdDSA 키 생성 (개인 키는 로그인 키체인, 공개 키는 Resources/sparkle-public-key.txt)
sparkle-keys:
	swift package resolve
	$(SPARKLE_BIN)/generate_keys
	$(SPARKLE_BIN)/generate_keys -p > Resources/sparkle-public-key.txt
	@echo "공개 키: $$(cat Resources/sparkle-public-key.txt)"
```

- [ ] **Step 4: 번들 확인**

Run: `make app VERSION=0.0.1`
Expected 마지막 줄: `build/Paster.app (0.0.1, build <커밋 수>, release)`

Run:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" -c "Print :SUPublicEDKey" -c "Print :SUFeedURL" build/Paster.app/Contents/Info.plist
codesign -dv --verbose=2 build/Paster.app 2>&1 | grep -E "^Identifier|^Authority"
codesign -d -r- build/Paster.app 2>&1 | grep designated
ls build/Paster.app/Contents/Frameworks build/Paster.app/Contents/Resources
```

Expected:
- `0.0.1`, `<git rev-list --count HEAD 값>`, `<Resources/sparkle-public-key.txt 내용>`, `https://github.com/WoojinByun/Paster/releases/latest/download/appcast.xml`
- `Identifier=com.wjbyun.Paster`, `Authority=Paster Local Signing`
- `designated => identifier "com.wjbyun.Paster" and certificate leaf = H"<해시>"` — 이 줄을 적어 둔다.
- `Sparkle.framework` / `GRDB_GRDB.bundle  KeyboardShortcuts_KeyboardShortcuts.bundle`

- [ ] **Step 5: 서명 고정 확인**

Run: `make app VERSION=0.0.1 >/dev/null && codesign -d -r- build/Paster.app 2>&1 | grep designated`
Expected: Step 4 와 **똑같은** designated 줄 (재빌드해도 바뀌지 않음 → 손쉬운 사용 권한 유지).

- [ ] **Step 6: 설치 · 실행 확인 (수동)**

Run: `make install`

- 메뉴바 아이콘이 뜨고, 메뉴 두 번째 줄이 `Paster 0.0.0 (<커밋 수>)` 다 (`make install` 은 기본 `VERSION=0.0.0`).
- 시스템 설정 → 손쉬운 사용에서 플랜 2 때의 ad-hoc Paster 항목을 `-` 로 지우고 `/Applications/Paster.app` 을 허용한다.
- 패널에서 Enter 로 TextEdit 에 붙여넣기가 된다.
- 아무 Swift 파일에 주석 한 줄을 넣고 `make install` 을 다시 한 뒤에도 Enter 붙여넣기가 권한 요청 없이 된다 (권한 유지). 확인 후 주석은 `git checkout -- <파일>` 로 되돌린다.
- 메뉴 `업데이트 확인…` 이 활성화되어 있고, 누르면 Sparkle 창이 뜬다 (아직 릴리스가 없으므로 피드를 받지 못했다는 오류가 정상).
- 설정에 "자동으로 업데이트 확인" 이 켜져 있다. `defaults read com.wjbyun.Paster SUEnableAutomaticChecks` → `1`.
- 설정의 "로그인 시 실행" 을 켜면 시스템 설정 → 일반 → 로그인 항목에 Paster 가 생긴다.

- [ ] **Step 7: make run 확인**

Run: `make run`
Expected: `build/Paster.app (0.0.0, build <커밋 수>, debug)` 후 앱 실행. (`/Applications` 의 Paster 는 `pkill` 로 먼저 종료된다.)

- [ ] **Step 8: 커밋**

```bash
git add Resources/Info.plist scripts/bundle.sh Makefile
git commit -m "build: assemble and sign Paster.app with Sparkle framework" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`git rm` 한 `scripts/dev-bundle.sh` 삭제도 이 커밋에 들어간다.)

---

### Task 5: 릴리스 스크립트

스펙 13절 `make release VERSION=x.y.z` 순서: ① release 빌드 ② 조립 ③ "Paster Local Signing" 서명 ④ `ditto -c -k --keepParent` zip ⑤ `generate_appcast`(키체인 EdDSA 키) ⑥ `gh release create vX.Y.Z` 로 zip + `appcast.xml` 업로드. appcast 의 다운로드 URL 은 `https://github.com/WoojinByun/Paster/releases/download/vX.Y.Z/` 아래 zip 이다. `SUFeedURL` 이 `releases/latest/download/appcast.xml` 이므로 매 릴리스의 appcast 에는 그 릴리스 항목 하나만 있으면 된다.

안전장치: 버전 형식 검사, `0.0.0` 거부, 커밋 안 된 변경 거부, HEAD 가 origin 에 없으면 거부, 같은 태그 릴리스가 있으면 거부. 릴리스 노트는 직전 태그 이후 커밋 제목으로 `build/release-X.Y.Z/Paster-X.Y.Z.md` 를 만들고, generate_appcast(`--embed-release-notes`)와 `gh release` 가 같이 쓴다.

**Files:**
- Create: `scripts/release.sh`
- Modify: `Makefile` (전체 교체)

- [ ] **Step 1: 스크립트 작성**

`scripts/release.sh`:

```bash
#!/bin/bash
# 릴리스: 빌드 · 서명 · zip · appcast · GitHub Release 업로드 (스펙 13절).
# 사용법: scripts/release.sh X.Y.Z   (make release VERSION=X.Y.Z)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: 버전은 x.y.z 형식이어야 합니다 (예: make release VERSION=0.1.0)" >&2
    exit 1
fi
if [ "$VERSION" = "0.0.0" ]; then
    echo "error: 0.0.0 은 개발 빌드 전용입니다. VERSION 을 지정하세요." >&2
    exit 1
fi
TAG="v$VERSION"
REPO="WoojinByun/Paster"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
OUT="build/release-$VERSION"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: 커밋하지 않은 변경이 있습니다." >&2
    exit 1
fi
git fetch origin --tags --quiet
if [ -z "$(git branch -r --contains HEAD)" ]; then
    echo "error: HEAD 가 origin 에 없습니다. 먼저 push 하세요." >&2
    exit 1
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "error: $TAG 릴리스가 이미 있습니다." >&2
    exit 1
fi

# 1~3. release 빌드, Paster.app 조립, "Paster Local Signing" 서명
VERSION="$VERSION" ./scripts/bundle.sh release

# 4. zip
rm -rf "$OUT"
mkdir -p "$OUT"
ZIP="$OUT/Paster-$VERSION.zip"
ditto -c -k --keepParent build/Paster.app "$ZIP"

# 릴리스 노트: 직전 태그 이후 커밋 제목. 같은 이름의 .md 를 generate_appcast 가 읽는다.
NOTES="$OUT/Paster-$VERSION.md"
PREVIOUS_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
{
    echo "# Paster $VERSION"
    echo
    if [ -n "$PREVIOUS_TAG" ]; then
        git log --pretty='- %s' "$PREVIOUS_TAG..HEAD"
    else
        git log --pretty='- %s'
    fi
} > "$NOTES"

# 5. appcast (로그인 키체인의 EdDSA 개인 키로 서명)
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes \
    -o "$OUT/appcast.xml" \
    "$OUT"

# 6. GitHub Release: zip 과 appcast.xml 업로드
gh release create "$TAG" "$ZIP" "$OUT/appcast.xml" \
    --repo "$REPO" \
    --target "$(git rev-parse HEAD)" \
    --title "Paster $VERSION" \
    --notes-file "$NOTES"

echo "릴리스 완료: https://github.com/$REPO/releases/tag/$TAG"
```

Run: `chmod +x scripts/release.sh && bash -n scripts/release.sh && echo syntax-ok`
Expected: `syntax-ok`

- [ ] **Step 2: Makefile 교체 (최종)**

```make
VERSION ?= 0.0.0
SPARKLE_BIN := .build/artifacts/sparkle/Sparkle/bin

.PHONY: cert app install test run sparkle-keys release

# 최초 1회: 자체 서명 인증서 "Paster Local Signing" (로그인 암호 입력 필요)
cert:
	./scripts/make-cert.sh

# build/Paster.app (release) 빌드 + 서명
app:
	VERSION=$(VERSION) ./scripts/bundle.sh release

# /Applications 로 복사하고 실행
install: app
	-pkill -x Paster && sleep 1
	rm -rf /Applications/Paster.app
	ditto build/Paster.app /Applications/Paster.app
	open /Applications/Paster.app

test:
	swift test

# 개발용 실행: debug 빌드를 같은 인증서로 서명해 연다
run:
	VERSION=$(VERSION) ./scripts/bundle.sh debug
	-pkill -x Paster && sleep 1
	open build/Paster.app

# 최초 1회: Sparkle EdDSA 키 생성 (개인 키는 로그인 키체인, 공개 키는 Resources/sparkle-public-key.txt)
sparkle-keys:
	swift package resolve
	$(SPARKLE_BIN)/generate_keys
	$(SPARKLE_BIN)/generate_keys -p > Resources/sparkle-public-key.txt
	@echo "공개 키: $$(cat Resources/sparkle-public-key.txt)"

release:
	./scripts/release.sh $(VERSION)
```

- [ ] **Step 3: 안전장치 확인 (업로드 없음)**

Run: `make release VERSION=1.0 ; make release`
Expected: `error: 버전은 x.y.z 형식이어야 합니다 ...` 와 `error: 0.0.0 은 개발 빌드 전용입니다. VERSION 을 지정하세요.` (둘 다 make 가 `Error 1` 로 끝남)

- [ ] **Step 4: 커밋**

```bash
git add scripts/release.sh Makefile
git commit -m "build: add release script for zip, appcast and GitHub Release" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 첫 릴리스 · 자동 업데이트 수동 확인

스펙 11절 "자동 업데이트 수동 확인: 더 높은 버전의 테스트 release 를 올린 뒤 `업데이트 확인…` 으로 감지 · 설치 · 재실행 확인". **공개 저장소에 릴리스가 올라가므로 사용자에게 진행 여부를 먼저 확인한다.**

**Files:** 없음 (태그 · 릴리스만 만든다)

- [ ] **Step 1: 사전 확인**

Run: `gh auth status && git status --short && git log origin/Paster..HEAD --oneline`
Expected: 로그인 상태, 변경 없음, 출력 없음 (push 완료). push 가 안 됐으면 `git -c credential.helper='!gh auth git-credential' push origin Paster`.

릴리스 태그는 현재 HEAD 를 가리킨다. 기본 브랜치(main)에 병합한 뒤 릴리스할지 사용자에게 확인한다.

- [ ] **Step 2: v0.1.0 릴리스**

Run: `make release VERSION=0.1.0`
Expected 마지막 줄: `릴리스 완료: https://github.com/WoojinByun/Paster/releases/tag/v0.1.0`

Run: `curl -sL https://github.com/WoojinByun/Paster/releases/latest/download/appcast.xml | grep -E "shortVersionString|enclosure"`
Expected: `<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>` 와 `url="https://github.com/WoojinByun/Paster/releases/download/v0.1.0/Paster-0.1.0.zip"` 가 든 enclosure.

- [ ] **Step 3: 0.1.0 설치**

Run: `make install VERSION=0.1.0` (방금 릴리스와 같은 빌드 번호)

메뉴 두 번째 줄이 `Paster 0.1.0 (<N>)` 인지 확인.

- [ ] **Step 4: 더 높은 버전으로 업데이트 확인**

빌드 번호가 올라가도록 빈 커밋을 하나 만들고 push 한 뒤 릴리스한다:

```bash
git commit --allow-empty -m "chore: release 0.1.1 for update test" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -c credential.helper='!gh auth git-credential' push origin Paster
make release VERSION=0.1.1
```

설치된 0.1.0 앱에서 메뉴 → `업데이트 확인…`:
- Sparkle 창이 0.1.1 과 릴리스 노트(커밋 제목 목록)를 보여준다.
- 설치 → 앱이 재실행되고 메뉴가 `Paster 0.1.1 (<N+1>)` 이다.
- 업데이트 후에도 Enter 붙여넣기가 권한 요청 없이 된다 (같은 인증서).

- [ ] **Step 5: Gatekeeper 안내 확인**

브라우저로 Releases 에서 `Paster-0.1.1.zip` 을 받아 풀면 처음 실행이 차단되는 것(notarize 안 됨)과, README 의 "그래도 열기" 또는 `xattr -dr com.apple.quarantine` 로 열리는 것을 확인한다. Sparkle 로 받은 업데이트에는 이 문제가 없다.

---

### Task 7: README 갱신

구현이 끝났으므로 README 의 "개발 중" / "구현 예정" 표시를 지운다. 다른 작업자가 README 를 고쳤을 수 있으므로 **먼저 현재 내용을 읽고** 아래 표시만 정확히 고친다.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 표시 위치 찾기**

Run: `git pull --ff-only origin Paster 2>/dev/null; grep -nE "개발 중|구현 예정|🚧" README.md`
Expected (작성 시점 README 기준):

```
5:> 🚧 개발 중 — 첫 릴리스(v0.1.0) 전입니다.
<N>:Xcode 16+ / Swift 6 필요. 아래 명령은 구현이 들어오면 사용할 수 있습니다 (구현 예정).
```

- [ ] **Step 2: 배너 삭제**

찾을 코드 (줄 전체와 그 뒤 빈 줄 하나):

```markdown
> 🚧 개발 중 — 첫 릴리스(v0.1.0) 전입니다.

```

바꿀 코드: (없음 — 삭제)

- [ ] **Step 3: 빌드 안내 문장 수정 · make run 추가**

찾을 코드:

````markdown
Xcode 16+ / Swift 6 필요. 아래 명령은 구현이 들어오면 사용할 수 있습니다 (구현 예정).

```sh
make cert      # 최초 1회: 자체 서명 인증서 "Paster Local Signing" 생성
make app       # build/Paster.app 빌드 + 서명
make install   # /Applications 로 복사
make test      # swift test
```
````

바꿀 코드:

````markdown
Xcode 16+ / Swift 6 필요.

```sh
make cert      # 최초 1회: 자체 서명 인증서 "Paster Local Signing" 생성 (로그인 암호 입력)
make app       # build/Paster.app 빌드 + 서명
make install   # /Applications 로 복사 후 실행
make run       # debug 빌드로 실행 (개발용)
make test      # swift test
```

`make app` / `make run` 은 Sparkle 공개 키 파일(`Resources/sparkle-public-key.txt`, 저장소에 포함)이 필요합니다.
````

(README 가 이미 바뀌어 위 문장이 없으면, 같은 의미의 "구현 예정" / "개발 중" 표현만 지우고 명령 목록에 `make run` 을 더한다.)

- [ ] **Step 4: 확인**

Run: `grep -cE "개발 중|구현 예정|🚧" README.md`
Expected: `0`

- [ ] **Step 5: 커밋**

```bash
git add README.md
git commit -m "docs: mark README as released" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 스펙 대응표

스펙의 모든 절이 어느 플랜 · Task 에서 구현 · 검증되는지. (P1 = 플랜 1, P2 = 플랜 2, P3 = 플랜 3)

| 스펙 | 내용 | 구현 | 검증 |
|---|---|---|---|
| 1 | 개요: 텍스트 / 이미지 / 파일 저장, 단축키 패널에서 검색 · 붙여넣기 | P1 전체, P2 전체 | P2 T7 체크리스트 |
| 2 | 비목표 (Snippets, Merging, 동기화, 파일 사본, Space Quick Look, App Store/샌드박스) | 구현하지 않음. 파일은 경로만 저장(P1 T5), Space 는 검색 입력(P1 T15 `typingIsTextInput`), 샌드박스 없음(P3 T4 Info.plist · 서명에 entitlements 없음) | — |
| 3.1 | 메뉴바 상주 `LSUIElement`, 비샌드박스, SwiftUI + NSPanel, PasterCore / Paster 분리, 의존성 3개, `SMAppService.mainApp`, macOS 15, Swift 6 | P1 T1, P2 T1 · T5 · T6, P3 T2 · T4 | P2 T1 S8, P3 T4 S6 |
| 3.2 | AppDelegate | P2 T1 → T6, P3 T2 | P2 T1 S8 |
| 3.2 | ClipboardMonitor (0.5초 `changeCount`) | P2 T2 | P2 T2 S6 |
| 3.2 | ClipCapture (가짜 pasteboard 로 테스트) | P1 T5 (`PasteboardSnapshot`) | P1 `ClipCaptureTests` |
| 3.2 | ClipStore (GRDB + FTS5) | P1 T7 ~ T11 | P1 `ClipStore*Tests` |
| 3.2 | BlobStore | P1 T6 | P1 `BlobStoreTests` |
| 3.2 | RetentionService | P1 T13, P2 T3 | P1 `RetentionServiceTests`, P2 T3 S4 |
| 3.2 | HotkeyService | P2 T5 | P2 T5 S11 |
| 3.2 | PanelController (non-activating, 직전 앱 기억) | P2 T5 | P2 T5 S11 |
| 3.2 | PanelView | P2 T5 | P2 T5 S11 |
| 3.2 | PasteService (쓰기 → 활성화 → ⌘V, 일반 텍스트) | P2 T4, T5 | P2 T7 |
| 3.2 | SettingsView | P2 T6, P3 T2 | P2 T6 S6, P3 T4 S6 |
| 3.2 | SPUStandardUpdaterController | P3 T2 | P3 T6 |
| 3.3 | 메뉴바 메뉴 항목 · 순서 · 버전 줄 | P2 T1, P3 T2 | P2 T1 S8, P3 T4 S6 |
| 4 | 저장 위치, `paster.sqlite`, `blobs/<uuid>.png`, UserDefaults, 번들 ID `com.wjbyun.Paster` | P1 T6 · T7 · T11 · T12, P2 T2, P3 T4 | P1 `ClipStoreOpenTests`, P3 T4 S4 |
| 4 | `clip_items` 칼럼 전부, `content_hash` UNIQUE | P1 T2 · T7 | P1 `ClipStoreSaveTests` |
| 5.1 | concealed / transient / auto-generated / 제외 앱 / 자체 마커 / 꺼진 타입 건너뜀 | P1 T5 · T12, P2 T2 (마커 있으면 내용 안 읽음) | P1 `markerTypesAreSkipped`, `excludedAppIsSkipped`, `disabledKindIsSkipped` |
| 5.2 | 파일 > 텍스트 > 이미지 | P1 T5 | P1 `filesWinOverTextAndImage`, `textWinsOverImage`, `emptyStringFallsBackToImage` |
| 5.3 | PNG 저장, 붙여넣기 PNG + TIFF, 100MB 초과 건너뜀 + 로그 | P1 T4 · T5, P2 T4 | P1 `imageOverLimitIsSkipped`, `pngConvertsToTIFF` |
| 5.4 | 중복: `last_copied_at` · 출처 갱신 | P1 T7 | P1 `sameHashBumpsInsteadOfInserting` |
| 6 | trigram, 1~2글자 LIKE, 대상(본문 · 파일명 · 앱 이름), 두 칼럼 필터 | P1 T8 | P1 `ClipStoreSearchTests` |
| 7.1 | 타입별 켬/끔 · 기간, 기본 3개월, 꺼진 타입 유지, 만료 조건, blob · 고아 정리, Pin 무만료, 해제 시 now, 조회 시 제외, Clear All 은 미고정만 + 확인 | P1 T3 · T8 · T9 · T10, P2 T6 | P1 `RetentionSettingsTests`, `expiredItemsAreHiddenBeforePurge`, `disabledKindKeepsShowingUntilItsPeriodEnds`, `unpinResetsLastCopiedAt...`, `deleteExpired...`, `deleteAllUnpinnedKeepsPinned`, P2 T6 S6 |
| 7.2 | 0시 타이머 · 재설정, 실행 시, 깨어난 뒤 날짜 변경 시, 시계 · 시간대 변경 시 재설정, 마지막 정리 날짜 UserDefaults | P1 T13, P2 T3 | P1 `RetentionScheduleTests`, `purgeIfDayChangedRunsOncePerDay`, P2 T3 S4 |
| 8.1 | ⌃⌥⌘V(변경 가능), 메뉴로 열기, 마우스 화면 중앙 760×520, 바깥 클릭 닫힘, Esc | P2 T5 · T6, P1 T14 | P1 `escape*`, P2 T5 S11 |
| 8.2 | 레이아웃 | P2 T5 | P2 T5 S11 |
| 8.3 | 포커스 이동 규칙 전부, 칼럼별 선택 기억, Clipboard 는 미고정만, Pinned 는 `pin_order` | P1 T8 · T14, P2 T5 | P1 `PanelNavigationTests`, `pinnedAreExcludedFromUnpinnedAndOrderedByPinOrder` |
| 8.4 | 키 표 전부 | P1 T14 · T15, P2 T5 | P1 `PanelActionTests`, `PanelKeyMapperTests`, P2 T7 |
| 8.5 | 행: 아이콘 + 제목(텍스트 첫 줄 / `Image: WxH (크기)` / `파일: a 외 N개`), ⚠, 포커스 칼럼만 ⌘숫자, 빈 Pinned 안내 | P1 T2 (`title`, `missingFilePaths`), P2 T5 | P1 `ClipItemTests`, P2 T7 |
| 8.6 | 미리보기 띠 (텍스트 스크롤 / 이미지 fit / 파일 경로 + 존재 / 메타 줄) | P2 T5 | P2 T7 |
| 9.1 | 직전 앱 기억, 마커 포함 쓰기, `last_copied_at` 갱신, 닫고 활성화 후 ⌘V, 일반 텍스트는 string 만, 파일은 file URL, 원본 없으면 "원본 파일이 없습니다" | P2 T4 · T5, P1 T7 (`touch`) | P2 T7 |
| 9.2 | 첫 실행 `AXIsProcessTrustedWithOptions`, 권한 없으면 복사만 + 안내, 자체 인증서로 권한 유지 | P2 T4 · T5, P3 T1 · T4 | P2 T7, P3 T4 S5 · S6 |
| 10 | DB 손상 → `.corrupt-<timestamp>` 보존 후 새 DB, 이미지 실패 / 100MB 로그, `os.Logger` subsystem, 내용 미기록 | P1 T1 · T5 · T11 | P1 `corruptDatabaseIsPreservedAndReplaced`, `imageOverLimitIsSkipped` |
| 11 | `swift test` 대상 PasterCore, 각 테스트 범주, 수동 체크리스트, 자동 업데이트 수동 확인 | P1 전체, P2 T7, P3 T6 | — |
| 12 | 인증서 없음 → 자체 서명, `make cert / app / install / test / sparkle-keys / release` | P3 T1 · T3 · T4 · T5 (`make test` 는 P2 T1) | P3 T4 S4 · S5 |
| 13 | SPUStandardUpdaterController, 메뉴 `checkForUpdates`, 체크박스 ↔ `automaticallyChecksForUpdates` 기본 ON, `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` 미지정, 키는 키체인 · 공개 키만 커밋, 버전 규칙, release 6단계, 서명 연속성 · 백업 안내, notarize 없음 | P3 T2 · T3 · T4 · T5, README(P3 T7) | P3 T4 S6, T6 |
| 14 | 레포 구조 (`Package.swift`, `Sources/PasterCore`, `Sources/Paster`, `Tests/PasterCoreTests`, `Resources/Info.plist`, `scripts/`, `Makefile`, `README.md`) | P1 T1, P2 T1, P3 T1 · T4 | — |
