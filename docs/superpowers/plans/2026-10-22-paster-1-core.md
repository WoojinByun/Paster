# Paster 1/3 — PasterCore 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SwiftPM 패키지 골격과, UI 없이 `swift test` 로 전부 검증되는 `PasterCore` 라이브러리(모델 · 캡처 · 저장 · 검색 · 보관 정책 · 패널 키 리듀서)를 만든다.

**Architecture:** `PasterCore` 는 Foundation · CoreGraphics · ImageIO · CryptoKit · GRDB 에만 의존하고 AppKit 을 쓰지 않는다. pasteboard 는 값 타입 `PasteboardSnapshot` 으로 추상화하고, 저장소는 GRDB `DatabaseQueue`(Sendable) 위의 `ClipStore` 하나로 모은다. 패널 키 처리는 순수 함수 `PanelReducer.reduce(PanelState, PanelKey) -> (PanelState, PanelEffect?)` 로 분리한다.

**Tech Stack:** Swift 6.4 (Xcode 27.1, Swift 6 language mode, strict concurrency), SwiftPM, GRDB.swift 7.11.1, SQLite 3.54 (시스템) FTS5 `trigram`, Swift Testing (`import Testing`).

**스펙:** `docs/superpowers/specs/2026-10-22-paster-design.md` (이하 "스펙"). 이 계획은 3개 중 첫 번째이며, 플랜 2(`2026-10-22-paster-2-app.md`)와 플랜 3(`2026-10-22-paster-3-release.md`)이 여기서 정의한 이름을 그대로 쓴다.

---

## 작업 환경

- 작업 디렉터리: `/Users/woojin/work/ridi/worktrees/Paster/Paster` (브랜치 `Paster`). 모든 명령은 여기서 실행한다.
- 같은 브랜치에서 다른 작업자가 `README.md` 를 커밋할 수 있다. **`git add` 는 항상 이 계획이 지정한 파일만** 한다 (`git add -A`, `git add .` 금지). `index.lock` 오류가 나면 몇 초 기다렸다 다시 시도한다. bare `git stash` 금지.
- 커밋 메시지 끝에는 항상 다음 trailer 를 붙인다: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- 사전 확인 (한 번):

```bash
swift --version
sqlite3 --version
```

Expected: `Apple Swift version 6.4 ...` 와 `3.54.0 ...` (SQLite 3.34 이상이면 FTS5 `trigram` 사용 가능).

## 검증해 둔 사실

계획 작성 시 이 Mac(Xcode 27.1, Swift 6.4, macOS 27 arm64)에서 직접 확인했다.

- **GRDB 7.11.1** 의 `Package.swift` 는 `SQLITE_ENABLE_FTS5` 를 정의하므로 시스템 SQLite 로도 GRDB 의 FTS5 Swift API 가 켜진다. 다만 `trigram` 토크나이저용 Swift 헬퍼는 없으므로 이 계획은 **raw SQL** 로 `CREATE VIRTUAL TABLE ... USING fts5(..., content='clip_items', content_rowid='id', tokenize='trigram')` 와 동기화 트리거를 만든다. 시스템 SQLite 3.54.0 에서 한글 3글자 부분 문자열 검색이 동작함을 확인했다.
- **Swift Testing** 은 `swift test` 로 바로 돈다. 출력 마지막 줄 형식: `✔ Test run with N tests in M suites passed after ...`. 매개변수화 테스트(`@Test(arguments:)`)는 1개로 센다. `swift test --filter <SuiteName>` 도 동작한다.
- 설정 저장소는 `SettingsStore` 프로토콜(`AnyObject, Sendable`)로 추상화하고 `UserDefaults` 가 그대로 따른다. 테스트는 메모리 저장소를 써서 `~/Library/Preferences` 에 plist 를 남기지 않는다 (cfprefsd 가 프로세스 종료 뒤에 파일을 다시 쓰기 때문).
- `URL(fileURLWithPath:).lastPathComponent` 는 한글을 NFD(자모 분해)로 돌려줄 수 있다. NFD 로 저장하면 NFC 검색어와 trigram 이 맞지 않으므로, 파일명은 저장 전에 `precomposedStringWithCanonicalMapping` 으로 NFC 로 맞춘다 (테스트로 확인). 검색은 저장된 텍스트가 NFC 든 NFD 든 찾을 수 있도록 검색어의 NFC · NFD 두 형태를 모두 매칭한다 (Task 8).
- `Calendar.nextDate(after:matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)` 은 0시가 없는 날(2018-11-04 상파울루)에 그날 01:00 을 돌려준다.

## 스펙과 다르게 정한 점

- 스펙 3.2절은 ClipCapture 가 `PasteboardReading` 프로토콜에 의존한다고 적었다. 이 계획은 프로토콜 대신 **값 타입 `PasteboardSnapshot`** 을 쓴다. 앱은 NSPasteboard 에서 스냅샷을 만들어 넘기고, 테스트는 스냅샷을 직접 만든다. 같은 목적(가짜 pasteboard 로 테스트)을 Sendable 하게 달성한다.
- FTS 테이블은 `fts5(plain_text, source_app_name, ...)` 두 칼럼이다. 파일 항목의 `plain_text` 가 곧 파일명 목록(스펙 4절)이므로 파일명 검색은 `plain_text` 로 된다. 별도 `file_names` 칼럼은 만들지 않는다 (스펙 4절 테이블에 없는 칼럼을 늘리지 않기 위해).
- 스펙 11절의 `(PanelState, KeyEvent) → PanelState` 는 부수 효과(붙여넣기, 고정 등)를 표현하려고 `(PanelState, PanelKey) -> (PanelState, PanelEffect?)` 로 넓혔다.
- 키 표에 없는 조합의 동작을 다음처럼 정했다 (테스트로 고정):
  - 검색창 포커스에서 Enter / ⇧Enter / ⌘Enter 는 Clipboard 칼럼의 현재 선택(검색 직후엔 맨 위)을 대상으로 한다.
  - 검색창 포커스에서 ⌘P, ⌥⌘↑/↓ 는 아무 일도 하지 않고, ⌘⌫ 는 검색창 편집(줄 앞까지 지우기)으로 흘려보낸다.
  - 검색창에서 ↓ 를 눌렀는데 Clipboard 가 비어 있으면 Pinned 로 간다 (검색 결과가 Pinned 에만 있을 때 키보드로 닿을 수 있게).
  - Esc 로 검색어를 지우면 포커스는 검색창으로 돌아간다.
  - ⌘P 로 고정하면 Pinned 맨 아래에 붙는다.

## File Structure

```
Package.swift                              # SwiftPM 매니페스트 (이 플랜: PasterCore + 테스트만)
Package.resolved                           # 의존성 고정 (커밋)
.gitignore
Sources/PasterCore/
  Support/Log.swift                        # os.Logger (subsystem com.wjbyun.Paster)
  Models/ClipKind.swift                    # text / image / files
  Models/MoveDirection.swift               # Pinned 순서 변경 방향
  Models/ByteSize.swift                    # "1.2 MB" 표시
  Models/ClipItem.swift                    # clip_items 행 (GRDB record) + 행 제목
  Models/RetentionSettings.swift           # RetentionPeriod, KindRetention, RetentionSettings
  Capture/ImageConverter.swift             # ImageIO 기반 PNG/TIFF 변환
  Capture/PasteboardSnapshot.swift         # PasteboardType 상수, PasteboardSnapshot, SourceApp
  Capture/ContentHasher.swift              # sha256 content_hash
  Capture/ClipCapture.swift                # 캡처 규칙: 건너뛰기 / 우선순위 / 100MB
  Storage/BlobStore.swift                  # blobs/<uuid>.png
  Storage/ClipStore.swift                  # DatabaseQueue + 마이그레이션(스키마, FTS5, 트리거)
  Storage/ClipStore+Save.swift             # 저장 · 중복 bump · touch
  Storage/SearchFilter.swift               # 검색어 → FTS5 MATCH / LIKE
  Storage/ClipStore+Query.swift            # Clipboard / Pinned 조회 (만료 제외)
  Storage/ClipStore+Pin.swift              # 고정 / 해제 / 순서 변경
  Storage/ClipStore+Delete.swift           # 삭제 / 전체 삭제 / 만료 삭제 / 고아 blob
  Storage/ClipStore+Open.swift             # 디스크 DB 열기 + 손상 복구
  Settings/PasterSettings.swift            # UserDefaults 설정
  Retention/RetentionSchedule.swift        # 다음 0시, 날짜 키, 깨어난 뒤 정리 여부
  Retention/RetentionService.swift         # 만료 정리 + 고아 blob 정리 (시계 주입)
  Panel/PanelState.swift                   # PanelColumn, PanelFocus, PasteMode, PanelState
  Panel/PanelKey.swift                     # PanelKey, PanelEffect
  Panel/PanelReducer.swift                 # 키 표 · 포커스 규칙 리듀서
  Panel/PanelKeyMapper.swift               # KeyModifiers, 가상 키 코드 → PanelKey
Tests/PasterCoreTests/
  SmokeTests.swift
  ClipItemTests.swift
  RetentionSettingsTests.swift
  Fixtures.swift                           # 이미지 생성, 임시 디렉터리, 고정 시각
  ImageConverterTests.swift
  ClipCaptureTests.swift
  BlobStoreTests.swift
  StoreFixtures.swift                      # 저장소 테스트용 클립 생성기
  ClipStoreSaveTests.swift
  ClipStoreQueryTests.swift
  ClipStoreSearchTests.swift
  ClipStorePinTests.swift
  ClipStoreDeleteTests.swift
  ClipStoreOpenTests.swift
  PasterSettingsTests.swift
  RetentionScheduleTests.swift
  RetentionServiceTests.swift              # TestClock 포함
  PanelNavigationTests.swift
  PanelActionTests.swift
  PanelKeyMapperTests.swift
```

각 Task 는 새 파일만 만든다 (기존 파일 수정 없음). 그래서 Task 순서대로만 진행하면 매 Task 끝에서 전체 테스트가 통과한다.

플랜 2·3 이 사용하는 공개 API 요약 (이름을 바꾸지 말 것):

| 타입 | 주요 멤버 |
|---|---|
| `ClipKind` | `.text` `.image` `.files` |
| `ClipItem` | `id`, `kind`, `plainText`, `rtf`, `html`, `imageBlob`, `imageWidth`, `imageHeight`, `byteSize`, `filePaths`, `sourceBundleID`, `sourceAppName`, `contentHash`, `createdAt`, `lastCopiedAt`, `pinnedAt`, `pinOrder`, `isPinned`, `title`, `missingFilePaths()` |
| `ByteSize` | `format(_:)` |
| `RetentionPeriod` / `KindRetention` / `RetentionSettings` | `.day .week .month .threeMonths`, `label`, `cutoff(from:calendar:)` / `isEnabled`, `period` / `text image files`, `subscript(kind)`, `enabledKinds`, `.default` |
| `PasteboardType` | `fileURL utf8PlainText rtf html png tiff concealed transient autoGenerated pasterInternal` |
| `PasteboardSnapshot` | `types fileURLs string rtf html png tiff` |
| `SourceApp` | `bundleID`, `name`, `.unknown` |
| `ClipCapture` | `init(excludedBundleIDs:enabledKinds:maxImageBytes:)`, `capture(_:source:) -> CaptureResult` |
| `CaptureResult` / `CapturedClip` / `CaptureSkipReason` | `.captured(CapturedClip)` / `.skipped(reason)` |
| `ImageConverter` | `png(from:) -> PNGImage?`, `convert(_:to:) -> Data?` |
| `BlobStore` | `directory`, `write(_:)`, `url(for:)`, `read(_:)`, `remove(_:)`, `allNames()` |
| `ClipStore` | `open(directory:now:)`, `inMemory(blobDirectory:)`, `blobs`, `dbQueue`, `item(id:)`, `save(_:now:) -> SaveOutcome`, `touch(id:now:)`, `fetchUnpinned(matching:settings:now:calendar:limit:)`, `fetchPinned(matching:)`, `pin(id:now:)`, `unpin(id:now:)`, `movePinned(id:direction:)`, `delete(id:)`, `deleteAllUnpinned()`, `deleteExpired(settings:now:calendar:)`, `sweepOrphanBlobs()` |
| `PasterSettings` | `init(defaults:)`, `retention`, `excludedBundleIDs`, `lastPurgeDay`, `makeCapture()` |
| `RetentionSchedule` | `nextMidnight(after:calendar:)`, `dayKey(for:calendar:)`, `shouldPurge(lastPurgeDay:now:calendar:)` |
| `RetentionService` | `init(store:calendar:now:)`, `purge(settings:)`, `purge(using:)`, `purgeIfDayChanged(using:)` |
| `PanelState` / `PanelFocus` / `PanelColumn` / `PasteMode` | `focus query clipboardCount pinnedCount clipboardIndex pinnedIndex activeColumn activeIndex count(of:) selectedIndex(in:) updateCounts(clipboard:pinned:) setQuery(_:)` |
| `PanelKey` / `PanelEffect` / `PanelReducer` | `reduce(_:_:)` |
| `KeyModifiers` / `PanelKeyMapper` | `.command .option .shift .control` / `key(keyCode:modifiers:characters:)` |
| `Log` | `subsystem`, `capture`, `store`, `retention`, `app` |

---

### Task 1: 패키지 골격

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/PasterCore/Support/Log.swift`
- Test: `Tests/PasterCoreTests/SmokeTests.swift`
- 생성됨(커밋): `Package.resolved`

- [ ] **Step 1: `Package.swift` 작성**

플랜 2 에서 `Paster` 실행 타깃과 KeyboardShortcuts 를, 플랜 3 에서 Sparkle 을 추가한다. 지금은 라이브러리와 테스트만 둔다.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paster",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PasterCore", targets: ["PasterCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "PasterCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "PasterCoreTests",
            dependencies: ["PasterCore"]
        ),
    ]
)
```

- [ ] **Step 2: `.gitignore` 작성**

```
.build/
.swiftpm/
build/
*.p12
*.pem
```

- [ ] **Step 3: 실패하는 스모크 테스트 작성**

`Tests/PasterCoreTests/SmokeTests.swift`:

```swift
import Testing
@testable import PasterCore

@Test func logSubsystemIsBundleID() {
    #expect(Log.subsystem == "com.wjbyun.Paster")
}
```

- [ ] **Step 4: 실패 확인**

Run: `swift test`
Expected: 의존성(GRDB 7.11.1)을 받은 뒤 빌드 실패. `PasterCore` 타깃에 소스가 없다는 오류 (`target 'PasterCore' referenced in product 'PasterCore' is empty` 류) 또는 `cannot find 'Log' in scope`.

- [ ] **Step 5: 로거 작성**

`Sources/PasterCore/Support/Log.swift`:

```swift
import os

/// os.Logger 모음. 클립보드 내용은 절대 로그에 남기지 않는다.
public enum Log {
    public static let subsystem = "com.wjbyun.Paster"

    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let retention = Logger(subsystem: subsystem, category: "retention")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
```

- [ ] **Step 6: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 1 test in 0 suites passed`

- [ ] **Step 7: 커밋**

```bash
git add Package.swift Package.resolved .gitignore Sources/PasterCore/Support/Log.swift Tests/PasterCoreTests/SmokeTests.swift
git commit -m "chore: add SwiftPM package skeleton with PasterCore" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ClipKind · ClipItem · ByteSize

스펙 4절 `clip_items` 칼럼과 8.5절 행 제목.

**Files:**
- Create: `Sources/PasterCore/Models/ClipKind.swift`
- Create: `Sources/PasterCore/Models/MoveDirection.swift`
- Create: `Sources/PasterCore/Models/ByteSize.swift`
- Create: `Sources/PasterCore/Models/ClipItem.swift`
- Test: `Tests/PasterCoreTests/ClipItemTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ClipItemTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct ClipItemTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ kind: ClipKind, text: String = "", size: Int = 0, width: Int? = nil, height: Int? = nil, paths: [String] = []) -> ClipItem {
        ClipItem(kind: kind, plainText: text, imageWidth: width, imageHeight: height, byteSize: size,
                 filePaths: paths, contentHash: "h", createdAt: date, lastCopiedAt: date)
    }

    @Test func textTitleIsFirstNonEmptyLine() {
        #expect(item(.text, text: "\n  첫 줄  \n둘째 줄").title == "첫 줄")
        #expect(item(.text, text: "한 줄").title == "한 줄")
    }

    @Test func imageTitleShowsSizeAndBytes() {
        #expect(item(.image, size: 1_234_567, width: 1292, height: 878).title == "Image: 1292x878 (1.2 MB)")
    }

    @Test func filesTitleShowsFirstNameAndCount() {
        #expect(item(.files, paths: ["/tmp/report.pdf"]).title == "파일: report.pdf")
        #expect(item(.files, paths: ["/tmp/report.pdf", "/tmp/a.txt", "/tmp/b.txt"]).title == "파일: report.pdf 외 2개")
    }

    @Test func missingFilePathsListsOnlyAbsentFiles() throws {
        let existing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }
        let clip = item(.files, paths: [existing.path, "/nonexistent/\(UUID().uuidString)"])
        #expect(clip.missingFilePaths().count == 1)
        #expect(clip.missingFilePaths().first?.hasPrefix("/nonexistent/") == true)
    }

    @Test(arguments: [
        (0, "0 B"), (999, "999 B"), (1000, "1.0 KB"), (1_234_567, "1.2 MB"), (5_000_000_000, "5.0 GB"),
    ])
    func byteSizeFormat(bytes: Int, expected: String) {
        #expect(ByteSize.format(bytes) == expected)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ClipItemTests`
Expected: 빌드 실패 `error: cannot find 'ClipItem' in scope` (그리고 `ClipKind`, `ByteSize`).

- [ ] **Step 3: 구현**

`Sources/PasterCore/Models/ClipKind.swift`:

```swift
/// 클립 종류. DB 의 `kind` 칼럼 값과 같다.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case files
}
```

`Sources/PasterCore/Models/MoveDirection.swift`:

```swift
/// Pinned 순서 변경 방향.
public enum MoveDirection: Equatable, Sendable {
    case up
    case down
}
```

`Sources/PasterCore/Models/ByteSize.swift`:

```swift
import Foundation

/// 크기 표시 문자열. Finder 와 같은 10진 단위 (1 KB = 1000 B).
public enum ByteSize {
    public static func format(_ bytes: Int) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        guard bytes >= 1000 else { return "\(bytes) B" }
        var value = Double(bytes)
        var unit = "B"
        for next in units {
            // 소수 첫째 자리로 반올림했을 때 1000 이 되면 다음 단위로 올린다
            guard (value * 10).rounded() / 10 >= 1000 else { break }
            value /= 1000
            unit = next
        }
        return String(format: "%.1f %@", value, unit)
    }
}
```

> 리뷰 반영: 반올림한 값이 1000 에 닿으면 다음 단위로 올린다 (`999_999` → `1.0 MB`, 커밋 14d9a86).

`Sources/PasterCore/Models/ClipItem.swift` — Codable 의 CodingKeys 가 DB 칼럼 이름(snake_case)이다. GRDB 는 `[String]` 같은 중첩 Codable 값을 JSON 텍스트로 저장한다 (`file_paths`).

```swift
import Foundation
import GRDB

/// `clip_items` 테이블의 한 행.
public struct ClipItem: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var kind: ClipKind
    /// 텍스트 본문. 파일이면 파일명 목록 (줄바꿈 구분).
    public var plainText: String
    public var rtf: Data?
    public var html: Data?
    /// `blobs/` 안의 파일 이름 (`<uuid>.png`).
    public var imageBlob: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var byteSize: Int
    public var filePaths: [String]
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var contentHash: String
    public var createdAt: Date
    public var lastCopiedAt: Date
    public var pinnedAt: Date?
    public var pinOrder: Int?

    public init(
        id: Int64? = nil,
        kind: ClipKind,
        plainText: String,
        rtf: Data? = nil,
        html: Data? = nil,
        imageBlob: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteSize: Int,
        filePaths: [String] = [],
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String,
        createdAt: Date,
        lastCopiedAt: Date,
        pinnedAt: Date? = nil,
        pinOrder: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.rtf = rtf
        self.html = html
        self.imageBlob = imageBlob
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.pinnedAt = pinnedAt
        self.pinOrder = pinOrder
    }

    public var isPinned: Bool { pinnedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case plainText = "plain_text"
        case rtf
        case html
        case imageBlob = "image_blob"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case byteSize = "byte_size"
        case filePaths = "file_paths"
        case sourceBundleID = "source_bundle_id"
        case sourceAppName = "source_app_name"
        case contentHash = "content_hash"
        case createdAt = "created_at"
        case lastCopiedAt = "last_copied_at"
        case pinnedAt = "pinned_at"
        case pinOrder = "pin_order"
    }
}

extension ClipItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clip_items"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension ClipItem {
    /// 패널 행 제목.
    public var title: String {
        switch kind {
        case .text:
            let firstLine = plainText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return firstLine ?? ""
        case .image:
            return "Image: \(imageWidth ?? 0)x\(imageHeight ?? 0) (\(ByteSize.format(byteSize)))"
        case .files:
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
            guard let first = names.first else { return "파일" }
            return names.count == 1 ? "파일: \(first)" : "파일: \(first) 외 \(names.count - 1)개"
        }
    }

    /// 원본이 사라진 파일 경로들.
    public func missingFilePaths(fileManager: FileManager = .default) -> [String] {
        filePaths.filter { !fileManager.fileExists(atPath: $0) }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 6 tests in 1 suite passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Models/ClipKind.swift Sources/PasterCore/Models/MoveDirection.swift Sources/PasterCore/Models/ByteSize.swift Sources/PasterCore/Models/ClipItem.swift Tests/PasterCoreTests/ClipItemTests.swift
git commit -m "feat(core): add ClipItem model, ClipKind and byte size formatting" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 보관 설정 모델

스펙 7.1절: 타입별 켬/끔 + 기간(24시간 / 7일 / 1개월 / 3개월), 기본값 모두 켬 · 3개월.

**Files:**
- Create: `Sources/PasterCore/Models/RetentionSettings.swift`
- Test: `Tests/PasterCoreTests/RetentionSettingsTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/RetentionSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct RetentionSettingsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    @Test func defaultIsAllEnabledThreeMonths() {
        let settings = RetentionSettings.default
        for kind in ClipKind.allCases {
            #expect(settings[kind] == KindRetention(isEnabled: true, period: .threeMonths))
        }
        #expect(settings.enabledKinds == Set(ClipKind.allCases))
    }

    @Test func subscriptSetsOnlyThatKind() {
        var settings = RetentionSettings.default
        settings[.image] = KindRetention(isEnabled: false, period: .day)
        #expect(settings.image == KindRetention(isEnabled: false, period: .day))
        #expect(settings.text == KindRetention())
        #expect(settings.enabledKinds == [.text, .files])
    }

    @Test func cutoffs() {
        let now = date("2026-05-31T12:00:00Z")
        #expect(RetentionPeriod.day.cutoff(from: now, calendar: calendar) == date("2026-05-30T12:00:00Z"))
        #expect(RetentionPeriod.week.cutoff(from: now, calendar: calendar) == date("2026-05-24T12:00:00Z"))
        // 5월 31일의 1개월 전은 4월 30일 (달력 기준)
        #expect(RetentionPeriod.month.cutoff(from: now, calendar: calendar) == date("2026-04-30T12:00:00Z"))
        #expect(RetentionPeriod.threeMonths.cutoff(from: now, calendar: calendar) == date("2026-02-28T12:00:00Z"))
    }

    @Test func codableRoundTrip() throws {
        var settings = RetentionSettings.default
        settings.files = KindRetention(isEnabled: false, period: .week)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(RetentionSettings.self, from: data) == settings)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter RetentionSettingsTests`
Expected: 빌드 실패 `error: cannot find 'RetentionSettings' in scope`

- [ ] **Step 3: 구현**

`Sources/PasterCore/Models/RetentionSettings.swift` — 1개월 · 3개월은 달력 기준(`Calendar.date(byAdding: .month, ...)`), 24시간 · 7일은 초 단위로 뺀다.

```swift
import Foundation

/// 보관 기간. 설정 화면 선택지와 같다.
public enum RetentionPeriod: String, Codable, CaseIterable, Sendable {
    case day = "24h"
    case week = "7d"
    case month = "1m"
    case threeMonths = "3m"

    public var label: String {
        switch self {
        case .day: "24시간"
        case .week: "7일"
        case .month: "1개월"
        case .threeMonths: "3개월"
        }
    }

    /// 이 시각보다 `last_copied_at` 이 이른 미고정 항목은 만료된 것이다.
    public func cutoff(from now: Date, calendar: Calendar) -> Date {
        switch self {
        case .day: now.addingTimeInterval(-24 * 60 * 60)
        case .week: now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)!
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)!
        }
    }
}

/// 타입 하나의 보관 설정.
public struct KindRetention: Codable, Equatable, Sendable {
    /// 꺼져 있으면 새로 캡처하지 않는다. 기존 항목은 기간 만료까지 유지한다.
    public var isEnabled: Bool
    public var period: RetentionPeriod

    public init(isEnabled: Bool = true, period: RetentionPeriod = .threeMonths) {
        self.isEnabled = isEnabled
        self.period = period
    }
}

/// 타입별 보관 설정. 기본값은 모두 켬 · 3개월.
public struct RetentionSettings: Codable, Equatable, Sendable {
    public var text: KindRetention
    public var image: KindRetention
    public var files: KindRetention

    public init(text: KindRetention = .init(), image: KindRetention = .init(), files: KindRetention = .init()) {
        self.text = text
        self.image = image
        self.files = files
    }

    public static let `default` = RetentionSettings()

    public subscript(kind: ClipKind) -> KindRetention {
        get {
            switch kind {
            case .text: text
            case .image: image
            case .files: files
            }
        }
        set {
            switch kind {
            case .text: text = newValue
            case .image: image = newValue
            case .files: files = newValue
            }
        }
    }

    public var enabledKinds: Set<ClipKind> {
        Set(ClipKind.allCases.filter { self[$0].isEnabled })
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 10 tests in 2 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Models/RetentionSettings.swift Tests/PasterCoreTests/RetentionSettingsTests.swift
git commit -m "feat(core): add per-kind retention settings" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 이미지 변환 (ImageIO)

스펙 5.3절: PNG 로 저장, 붙여넣을 때는 PNG + TIFF. AppKit(`NSImage`) 대신 ImageIO 를 써서 테스트가 window server 없이 돈다.

**Files:**
- Create: `Sources/PasterCore/Capture/ImageConverter.swift`
- Create: `Tests/PasterCoreTests/Fixtures.swift`
- Test: `Tests/PasterCoreTests/ImageConverterTests.swift`

- [ ] **Step 1: 테스트 도우미 작성**

`Tests/PasterCoreTests/Fixtures.swift` — 이후 모든 테스트가 쓰는 공용 도우미. `Fixtures.now` 는 밀리초 이하가 없는 고정 시각이라 GRDB 왕복(밀리초 정밀도) 후에도 `==` 비교가 된다.

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import PasterCore

/// 테스트 공용 도우미.
enum Fixtures {
    /// 단색 이미지를 지정 형식으로 인코딩한다.
    static func image(width: Int, height: Int, type: UTType) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 2027-01-15 08:00:00 UTC. 초 단위로 떨어지는 고정 시각.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ImageConverterTests.swift`:

```swift
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PasterCore

struct ImageConverterTests {
    @Test func tiffIsConvertedToPNG() throws {
        let tiff = Fixtures.image(width: 40, height: 30, type: .tiff)
        let png = try #require(ImageConverter.png(from: tiff))
        #expect(png.width == 40)
        #expect(png.height == 30)
        // PNG 시그니처 89 50 4E 47
        #expect(Array(png.data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func pngIsKeptAsIs() throws {
        let original = Fixtures.image(width: 10, height: 20, type: .png)
        let png = try #require(ImageConverter.png(from: original))
        #expect(png.data == original)
        #expect(png.width == 10)
        #expect(png.height == 20)
    }

    @Test func garbageReturnsNil() {
        #expect(ImageConverter.png(from: Data("not an image".utf8)) == nil)
    }

    @Test func pngConvertsToTIFF() throws {
        let png = Fixtures.image(width: 8, height: 8, type: .png)
        let tiff = try #require(ImageConverter.convert(png, to: .tiff))
        // TIFF 시그니처: "II*\0" 또는 "MM\0*"
        let head = Array(tiff.prefix(2))
        #expect(head == [0x49, 0x49] || head == [0x4D, 0x4D])
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter ImageConverterTests`
Expected: 빌드 실패 `error: cannot find 'ImageConverter' in scope`

- [ ] **Step 4: 구현**

`Sources/PasterCore/Capture/ImageConverter.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG 로 변환된 이미지와 픽셀 크기.
public struct PNGImage: Equatable, Sendable {
    public var data: Data
    public var width: Int
    public var height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

/// ImageIO 기반 변환. AppKit 없이 동작하므로 테스트에서 window server 가 필요 없다.
public enum ImageConverter {
    /// 임의 형식(PNG, TIFF 등) 이미지 데이터를 PNG 로 바꾼다. 이미 PNG 면 원본 데이터를 그대로 쓴다.
    public static func png(from data: Data) -> PNGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        if let type = CGImageSourceGetType(source), (type as String) == UTType.png.identifier {
            return PNGImage(data: data, width: image.width, height: image.height)
        }
        guard let encoded = encode(image, as: .png) else { return nil }
        return PNGImage(data: encoded, width: image.width, height: image.height)
    }

    /// 이미지 데이터를 지정한 형식으로 다시 인코딩한다. 붙여넣기 때 PNG → TIFF 용.
    public static func convert(_ data: Data, to type: UTType) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image, as: type)
    }

    static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 14 tests in 3 suites passed`

- [ ] **Step 6: 커밋**

```bash
git add Sources/PasterCore/Capture/ImageConverter.swift Tests/PasterCoreTests/Fixtures.swift Tests/PasterCoreTests/ImageConverterTests.swift
git commit -m "feat(core): add ImageIO-based PNG/TIFF conversion" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: PasteboardSnapshot · ClipCapture

스펙 5절 전체: 건너뛰기(concealed / transient / auto-generated / 제외 앱 / 자체 마커 `com.wjbyun.paster.internal` / 꺼진 타입), 우선순위(파일 > 텍스트 > 이미지), PNG 변환과 100MB 제한, sha256 `content_hash`.

**Files:**
- Create: `Sources/PasterCore/Capture/PasteboardSnapshot.swift`
- Create: `Sources/PasterCore/Capture/ContentHasher.swift`
- Create: `Sources/PasterCore/Capture/ClipCapture.swift`
- Test: `Tests/PasterCoreTests/ClipCaptureTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ClipCaptureTests.swift`:

```swift
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PasterCore

struct ClipCaptureTests {
    let finder = SourceApp(bundleID: "com.apple.finder", name: "Finder")
    let capture = ClipCapture()

    struct NotCaptured: Error {
        let result: CaptureResult
    }

    func captured(_ result: CaptureResult) throws -> CapturedClip {
        guard case let .captured(clip) = result else { throw NotCaptured(result: result) }
        return clip
    }

    // MARK: 우선순위

    @Test func filesWinOverTextAndImage() throws {
        let snapshot = PasteboardSnapshot(
            types: [PasteboardType.fileURL, PasteboardType.utf8PlainText, PasteboardType.tiff],
            fileURLs: [URL(fileURLWithPath: "/tmp/report.pdf"), URL(fileURLWithPath: "/tmp/a.txt")],
            string: "report.pdf",
            tiff: Fixtures.image(width: 4, height: 4, type: .tiff)
        )
        let clip = try captured(capture.capture(snapshot, source: finder))
        #expect(clip.kind == .files)
        #expect(clip.filePaths == ["/tmp/report.pdf", "/tmp/a.txt"])
        #expect(clip.plainText == "report.pdf\na.txt")
        #expect(clip.source == finder)
    }

    @Test func textWinsOverImage() throws {
        let snapshot = PasteboardSnapshot(
            types: [PasteboardType.utf8PlainText, PasteboardType.rtf, PasteboardType.png],
            string: "Word 본문",
            rtf: Data("{\\rtf1 Word}".utf8),
            png: Fixtures.image(width: 4, height: 4, type: .png)
        )
        let clip = try captured(capture.capture(snapshot, source: .unknown))
        #expect(clip.kind == .text)
        #expect(clip.plainText == "Word 본문")
        #expect(clip.rtf == Data("{\\rtf1 Word}".utf8))
        #expect(clip.pngData == nil)
        #expect(clip.byteSize == "Word 본문".utf8.count)
    }

    @Test func emptyStringFallsBackToImage() throws {
        let snapshot = PasteboardSnapshot(
            types: [PasteboardType.utf8PlainText, PasteboardType.tiff],
            string: "",
            tiff: Fixtures.image(width: 12, height: 7, type: .tiff)
        )
        let clip = try captured(capture.capture(snapshot, source: .unknown))
        #expect(clip.kind == .image)
        #expect(clip.imageWidth == 12)
        #expect(clip.imageHeight == 7)
        #expect(Array(clip.pngData!.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        #expect(clip.byteSize == clip.pngData!.count)
    }

    @Test func nothingUsableIsEmpty() {
        #expect(capture.capture(PasteboardSnapshot(types: ["com.example.custom"]), source: .unknown) == .skipped(.empty))
    }

    // MARK: 건너뛰기

    @Test(arguments: [
        (PasteboardType.pasterInternal, CaptureSkipReason.ownMarker),
        (PasteboardType.concealed, CaptureSkipReason.concealed),
        (PasteboardType.transient, CaptureSkipReason.transient),
        (PasteboardType.autoGenerated, CaptureSkipReason.autoGenerated),
    ])
    func markerTypesAreSkipped(marker: String, reason: CaptureSkipReason) {
        let snapshot = PasteboardSnapshot(types: [PasteboardType.utf8PlainText, marker], string: "secret")
        #expect(capture.capture(snapshot, source: .unknown) == .skipped(reason))
    }

    @Test func excludedAppIsSkipped() {
        let capture = ClipCapture(excludedBundleIDs: ["com.1password.1password"])
        let snapshot = PasteboardSnapshot(types: [PasteboardType.utf8PlainText], string: "x")
        let source = SourceApp(bundleID: "com.1password.1password", name: "1Password")
        #expect(capture.capture(snapshot, source: source) == .skipped(.excludedApp))
        #expect(capture.capture(snapshot, source: finder) != .skipped(.excludedApp))
    }

    @Test func disabledKindIsSkipped() {
        let capture = ClipCapture(enabledKinds: [.text, .files])
        let snapshot = PasteboardSnapshot(types: [PasteboardType.png], png: Fixtures.image(width: 2, height: 2, type: .png))
        #expect(capture.capture(snapshot, source: .unknown) == .skipped(.kindDisabled(.image)))
    }

    @Test func imageOverLimitIsSkipped() {
        let png = Fixtures.image(width: 64, height: 64, type: .png)
        let capture = ClipCapture(maxImageBytes: png.count - 1)
        let snapshot = PasteboardSnapshot(types: [PasteboardType.png], png: png)
        #expect(capture.capture(snapshot, source: .unknown) == .skipped(.imageTooLarge))
    }

    @Test func unreadableImageIsSkipped() {
        let snapshot = PasteboardSnapshot(types: [PasteboardType.tiff], tiff: Data("broken".utf8))
        #expect(capture.capture(snapshot, source: .unknown) == .skipped(.imageUnreadable))
    }

    // MARK: 해시

    @Test func hashIsStableSha256AndKindSpecific() throws {
        let text = try captured(capture.capture(PasteboardSnapshot(types: [PasteboardType.utf8PlainText], string: "a.txt"), source: .unknown))
        let again = try captured(capture.capture(PasteboardSnapshot(types: [PasteboardType.utf8PlainText], string: "a.txt"), source: finder))
        let file = try captured(capture.capture(PasteboardSnapshot(types: [PasteboardType.fileURL], fileURLs: [URL(fileURLWithPath: "a.txt")]), source: .unknown))
        #expect(text.contentHash.count == 64)
        #expect(text.contentHash == again.contentHash)
        #expect(text.contentHash != file.contentHash)
    }

    @Test func fileNamesAreNormalizedToNFC() throws {
        // "한" 을 자모로 분해한 NFD 문자열
        let nfdName = "\u{1112}\u{1161}\u{11AB}.txt"
        let snapshot = PasteboardSnapshot(types: [PasteboardType.fileURL], fileURLs: [URL(fileURLWithPath: "/tmp/\(nfdName)")])
        let clip = try captured(capture.capture(snapshot, source: .unknown))
        #expect(clip.plainText.unicodeScalars.count == "한.txt".unicodeScalars.count)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ClipCaptureTests`
Expected: 빌드 실패 `error: cannot find 'ClipCapture' in scope` (그리고 `PasteboardSnapshot`, `SourceApp`, `PasteboardType`)

- [ ] **Step 3: 스냅샷 타입 작성**

`Sources/PasterCore/Capture/PasteboardSnapshot.swift`:

```swift
import Foundation

/// Paster 가 다루는 pasteboard 타입 문자열.
public enum PasteboardType {
    public static let fileURL = "public.file-url"
    public static let utf8PlainText = "public.utf8-plain-text"
    public static let rtf = "public.rtf"
    public static let html = "public.html"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    /// nspasteboard.org 관례: 비밀번호 관리자 등이 붙이는 표시
    public static let concealed = "org.nspasteboard.ConcealedType"
    public static let transient = "org.nspasteboard.TransientType"
    public static let autoGenerated = "org.nspasteboard.AutoGeneratedType"
    /// Paster 가 직접 쓴 내용임을 나타내는 마커
    public static let pasterInternal = "com.wjbyun.paster.internal"
}

/// 한 시점의 pasteboard 내용. 앱은 NSPasteboard 에서 만들고, 테스트는 직접 만든다.
public struct PasteboardSnapshot: Equatable, Sendable {
    public var types: [String]
    public var fileURLs: [URL]
    public var string: String?
    public var rtf: Data?
    public var html: Data?
    public var png: Data?
    public var tiff: Data?

    public init(
        types: [String] = [],
        fileURLs: [URL] = [],
        string: String? = nil,
        rtf: Data? = nil,
        html: Data? = nil,
        png: Data? = nil,
        tiff: Data? = nil
    ) {
        self.types = types
        self.fileURLs = fileURLs
        self.string = string
        self.rtf = rtf
        self.html = html
        self.png = png
        self.tiff = tiff
    }
}

/// 복사 시점의 frontmost 앱.
public struct SourceApp: Equatable, Sendable {
    public var bundleID: String?
    public var name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }

    public static let unknown = SourceApp(bundleID: nil, name: nil)
}
```

- [ ] **Step 4: 해시 작성**

`Sources/PasterCore/Capture/ContentHasher.swift` — 종류 이름 + `0x00` + 내용(텍스트는 UTF-8, 이미지는 PNG 바이트, 파일은 줄바꿈으로 이은 경로)의 sha256 16진 문자열(64자).

```swift
import CryptoKit
import Foundation

/// `content_hash` 계산. 종류를 앞에 붙여 같은 바이트라도 종류가 다르면 다른 해시가 된다.
enum ContentHasher {
    static func hash(kind: ClipKind, payload: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: payload)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 5: 캡처 규칙 작성**

`Sources/PasterCore/Capture/ClipCapture.swift` — 로그에는 크기만 남기고 내용은 남기지 않는다 (스펙 10절).

```swift
import Foundation

/// 캡처하지 않은 이유.
public enum CaptureSkipReason: Equatable, Sendable {
    case ownMarker
    case concealed
    case transient
    case autoGenerated
    case excludedApp
    case kindDisabled(ClipKind)
    case empty
    case imageTooLarge
    case imageUnreadable
}

/// 저장 직전의 클립. ClipStore.save 에 넘긴다.
public struct CapturedClip: Equatable, Sendable {
    public var kind: ClipKind
    public var plainText: String
    public var rtf: Data?
    public var html: Data?
    public var pngData: Data?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var byteSize: Int
    public var filePaths: [String]
    public var source: SourceApp
    public var contentHash: String

    public init(
        kind: ClipKind,
        plainText: String,
        rtf: Data? = nil,
        html: Data? = nil,
        pngData: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteSize: Int,
        filePaths: [String] = [],
        source: SourceApp,
        contentHash: String
    ) {
        self.kind = kind
        self.plainText = plainText
        self.rtf = rtf
        self.html = html
        self.pngData = pngData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.filePaths = filePaths
        self.source = source
        self.contentHash = contentHash
    }
}

public enum CaptureResult: Equatable, Sendable {
    case captured(CapturedClip)
    case skipped(CaptureSkipReason)
}

/// PasteboardSnapshot → CapturedClip 변환 규칙 (스펙 5절).
public struct ClipCapture: Sendable {
    public static let defaultMaxImageBytes = 100 * 1024 * 1024

    public var excludedBundleIDs: Set<String>
    public var enabledKinds: Set<ClipKind>
    public var maxImageBytes: Int

    public init(
        excludedBundleIDs: Set<String> = [],
        enabledKinds: Set<ClipKind> = Set(ClipKind.allCases),
        maxImageBytes: Int = ClipCapture.defaultMaxImageBytes
    ) {
        self.excludedBundleIDs = excludedBundleIDs
        self.enabledKinds = enabledKinds
        self.maxImageBytes = maxImageBytes
    }

    public func capture(_ snapshot: PasteboardSnapshot, source: SourceApp) -> CaptureResult {
        let types = Set(snapshot.types)
        if types.contains(PasteboardType.pasterInternal) { return .skipped(.ownMarker) }
        if types.contains(PasteboardType.concealed) { return .skipped(.concealed) }
        if types.contains(PasteboardType.transient) { return .skipped(.transient) }
        if types.contains(PasteboardType.autoGenerated) { return .skipped(.autoGenerated) }
        if let bundleID = source.bundleID, excludedBundleIDs.contains(bundleID) {
            return .skipped(.excludedApp)
        }
        guard let kind = Self.detectKind(snapshot) else { return .skipped(.empty) }
        guard enabledKinds.contains(kind) else { return .skipped(.kindDisabled(kind)) }

        switch kind {
        case .files: return .captured(makeFiles(snapshot, source: source))
        case .text: return .captured(makeText(snapshot, source: source))
        case .image: return makeImage(snapshot, source: source)
        }
    }

    /// 우선순위: 파일 > 텍스트 > 이미지.
    static func detectKind(_ snapshot: PasteboardSnapshot) -> ClipKind? {
        if snapshot.fileURLs.contains(where: \.isFileURL) { return .files }
        if let string = snapshot.string, !string.isEmpty { return .text }
        if snapshot.png != nil || snapshot.tiff != nil { return .image }
        return nil
    }

    private func makeText(_ snapshot: PasteboardSnapshot, source: SourceApp) -> CapturedClip {
        let text = snapshot.string ?? ""
        return CapturedClip(
            kind: .text,
            plainText: text,
            rtf: snapshot.rtf,
            html: snapshot.html,
            byteSize: text.utf8.count,
            source: source,
            contentHash: ContentHasher.hash(kind: .text, payload: Data(text.utf8))
        )
    }

    private func makeFiles(_ snapshot: PasteboardSnapshot, source: SourceApp) -> CapturedClip {
        let paths = snapshot.fileURLs.filter(\.isFileURL).map(\.path)
        // Finder 파일명은 NFD 일 수 있어 검색용 텍스트는 NFC 로 맞춘다
        let names = paths
            .map { URL(fileURLWithPath: $0).lastPathComponent.precomposedStringWithCanonicalMapping }
            .joined(separator: "\n")
        let size = paths.reduce(0) { total, path in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return total + ((attributes?[.size] as? NSNumber)?.intValue ?? 0)
        }
        return CapturedClip(
            kind: .files,
            plainText: names,
            byteSize: size,
            filePaths: paths,
            source: source,
            contentHash: ContentHasher.hash(kind: .files, payload: Data(paths.joined(separator: "\n").utf8))
        )
    }

    private func makeImage(_ snapshot: PasteboardSnapshot, source: SourceApp) -> CaptureResult {
        guard let raw = snapshot.png ?? snapshot.tiff, let png = ImageConverter.png(from: raw) else {
            Log.capture.error("이미지를 읽을 수 없어 건너뜀")
            return .skipped(.imageUnreadable)
        }
        guard png.data.count <= maxImageBytes else {
            Log.capture.error("PNG 크기 \(png.data.count, privacy: .public) 바이트가 제한을 넘어 건너뜀")
            return .skipped(.imageTooLarge)
        }
        return .captured(CapturedClip(
            kind: .image,
            plainText: "",
            pngData: png.data,
            imageWidth: png.width,
            imageHeight: png.height,
            byteSize: png.data.count,
            source: source,
            contentHash: ContentHasher.hash(kind: .image, payload: png.data)
        ))
    }
}
```

- [ ] **Step 6: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 25 tests in 4 suites passed`

- [ ] **Step 7: 커밋**

```bash
git add Sources/PasterCore/Capture/PasteboardSnapshot.swift Sources/PasterCore/Capture/ContentHasher.swift Sources/PasterCore/Capture/ClipCapture.swift Tests/PasterCoreTests/ClipCaptureTests.swift
git commit -m "feat(core): add clip capture rules over pasteboard snapshots" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: BlobStore

스펙 4절 `blobs/<uuid>.png`.

**Files:**
- Create: `Sources/PasterCore/Storage/BlobStore.swift`
- Test: `Tests/PasterCoreTests/BlobStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/BlobStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct BlobStoreTests {
    @Test func writeReadRemove() throws {
        let directory = try Fixtures.temporaryDirectory().appendingPathComponent("blobs")
        let store = try BlobStore(directory: directory)
        let name = try store.write(Data([1, 2, 3]))
        #expect(name.hasSuffix(".png"))
        #expect(UUID(uuidString: String(name.dropLast(4))) != nil)
        #expect(store.read(name) == Data([1, 2, 3]))
        #expect(store.allNames() == [name])

        store.remove(name)
        #expect(store.read(name) == nil)
        #expect(store.allNames().isEmpty)
    }

    @Test func allNamesIgnoresOtherFiles() throws {
        let store = try BlobStore(directory: Fixtures.temporaryDirectory())
        try Data().write(to: store.directory.appendingPathComponent(".DS_Store"))
        let name = try store.write(Data([0]))
        #expect(store.allNames() == [name])
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter BlobStoreTests`
Expected: 빌드 실패 `error: cannot find 'BlobStore' in scope`

- [ ] **Step 3: 구현**

`Sources/PasterCore/Storage/BlobStore.swift`:

```swift
import Foundation

/// `blobs/<uuid>.png` 파일 관리.
public struct BlobStore: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 새 blob 을 쓰고 파일 이름을 돌려준다.
    public func write(_ data: Data) throws -> String {
        let name = UUID().uuidString.lowercased() + ".png"
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    /// 디렉터리 밖으로 나가지 않는 평범한 `.png` 파일 이름만 허용한다.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && name.hasSuffix(".png")
    }

    /// 잘못된 이름은 디렉터리 안의 존재하지 않는 자리 표시 경로로 바꾼다.
    public func url(for name: String) -> URL {
        directory.appendingPathComponent(Self.isPlainName(name) ? name : ".invalid", isDirectory: false)
    }

    public func read(_ name: String) -> Data? {
        guard Self.isPlainName(name) else { return nil }
        return try? Data(contentsOf: url(for: name))
    }

    public func remove(_ name: String) {
        guard Self.isPlainName(name) else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// 디렉터리 안의 모든 `.png` 파일 이름.
    public func allNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".png") })
    }
}
```

> 리뷰 반영: BlobStore 이름 검증(isPlainName), 커밋 3c5d944

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 27 tests in 5 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Storage/BlobStore.swift Tests/PasterCoreTests/BlobStoreTests.swift
git commit -m "feat(core): add blob store for image files" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: ClipStore 스키마 · 저장 · 중복 처리

스펙 4절 테이블, 5.4절 중복(같은 `content_hash` 는 `last_copied_at` 과 출처만 갱신), 6절 FTS5 trigram 가상 테이블과 동기화 트리거. 스펙 9.1절의 "PasteService 가 `last_copied_at` 을 갱신" 은 `touch(id:now:)` 로 제공한다.

마이그레이션 SQL 요점:
- `content_hash TEXT NOT NULL UNIQUE`
- `clip_fts` 는 external content 테이블(`content='clip_items', content_rowid='id'`)이라 본문을 중복 저장하지 않는다. INSERT / DELETE / `UPDATE OF plain_text, source_app_name` 트리거로 색인을 맞춘다. `last_copied_at` 만 바뀌는 bump 는 색인을 건드리지 않는다.

**Files:**
- Create: `Sources/PasterCore/Storage/ClipStore.swift`
- Create: `Sources/PasterCore/Storage/ClipStore+Save.swift`
- Create: `Tests/PasterCoreTests/StoreFixtures.swift`
- Test: `Tests/PasterCoreTests/ClipStoreSaveTests.swift`

- [ ] **Step 1: 저장소 테스트 도우미 작성**

`Tests/PasterCoreTests/StoreFixtures.swift` — `ContentHasher` 는 internal 이므로 `@testable import` 로 쓴다. 파일명은 Task 5 의 캡처와 똑같이 NFC 로 맞춘다.

```swift
import Foundation
@testable import PasterCore

extension Fixtures {
    static let finder = SourceApp(bundleID: "com.apple.finder", name: "Finder")
    static let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")

    static func makeStore() throws -> ClipStore {
        try ClipStore.inMemory(blobDirectory: temporaryDirectory())
    }

    static func textClip(_ text: String, source: SourceApp = finder) -> CapturedClip {
        CapturedClip(kind: .text, plainText: text, byteSize: text.utf8.count, source: source,
                     contentHash: ContentHasher.hash(kind: .text, payload: Data(text.utf8)))
    }

    static func imageClip(seed: Int, source: SourceApp = finder) -> CapturedClip {
        let png = image(width: seed + 1, height: 1, type: .png)
        return CapturedClip(kind: .image, plainText: "", pngData: png, imageWidth: seed + 1, imageHeight: 1,
                            byteSize: png.count, source: source,
                            contentHash: ContentHasher.hash(kind: .image, payload: png))
    }

    static func filesClip(_ paths: [String], source: SourceApp = finder) -> CapturedClip {
        let names = paths
            .map { URL(fileURLWithPath: $0).lastPathComponent.precomposedStringWithCanonicalMapping }
            .joined(separator: "\n")
        return CapturedClip(kind: .files, plainText: names, byteSize: 0, filePaths: paths, source: source,
                            contentHash: ContentHasher.hash(kind: .files, payload: Data(paths.joined(separator: "\n").utf8)))
    }

    /// 저장 후 id 를 돌려준다.
    @discardableResult
    static func save(_ clip: CapturedClip, in store: ClipStore, at date: Date = now) throws -> Int64 {
        try store.save(clip, now: date).item.id!
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ClipStoreSaveTests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import PasterCore

struct ClipStoreSaveTests {
    let store: ClipStore

    init() throws {
        store = try Fixtures.makeStore()
    }

    @Test func insertAssignsIDAndTimestamps() throws {
        let outcome = try store.save(Fixtures.textClip("hello"), now: Fixtures.now)
        guard case let .inserted(item) = outcome else { Issue.record("inserted 가 아님"); return }
        let id = try #require(item.id)
        let loaded = try #require(try store.item(id: id))
        #expect(loaded == item)
        #expect(loaded.createdAt == Fixtures.now)
        #expect(loaded.lastCopiedAt == Fixtures.now)
        #expect(loaded.pinnedAt == nil)
        #expect(loaded.sourceAppName == "Finder")
    }

    @Test func sameHashBumpsInsteadOfInserting() throws {
        let first = try store.save(Fixtures.textClip("hello"), now: Fixtures.now).item
        let later = Fixtures.now.addingTimeInterval(60)
        let outcome = try store.save(Fixtures.textClip("hello", source: Fixtures.safari), now: later)
        guard case let .bumped(bumped) = outcome else { Issue.record("bumped 가 아님"); return }
        #expect(bumped.id == first.id)
        #expect(bumped.createdAt == Fixtures.now)
        #expect(bumped.lastCopiedAt == later)
        #expect(bumped.sourceBundleID == "com.apple.Safari")
        #expect(bumped.sourceAppName == "Safari")
        let count = try store.dbQueue.read { try ClipItem.fetchCount($0) }
        #expect(count == 1)
    }

    @Test func filePathsRoundTripAsJSON() throws {
        let id = try Fixtures.save(Fixtures.filesClip(["/tmp/a b.txt", "/tmp/한글.pdf"]), in: store)
        #expect(try store.item(id: id)?.filePaths == ["/tmp/a b.txt", "/tmp/한글.pdf"])
        let raw = try store.dbQueue.read { try String.fetchOne($0, sql: "SELECT file_paths FROM clip_items") }
        #expect(raw?.hasPrefix("[") == true)
    }

    @Test func imageIsWrittenAsBlob() throws {
        let clip = Fixtures.imageClip(seed: 2)
        let item = try store.save(clip, now: Fixtures.now).item
        let blobName = try #require(item.imageBlob)
        #expect(store.blobs.read(blobName) == clip.pngData)
    }

    @Test func bumpingAnImageDoesNotWriteANewBlob() throws {
        let clip = Fixtures.imageClip(seed: 2)
        try store.save(clip, now: Fixtures.now)
        try store.save(clip, now: Fixtures.now.addingTimeInterval(1))
        #expect(store.blobs.allNames().count == 1)
    }

    @Test func touchMovesLastCopiedAt() throws {
        let id = try Fixtures.save(Fixtures.textClip("x"), in: store)
        let later = Fixtures.now.addingTimeInterval(3600)
        try store.touch(id: id, now: later)
        #expect(try store.item(id: id)?.lastCopiedAt == later)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter ClipStoreSaveTests`
Expected: 빌드 실패 `error: cannot find type 'ClipStore' in scope`

- [ ] **Step 4: 저장소 · 마이그레이션 작성**

`Sources/PasterCore/Storage/ClipStore.swift`:

```swift
import Foundation
import GRDB

/// SQLite(GRDB) 기반 클립 저장소. blob 파일도 함께 관리한다.
public final class ClipStore: Sendable {
    public static let databaseFileName = "paster.sqlite"
    public static let blobDirectoryName = "blobs"

    public let dbQueue: DatabaseQueue
    public let blobs: BlobStore

    public init(dbQueue: DatabaseQueue, blobs: BlobStore) throws {
        self.dbQueue = dbQueue
        self.blobs = blobs
        try Self.migrator.migrate(dbQueue)
    }

    /// 테스트용 메모리 DB.
    public static func inMemory(blobDirectory: URL) throws -> ClipStore {
        try ClipStore(dbQueue: DatabaseQueue(), blobs: BlobStore(directory: blobDirectory))
    }

    public func item(id: Int64) throws -> ClipItem? {
        try dbQueue.read { try ClipItem.fetchOne($0, key: id) }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE clip_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kind TEXT NOT NULL,
                    plain_text TEXT NOT NULL DEFAULT '',
                    rtf BLOB,
                    html BLOB,
                    image_blob TEXT,
                    image_width INTEGER,
                    image_height INTEGER,
                    byte_size INTEGER NOT NULL DEFAULT 0,
                    file_paths TEXT NOT NULL DEFAULT '[]',
                    source_bundle_id TEXT,
                    source_app_name TEXT,
                    content_hash TEXT NOT NULL UNIQUE,
                    created_at DATETIME NOT NULL,
                    last_copied_at DATETIME NOT NULL,
                    pinned_at DATETIME,
                    pin_order INTEGER
                );
                CREATE INDEX clip_items_last_copied_at ON clip_items(last_copied_at);
                CREATE INDEX clip_items_pin_order ON clip_items(pin_order) WHERE pinned_at IS NOT NULL;

                CREATE VIRTUAL TABLE clip_fts USING fts5(
                    plain_text, source_app_name,
                    content='clip_items', content_rowid='id', tokenize='trigram'
                );
                CREATE TRIGGER clip_items_ai AFTER INSERT ON clip_items BEGIN
                    INSERT INTO clip_fts(rowid, plain_text, source_app_name)
                    VALUES (new.id, new.plain_text, new.source_app_name);
                END;
                CREATE TRIGGER clip_items_ad AFTER DELETE ON clip_items BEGIN
                    INSERT INTO clip_fts(clip_fts, rowid, plain_text, source_app_name)
                    VALUES ('delete', old.id, old.plain_text, old.source_app_name);
                END;
                CREATE TRIGGER clip_items_au AFTER UPDATE OF plain_text, source_app_name ON clip_items BEGIN
                    INSERT INTO clip_fts(clip_fts, rowid, plain_text, source_app_name)
                    VALUES ('delete', old.id, old.plain_text, old.source_app_name);
                    INSERT INTO clip_fts(rowid, plain_text, source_app_name)
                    VALUES (new.id, new.plain_text, new.source_app_name);
                END;
                """)
        }
        return migrator
    }
}
```

- [ ] **Step 5: 저장 · bump · touch 작성**

`Sources/PasterCore/Storage/ClipStore+Save.swift` — blob 쓰기는 write 트랜잭션 안에서 한다. 그래야 Task 10 의 고아 blob 정리(같은 write 큐에서 실행)가 저장 중인 blob 을 지우지 않는다. insert 가 실패하면 방금 쓴 blob 을 지운다.

```swift
import Foundation
import GRDB

public enum SaveOutcome: Equatable, Sendable {
    /// 새 행을 만들었다.
    case inserted(ClipItem)
    /// 같은 content_hash 가 있어 last_copied_at 과 출처만 갱신했다.
    case bumped(ClipItem)

    public var item: ClipItem {
        switch self {
        case let .inserted(item), let .bumped(item): item
        }
    }
}

extension ClipStore {
    /// 캡처한 클립을 저장한다. 같은 해시가 있으면 새 행 대신 맨 위로 올린다.
    @discardableResult
    public func save(_ clip: CapturedClip, now: Date) throws -> SaveOutcome {
        try dbQueue.write { db in
            if var existing = try ClipItem.filter(Column("content_hash") == clip.contentHash).fetchOne(db) {
                existing.lastCopiedAt = now
                existing.sourceBundleID = clip.source.bundleID
                existing.sourceAppName = clip.source.name
                try existing.update(db)
                return .bumped(existing)
            }

            let blobName = try clip.pngData.map { try blobs.write($0) }
            var item = ClipItem(
                kind: clip.kind,
                plainText: clip.plainText,
                rtf: clip.rtf,
                html: clip.html,
                imageBlob: blobName,
                imageWidth: clip.imageWidth,
                imageHeight: clip.imageHeight,
                byteSize: clip.byteSize,
                filePaths: clip.filePaths,
                sourceBundleID: clip.source.bundleID,
                sourceAppName: clip.source.name,
                contentHash: clip.contentHash,
                createdAt: now,
                lastCopiedAt: now
            )
            do {
                try item.insert(db)
            } catch {
                if let blobName { blobs.remove(blobName) }
                throw error
            }
            return .inserted(item)
        }
    }

    /// 붙여넣기 / 복사한 항목을 맨 위로 올린다.
    public func touch(id: Int64, now: Date) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET last_copied_at = ? WHERE id = ?", arguments: [now, id])
        }
    }
}
```

- [ ] **Step 6: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 33 tests in 6 suites passed`

- [ ] **Step 7: 커밋**

```bash
git add Sources/PasterCore/Storage/ClipStore.swift Sources/PasterCore/Storage/ClipStore+Save.swift Tests/PasterCoreTests/StoreFixtures.swift Tests/PasterCoreTests/ClipStoreSaveTests.swift
git commit -m "feat(core): add ClipStore schema, FTS5 index and dedup save" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 조회 · 검색 (만료 제외, trigram + LIKE 폴백)

스펙 6절(검색: trigram, 1~2글자 LIKE, 대상 `plain_text` · 파일명 · 출처 앱 이름, 두 칼럼 모두에 적용), 7.1절(조회 시에도 만료 항목 제외, Pin 은 만료 없음), 8.3절(Clipboard 는 미고정만, Pinned 는 `pin_order` 순).

검색 규칙:
- 검색어를 공백(개행 포함)으로 나눈 단어마다 조건을 만들고 모두 만족해야 한다(AND). 빈 검색어는 조건이 없다.
- 저장된 텍스트는 NFC 일 수도 NFD 일 수도 있으므로(파일명만 저장 시 NFC 로 맞춘다), 단어마다 NFC 와 NFD 두 변형을 OR 로 찾는다. 두 변형이 스칼라 단위로 같으면(ASCII 등) 하나만 쓴다. Swift `String ==` 는 정규 동등이라 스칼라로 비교한다.
- 단어의 NFC 유니코드 스칼라가 3개 이상: `id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)`, 패턴은 큰따옴표로 감싼 구(phrase)이고 안의 `"` 는 `""` 로 이스케이프한다. FTS 연산자(`OR`, `NEAR` 등)가 해석되지 않는다.
- 1~2개: `plain_text LIKE ? ESCAPE '\'` 또는 `source_app_name LIKE ?`. `%`, `_`, `\` 는 이스케이프한다. trigram 인지 LIKE 인지는 단어마다 따로 정한다.
- trigram 과 LIKE 모두 ASCII 대소문자를 구분하지 않는다.
- 리뷰 반영: NFD 텍스트 검색, 다중 단어 AND (커밋 8776cb4)

만료 제외 조건: 종류마다 `kind = ? AND last_copied_at >= cutoff` 를 OR 로 묶는다. 꺼진 타입도 기간이 지날 때까지는 보인다 (스펙 7.1절).

**Files:**
- Create: `Sources/PasterCore/Storage/SearchFilter.swift`
- Create: `Sources/PasterCore/Storage/ClipStore+Query.swift`
- Test: `Tests/PasterCoreTests/ClipStoreQueryTests.swift`
- Test: `Tests/PasterCoreTests/ClipStoreSearchTests.swift`

- [ ] **Step 1: 실패하는 조회 테스트 작성**

`Tests/PasterCoreTests/ClipStoreQueryTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct ClipStoreQueryTests {
    let store: ClipStore
    let hour: TimeInterval = 3600

    init() throws {
        store = try Fixtures.makeStore()
    }

    @Test func unpinnedAreNewestFirst() throws {
        try Fixtures.save(Fixtures.textClip("old"), in: store, at: Fixtures.now)
        try Fixtures.save(Fixtures.textClip("new"), in: store, at: Fixtures.now.addingTimeInterval(hour))
        try Fixtures.save(Fixtures.textClip("old"), in: store, at: Fixtures.now.addingTimeInterval(2 * hour))
        let texts = try store.fetchUnpinned(settings: .default, now: Fixtures.now.addingTimeInterval(3 * hour)).map(\.plainText)
        #expect(texts == ["old", "new"])
    }

    @Test func expiredItemsAreHiddenBeforePurge() throws {
        var settings = RetentionSettings.default
        settings.text.period = .day
        try Fixtures.save(Fixtures.textClip("stale"), in: store, at: Fixtures.now.addingTimeInterval(-25 * hour))
        try Fixtures.save(Fixtures.textClip("fresh"), in: store, at: Fixtures.now.addingTimeInterval(-23 * hour))
        try Fixtures.save(Fixtures.imageClip(seed: 1), in: store, at: Fixtures.now.addingTimeInterval(-25 * hour))
        let items = try store.fetchUnpinned(settings: settings, now: Fixtures.now)
        #expect(items.map(\.kind) == [.text, .image])
        #expect(items.first?.plainText == "fresh")
    }

    @Test func disabledKindKeepsShowingUntilItsPeriodEnds() throws {
        var settings = RetentionSettings.default
        settings.text = KindRetention(isEnabled: false, period: .week)
        try Fixtures.save(Fixtures.textClip("kept"), in: store, at: Fixtures.now.addingTimeInterval(-6 * 24 * hour))
        #expect(try store.fetchUnpinned(settings: settings, now: Fixtures.now).count == 1)
    }

    @Test func pinnedAreExcludedFromUnpinnedAndOrderedByPinOrder() throws {
        let a = try Fixtures.save(Fixtures.textClip("a"), in: store)
        let b = try Fixtures.save(Fixtures.textClip("b"), in: store)
        try Fixtures.save(Fixtures.textClip("c"), in: store)
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 1 WHERE id = ?", arguments: [Fixtures.now, a])
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 0 WHERE id = ?", arguments: [Fixtures.now, b])
        }
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).map(\.plainText) == ["c"])
        #expect(try store.fetchPinned().map(\.plainText) == ["b", "a"])
    }

    @Test func pinnedNeverExpireInQueries() throws {
        let id = try Fixtures.save(Fixtures.textClip("ancient"), in: store, at: Fixtures.now.addingTimeInterval(-365 * 24 * hour))
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 0 WHERE id = ?", arguments: [Fixtures.now, id])
        }
        try Fixtures.save(Fixtures.textClip("stale unpinned"), in: store, at: Fixtures.now.addingTimeInterval(-365 * 24 * hour))
        #expect(try store.fetchPinned().count == 1)
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).isEmpty)
    }

    @Test func limitCapsResults() throws {
        for index in 0..<5 {
            try Fixtures.save(Fixtures.textClip("item \(index)"), in: store, at: Fixtures.now.addingTimeInterval(Double(index)))
        }
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now.addingTimeInterval(10), limit: 3).count == 3)
    }
}
```

- [ ] **Step 2: 실패하는 검색 테스트 작성**

`Tests/PasterCoreTests/ClipStoreSearchTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct ClipStoreSearchTests {
    let store: ClipStore
    let later = Fixtures.now.addingTimeInterval(60)

    init() throws {
        store = try Fixtures.makeStore()
        try Fixtures.save(Fixtures.textClip("배포 체크리스트 정리"), in: store)
        try Fixtures.save(Fixtures.textClip("https://example.com/Deploy?id=1"), in: store)
        try Fixtures.save(Fixtures.textClip("100% 완료_v2"), in: store)
        try Fixtures.save(Fixtures.filesClip(["/Users/me/Documents/분기 보고서.pdf"]), in: store)
        try Fixtures.save(Fixtures.textClip("plain", source: SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")), in: store)
    }

    func search(_ query: String) throws -> [String] {
        try store.fetchUnpinned(matching: query, settings: .default, now: later).map(\.plainText).sorted()
    }

    @Test func emptyQueryReturnsEverything() throws {
        #expect(try search("").count == 5)
        #expect(try search("   ").count == 5)
    }

    @Test func koreanSubstringViaTrigram() throws {
        #expect(try search("체크리") == ["배포 체크리스트 정리"])
        #expect(try search("크리스트") == ["배포 체크리스트 정리"])
    }

    @Test func trigramIsCaseInsensitive() throws {
        #expect(try search("deploy") == ["https://example.com/Deploy?id=1"])
    }

    @Test func fileNamesAreSearchable() throws {
        #expect(try search("보고서") == ["분기 보고서.pdf"])
    }

    @Test func sourceAppNameIsSearchable() throws {
        #expect(try search("TextEdit") == ["plain"])
    }

    @Test func oneOrTwoCharactersUseLike() throws {
        #expect(try search("배") == ["배포 체크리스트 정리"])
        #expect(try search("보고") == ["분기 보고서.pdf"])
        #expect(try search("Te") == ["plain"])
    }

    @Test func likeWildcardsAreEscaped() throws {
        #expect(try search("%") == ["100% 완료_v2"])
        #expect(try search("_v") == ["100% 완료_v2"])
    }

    @Test func quotesDoNotBreakFTS() throws {
        #expect(try search("\"배포\" OR") == [])
    }

    @Test func pinnedColumnIsFilteredToo() throws {
        let id = try #require(try store.fetchUnpinned(matching: "체크리", settings: .default, now: later).first?.id)
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 0 WHERE id = ?", arguments: [Fixtures.now, id])
        }
        #expect(try store.fetchPinned(matching: "체크리").count == 1)
        #expect(try store.fetchPinned(matching: "보고서").isEmpty)
    }

    @Test func nfdTextClipIsFoundByNFCTrigramQuery() throws {
        try Fixtures.save(Fixtures.textClip("/Users/me/분기 보고서.pdf".decomposedStringWithCanonicalMapping), in: store)
        #expect(try search("보고서".precomposedStringWithCanonicalMapping).count == 2)
    }

    @Test func nfdTextClipIsFoundByNFCLikeQuery() throws {
        try Fixtures.save(Fixtures.textClip("/Users/me/분기 보고서.pdf".decomposedStringWithCanonicalMapping), in: store)
        #expect(try search("보고".precomposedStringWithCanonicalMapping).count == 2)
    }

    @Test func nfcClipIsFoundByNFDQuery() throws {
        #expect(try search("체크리".decomposedStringWithCanonicalMapping) == ["배포 체크리스트 정리"])
        #expect(try search("배".decomposedStringWithCanonicalMapping) == ["배포 체크리스트 정리"])
    }

    @Test func storedNFDTextIsNotAltered() throws {
        let nfd = "분기 보고서".decomposedStringWithCanonicalMapping
        try Fixtures.save(Fixtures.textClip(nfd), in: store)
        let found = try store.fetchUnpinned(matching: "보고서", settings: .default, now: later).map(\.plainText)
        #expect(found.contains { $0.unicodeScalars.elementsEqual(nfd.unicodeScalars) })
    }

    @Test func allTermsMustMatch() throws {
        #expect(try search("배포 정리") == ["배포 체크리스트 정리"])
        #expect(try search("정리   배포") == ["배포 체크리스트 정리"])
        #expect(try search("배포 없는말") == [])
    }

    @Test func shortTermsCombineWithAnd() throws {
        #expect(try search("정 배포") == ["배포 체크리스트 정리"])
    }

    @Test func termsMixTrigramAndLike() throws {
        #expect(try search("체크리 정") == ["배포 체크리스트 정리"])
        #expect(try search("체크리 없") == [])
    }

    @Test func operatorsInsideQuotedTermsAreLiteral() throws {
        try Fixtures.save(Fixtures.textClip("a*b c-d"), in: store)
        #expect(try search("a*b") == ["a*b c-d"])
        #expect(try search("NEAR OR") == [])
    }

    @Test func filterParsing() {
        #expect(SearchFilter(query: "  ").terms.isEmpty)
        #expect(SearchFilter(query: "ab").terms == [.like(patterns: ["%ab%"])])
        #expect(SearchFilter(query: "abc").terms == [.fullText(patterns: ["\"abc\""])])
        #expect(SearchFilter(query: "a\"b").terms == [.fullText(patterns: ["\"a\"\"b\""])])
        #expect(SearchFilter(query: "ab  abc").terms == [.like(patterns: ["%ab%"]), .fullText(patterns: ["\"abc\""])])
    }

    @Test func filterParsingKeepsNFCAndNFDVariants() {
        let nfc = "보고서".precomposedStringWithCanonicalMapping
        let nfd = "보고서".decomposedStringWithCanonicalMapping
        guard case let .fullText(patterns) = SearchFilter(query: nfd).terms.first else {
            Issue.record("fullText 단어가 아님")
            return
        }
        // String == 는 정규 동등이라 스칼라로 비교한다
        #expect(patterns.count == 2)
        #expect(patterns[0].unicodeScalars.elementsEqual("\"\(nfc)\"".unicodeScalars))
        #expect(patterns[1].unicodeScalars.elementsEqual("\"\(nfd)\"".unicodeScalars))
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter ClipStoreQueryTests`
Expected: 빌드 실패 `error: value of type 'ClipStore' has no member 'fetchUnpinned'` (그리고 `cannot find 'SearchFilter' in scope`)

- [ ] **Step 4: 검색 조건 작성**

`Sources/PasterCore/Storage/SearchFilter.swift`:

```swift
import Foundation
import GRDB

/// 검색어 → SQL 조건. 공백으로 나눈 단어를 모두 만족해야 한다(AND).
/// 단어마다 3글자 이상은 FTS5 trigram, 1~2글자는 LIKE.
struct SearchFilter: Equatable {
    enum Term: Equatable {
        /// MATCH 패턴. NFC / NFD 변형 중 하나라도 맞으면 통과한다.
        case fullText(patterns: [String])
        /// LIKE 패턴. NFC / NFD 변형 중 하나라도 맞으면 통과한다.
        case like(patterns: [String])
    }

    /// 아주 긴 검색어가 SQLite 바인딩 변수 한도를 넘지 않도록 단어 수를 제한한다.
    static let maxTerms = 32

    let terms: [Term]

    init(query: String) {
        terms = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(Self.maxTerms)
            .map(Self.term(for:))
    }

    private static func term(for raw: String) -> Term {
        let nfc = raw.precomposedStringWithCanonicalMapping
        // 저장된 텍스트는 NFC 일 수도 NFD 일 수도 있어서 두 형태를 모두 찾는다
        var variants = [nfc]
        let nfd = raw.decomposedStringWithCanonicalMapping
        // Swift String 의 == 는 정규 동등이라 NFC/NFD 를 같다고 보므로 스칼라로 비교한다
        if !nfd.unicodeScalars.elementsEqual(nfc.unicodeScalars) { variants.append(nfd) }

        if nfc.unicodeScalars.count >= 3 {
            // 큰따옴표로 감싸 FTS 문법을 무력화하고 부분 문자열로 찾는다
            return .fullText(patterns: variants.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" })
        }
        return .like(patterns: variants.map { variant in
            let escaped = variant
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return "%" + escaped + "%"
        })
    }

    var sql: SQL? {
        guard !terms.isEmpty else { return nil }
        var clauses: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        for term in terms {
            switch term {
            case let .fullText(patterns):
                clauses.append("(" + patterns
                    .map { _ in "id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)" }
                    .joined(separator: " OR ") + ")")
                arguments += patterns
            case let .like(patterns):
                clauses.append("(" + patterns
                    .map { _ in "plain_text LIKE ? ESCAPE '\\' OR IFNULL(source_app_name, '') LIKE ? ESCAPE '\\'" }
                    .joined(separator: " OR ") + ")")
                arguments += patterns.flatMap { [$0, $0] }
            }
        }
        return SQL(sql: clauses.joined(separator: " AND "), arguments: StatementArguments(arguments))
    }
}
```

> 리뷰 반영: 검색어 단어는 앞의 32개까지만 쓴다 (SQLite 바인딩 변수 한도 방어, 커밋 d28a1cf).

- [ ] **Step 5: 조회 작성**

`Sources/PasterCore/Storage/ClipStore+Query.swift`:

```swift
import Foundation
import GRDB

extension ClipStore {
    /// Clipboard 칼럼: 미고정 · 미만료 항목, 최근 복사 순.
    public func fetchUnpinned(
        matching query: String = "",
        settings: RetentionSettings,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 1000
    ) throws -> [ClipItem] {
        var request = ClipItem
            .filter(Column("pinned_at") == nil)
            .filter(Self.notExpired(settings: settings, now: now, calendar: calendar))
        if let condition = SearchFilter(query: query).sql {
            request = request.filter(condition)
        }
        return try dbQueue.read { db in
            try request
                .order(Column("last_copied_at").desc, Column("id").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Pinned 칼럼: pin_order 순. Pin 항목은 만료되지 않는다.
    public func fetchPinned(matching query: String = "") throws -> [ClipItem] {
        var request = ClipItem.filter(Column("pinned_at") != nil)
        if let condition = SearchFilter(query: query).sql {
            request = request.filter(condition)
        }
        return try dbQueue.read { db in
            try request.order(Column("pin_order"), Column("id")).fetchAll(db)
        }
    }

    /// 타입별 기간 안에 있는 행만 통과시키는 조건.
    static func notExpired(settings: RetentionSettings, now: Date, calendar: Calendar) -> SQLExpression {
        ClipKind.allCases
            .map { kind in
                Column("kind") == kind.rawValue
                    && Column("last_copied_at") >= settings[kind].period.cutoff(from: now, calendar: calendar)
            }
            .joined(operator: .or)
    }
}
```

- [ ] **Step 6: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 49 tests in 8 suites passed`

`fileNamesAreSearchable` 가 실패하면 `StoreFixtures.filesClip` 의 NFC 정규화가 빠진 것이다. 파일명 NFC 정규화는 저장 시에만 강제하고, 검색은 저장된 텍스트가 NFC 든 NFD 든 검색어의 NFC · NFD 두 형태를 모두 찾는다 (`nfdTextClipIsFoundByNFCTrigramQuery` 등).

- [ ] **Step 7: 커밋**

```bash
git add Sources/PasterCore/Storage/SearchFilter.swift Sources/PasterCore/Storage/ClipStore+Query.swift Tests/PasterCoreTests/ClipStoreQueryTests.swift Tests/PasterCoreTests/ClipStoreSearchTests.swift
git commit -m "feat(core): add column queries with expiry filter and trigram search" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 고정 / 해제 / Pinned 순서 변경

스펙 7.1절(Pin 해제 시 `last_copied_at = now`), 8.4절(⌘P, ⌥⌘↑/↓).

**Files:**
- Create: `Sources/PasterCore/Storage/ClipStore+Pin.swift`
- Test: `Tests/PasterCoreTests/ClipStorePinTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ClipStorePinTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct ClipStorePinTests {
    let store: ClipStore
    let hour: TimeInterval = 3600

    init() throws {
        store = try Fixtures.makeStore()
    }

    func pinnedTexts() throws -> [String] {
        try store.fetchPinned().map(\.plainText)
    }

    @Test func pinMovesItemToPinnedColumnAtTheEnd() throws {
        let a = try Fixtures.save(Fixtures.textClip("a"), in: store)
        let b = try Fixtures.save(Fixtures.textClip("b"), in: store)
        try store.pin(id: b, now: Fixtures.now)
        try store.pin(id: a, now: Fixtures.now)
        #expect(try pinnedTexts() == ["b", "a"])
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).isEmpty)
        #expect(try store.item(id: a)?.pinnedAt == Fixtures.now)
    }

    @Test func pinningTwiceKeepsOrder() throws {
        let a = try Fixtures.save(Fixtures.textClip("a"), in: store)
        let b = try Fixtures.save(Fixtures.textClip("b"), in: store)
        try store.pin(id: a, now: Fixtures.now)
        try store.pin(id: b, now: Fixtures.now)
        try store.pin(id: a, now: Fixtures.now.addingTimeInterval(5))
        #expect(try pinnedTexts() == ["a", "b"])
        #expect(try store.item(id: a)?.pinnedAt == Fixtures.now)
    }

    @Test func unpinResetsLastCopiedAtSoItDoesNotExpireImmediately() throws {
        var settings = RetentionSettings.default
        settings.text.period = .day
        let old = Fixtures.now.addingTimeInterval(-30 * 24 * hour)
        let id = try Fixtures.save(Fixtures.textClip("long pinned"), in: store, at: old)
        try store.pin(id: id, now: old)
        try store.unpin(id: id, now: Fixtures.now)
        let item = try #require(try store.item(id: id))
        #expect(item.pinnedAt == nil)
        #expect(item.pinOrder == nil)
        #expect(item.lastCopiedAt == Fixtures.now)
        #expect(try store.fetchUnpinned(settings: settings, now: Fixtures.now).map(\.id) == [id])
    }

    @Test func unpinOnUnpinnedItemDoesNothing() throws {
        let id = try Fixtures.save(Fixtures.textClip("x"), in: store)
        try store.unpin(id: id, now: Fixtures.now.addingTimeInterval(99))
        #expect(try store.item(id: id)?.lastCopiedAt == Fixtures.now)
    }

    @Test func movePinnedSwapsNeighbours() throws {
        let ids = try ["a", "b", "c"].map { try Fixtures.save(Fixtures.textClip($0), in: store) }
        for id in ids { try store.pin(id: id, now: Fixtures.now) }

        #expect(try store.movePinned(id: ids[2], direction: .up))
        #expect(try pinnedTexts() == ["a", "c", "b"])
        #expect(try store.movePinned(id: ids[0], direction: .down))
        #expect(try pinnedTexts() == ["c", "a", "b"])
    }

    @Test func movePinnedStopsAtEdges() throws {
        let ids = try ["a", "b"].map { try Fixtures.save(Fixtures.textClip($0), in: store) }
        for id in ids { try store.pin(id: id, now: Fixtures.now) }
        #expect(try store.movePinned(id: ids[0], direction: .up) == false)
        #expect(try store.movePinned(id: ids[1], direction: .down) == false)
        #expect(try pinnedTexts() == ["a", "b"])
    }

    @Test func movePinnedIgnoresUnpinned() throws {
        let id = try Fixtures.save(Fixtures.textClip("x"), in: store)
        #expect(try store.movePinned(id: id, direction: .up) == false)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ClipStorePinTests`
Expected: 빌드 실패 `error: value of type 'ClipStore' has no member 'pin'`

- [ ] **Step 3: 구현**

`Sources/PasterCore/Storage/ClipStore+Pin.swift` — 순서 변경은 이웃과 자리를 바꾼 뒤 0부터 다시 번호를 매긴다 (중간에 빈 번호가 있어도 안전).

```swift
import Foundation
import GRDB

extension ClipStore {
    /// 고정한다. Pinned 칼럼 맨 아래에 붙는다.
    public func pin(id: Int64, now: Date) throws {
        try dbQueue.write { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(pin_order) FROM clip_items WHERE pinned_at IS NOT NULL") ?? -1
            try db.execute(
                sql: "UPDATE clip_items SET pinned_at = ?, pin_order = ? WHERE id = ? AND pinned_at IS NULL",
                arguments: [now, maxOrder + 1, id]
            )
        }
    }

    /// 고정 해제. 해제 즉시 만료되지 않도록 last_copied_at 을 now 로 바꾼다.
    public func unpin(id: Int64, now: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE clip_items SET pinned_at = NULL, pin_order = NULL, last_copied_at = ?
                    WHERE id = ? AND pinned_at IS NOT NULL
                    """,
                arguments: [now, id]
            )
        }
    }

    /// Pinned 칼럼 안에서 한 칸 옮긴다. 옮겼으면 true.
    @discardableResult
    public func movePinned(id: Int64, direction: MoveDirection) throws -> Bool {
        try dbQueue.write { db in
            var ids = try Int64.fetchAll(
                db, sql: "SELECT id FROM clip_items WHERE pinned_at IS NOT NULL ORDER BY pin_order, id"
            )
            guard let index = ids.firstIndex(of: id) else { return false }
            let target = direction == .up ? index - 1 : index + 1
            guard ids.indices.contains(target) else { return false }
            ids.swapAt(index, target)
            for (order, pinnedID) in ids.enumerated() {
                try db.execute(sql: "UPDATE clip_items SET pin_order = ? WHERE id = ?", arguments: [order, pinnedID])
            }
            return true
        }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 56 tests in 9 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Storage/ClipStore+Pin.swift Tests/PasterCoreTests/ClipStorePinTests.swift
git commit -m "feat(core): add pin, unpin and pinned reordering" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 삭제 · 전체 삭제 · 만료 삭제 · 고아 blob

스펙 7.1절: 만료 조건 `pinned_at IS NULL AND last_copied_at < now - 기간`, 만료 시 행 + blob 삭제, 고아 blob 정리, Clear All History 는 미고정 항목과 그 blob 만. 8.4절 ⌘⌫.

> 리뷰 반영: BlobStore 이름 검증(isPlainName), 커밋 3c5d944 (코드는 Task 6 의 BlobStore 블록 참고)

**Files:**
- Create: `Sources/PasterCore/Storage/ClipStore+Delete.swift`
- Test: `Tests/PasterCoreTests/ClipStoreDeleteTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ClipStoreDeleteTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct ClipStoreDeleteTests {
    let store: ClipStore
    let hour: TimeInterval = 3600

    init() throws {
        store = try Fixtures.makeStore()
    }

    func allTexts() throws -> [String] {
        try store.dbQueue.read { try String.fetchAll($0, sql: "SELECT plain_text FROM clip_items ORDER BY id") }
    }

    @Test func deleteRemovesRowBlobAndSearchEntry() throws {
        let image = try store.save(Fixtures.imageClip(seed: 1), now: Fixtures.now).item
        let text = try Fixtures.save(Fixtures.textClip("지울 항목입니다"), in: store)
        #expect(try store.delete(id: image.id!))
        #expect(try store.delete(id: text))
        #expect(store.blobs.allNames().isEmpty)
        #expect(try store.fetchUnpinned(matching: "지울 항목", settings: .default, now: Fixtures.now).isEmpty)
        #expect(try store.delete(id: text) == false)
    }

    @Test func deleteAllUnpinnedKeepsPinned() throws {
        let pinnedImage = try Fixtures.save(Fixtures.imageClip(seed: 1), in: store)
        try store.pin(id: pinnedImage, now: Fixtures.now)
        try Fixtures.save(Fixtures.imageClip(seed: 2), in: store)
        try Fixtures.save(Fixtures.textClip("bye"), in: store)

        #expect(try store.deleteAllUnpinned() == 2)
        #expect(try store.fetchPinned().map(\.id) == [pinnedImage])
        #expect(store.blobs.allNames() == [try store.item(id: pinnedImage)!.imageBlob!])
    }

    @Test func deleteExpiredUsesPerKindPeriodsAndSkipsPinned() throws {
        var settings = RetentionSettings.default
        settings.text.period = .day
        settings.image.period = .week
        settings.files = KindRetention(isEnabled: false, period: .day)

        try Fixtures.save(Fixtures.textClip("text 25h"), in: store, at: Fixtures.now.addingTimeInterval(-25 * hour))
        try Fixtures.save(Fixtures.textClip("text 23h"), in: store, at: Fixtures.now.addingTimeInterval(-23 * hour))
        let pinned = try Fixtures.save(Fixtures.textClip("pinned 1y"), in: store, at: Fixtures.now.addingTimeInterval(-365 * 24 * hour))
        try store.pin(id: pinned, now: Fixtures.now)
        try Fixtures.save(Fixtures.imageClip(seed: 1), in: store, at: Fixtures.now.addingTimeInterval(-8 * 24 * hour))
        let freshImage = try Fixtures.save(Fixtures.imageClip(seed: 2), in: store, at: Fixtures.now.addingTimeInterval(-6 * 24 * hour))
        try Fixtures.save(Fixtures.filesClip(["/tmp/old.txt"]), in: store, at: Fixtures.now.addingTimeInterval(-2 * 24 * hour))

        #expect(try store.deleteExpired(settings: settings, now: Fixtures.now) == 3)
        #expect(try allTexts() == ["text 23h", "pinned 1y", ""])
        #expect(store.blobs.allNames() == [try store.item(id: freshImage)!.imageBlob!])
    }

    @Test func sweepOrphanBlobsRemovesOnlyUnreferencedFiles() throws {
        let kept = try store.save(Fixtures.imageClip(seed: 1), now: Fixtures.now).item.imageBlob!
        let orphan = try store.blobs.write(Data([9]))
        #expect(try store.sweepOrphanBlobs() == 1)
        #expect(store.blobs.allNames() == [kept])
        #expect(store.blobs.read(orphan) == nil)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ClipStoreDeleteTests`
Expected: 빌드 실패 `error: value of type 'ClipStore' has no member 'delete'`

- [ ] **Step 3: 구현**

`Sources/PasterCore/Storage/ClipStore+Delete.swift` — GRDB 의 `SQL` 리터럴 보간(`"... \(condition)"`)은 인자를 안전하게 바인딩한다. 일반 `String` 보간과 섞지 말 것: 조건을 넣는 쿼리는 `SQLRequest<String>(literal:)` 과 `db.execute(literal:)` 로 실행한다. blob 파일은 트랜잭션이 커밋된 뒤 지운다.

```swift
import Foundation
import GRDB

extension ClipStore {
    /// 항목 하나와 그 blob 을 지운다. 지웠으면 true.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        let blobName: String?? = try dbQueue.write { db in
            guard let item = try ClipItem.fetchOne(db, key: id) else { return nil }
            try item.delete(db)
            return .some(item.imageBlob)
        }
        guard let blobName else { return false }
        if let blobName { blobs.remove(blobName) }
        return true
    }

    /// Clear All History: 미고정 항목과 그 blob 만 지운다. 지운 행 수를 돌려준다.
    @discardableResult
    public func deleteAllUnpinned() throws -> Int {
        try deleteRows(where: SQL(sql: "pinned_at IS NULL"))
    }

    /// 만료 조건 `pinned_at IS NULL AND last_copied_at < now - 기간` 에 맞는 행과 blob 을 지운다.
    @discardableResult
    public func deleteExpired(settings: RetentionSettings, now: Date, calendar: Calendar = .current) throws -> Int {
        var conditions: [SQL] = []
        for kind in ClipKind.allCases {
            let cutoff = settings[kind].period.cutoff(from: now, calendar: calendar)
            conditions.append(SQL(sql: "(kind = ? AND last_copied_at < ?)", arguments: [kind.rawValue, cutoff]))
        }
        let expired = conditions.joined(separator: " OR ")
        return try deleteRows(where: "pinned_at IS NULL AND (\(expired))")
    }

    /// DB 가 참조하지 않는 blob 파일을 지운다. 지운 파일 수를 돌려준다.
    /// save 와 같은 write 큐 안에서 실행하므로 저장 중인 blob 을 지우지 않는다.
    @discardableResult
    public func sweepOrphanBlobs() throws -> Int {
        try dbQueue.write { db in
            let referenced = try Set(
                String.fetchAll(db, sql: "SELECT image_blob FROM clip_items WHERE image_blob IS NOT NULL")
            )
            let orphans = blobs.allNames().subtracting(referenced)
            for name in orphans { blobs.remove(name) }
            return orphans.count
        }
    }

    private func deleteRows(where condition: SQL) throws -> Int {
        let (count, blobNames): (Int, [String]) = try dbQueue.write { db in
            let names = try SQLRequest<String>(
                literal: "SELECT image_blob FROM clip_items WHERE image_blob IS NOT NULL AND \(condition)"
            ).fetchAll(db)
            try db.execute(literal: "DELETE FROM clip_items WHERE \(condition)")
            return (db.changesCount, names)
        }
        for name in blobNames { blobs.remove(name) }
        return count
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 60 tests in 10 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Storage/ClipStore+Delete.swift Tests/PasterCoreTests/ClipStoreDeleteTests.swift
git commit -m "feat(core): add delete, clear-all-unpinned, expiry purge and orphan sweep" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 디스크 DB 열기 · 손상 복구

스펙 4절(저장 위치 `paster.sqlite`, `blobs/`), 10절(열기 실패 / 손상 시 `paster.sqlite.corrupt-<timestamp>` 로 보존하고 새 DB). `<timestamp>` 는 Unix 초다.

**Files:**
- Create: `Sources/PasterCore/Storage/ClipStore+Open.swift`
- Test: `Tests/PasterCoreTests/ClipStoreOpenTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/ClipStoreOpenTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct ClipStoreOpenTests {
    @Test func createsDatabaseAndBlobDirectory() throws {
        let directory = try Fixtures.temporaryDirectory().appendingPathComponent("Paster")
        let store = try ClipStore.open(directory: directory)
        try Fixtures.save(Fixtures.textClip("persisted"), in: store)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("paster.sqlite").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("blobs").path))

        let reopened = try ClipStore.open(directory: directory)
        #expect(try reopened.fetchUnpinned(settings: .default, now: Fixtures.now).map(\.plainText) == ["persisted"])
    }

    @Test func corruptDatabaseIsPreservedAndReplaced() throws {
        let directory = try Fixtures.temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("paster.sqlite")
        let garbage = Data(repeating: 0x42, count: 8192)
        try garbage.write(to: databaseURL)

        let store = try ClipStore.open(directory: directory, now: Fixtures.now)
        try Fixtures.save(Fixtures.textClip("fresh"), in: store)

        let corruptURL = directory.appendingPathComponent("paster.sqlite.corrupt-1800000000")
        #expect(try Data(contentsOf: corruptURL) == garbage)
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).count == 1)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ClipStoreOpenTests`
Expected: 빌드 실패 `error: type 'ClipStore' has no member 'open'`

- [ ] **Step 3: 구현**

`Sources/PasterCore/Storage/ClipStore+Open.swift` — 열기 · 마이그레이션 · `PRAGMA quick_check` 중 하나라도 실패하면 DB 파일과 `-wal` / `-shm` / `-journal` 을 같은 접미사로 옮긴다.

```swift
import Foundation
import GRDB

extension ClipStore {
    /// `directory/paster.sqlite` 와 `directory/blobs/` 를 연다.
    /// DB 를 열 수 없거나 손상됐으면 `paster.sqlite.corrupt-<timestamp>` 로 옮겨 보존하고 새 DB 를 만든다.
    public static func open(directory: URL, now: Date = Date()) throws -> ClipStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blobs = try BlobStore(directory: directory.appendingPathComponent(blobDirectoryName, isDirectory: true))
        let databaseURL = directory.appendingPathComponent(databaseFileName)
        do {
            return try openChecked(at: databaseURL, blobs: blobs)
        } catch let error as DatabaseError where isCorruption(error) {
            // BUSY · 권한 등 손상이 아닌 오류는 정상 DB 를 건드리지 않도록 그대로 던진다.
            let name = try quarantine(databaseURL, now: now)
            Log.store.error("DB 손상(result code \(error.resultCode.rawValue, privacy: .public)), \(name, privacy: .public) 로 보존하고 새로 만듦")
            return try openChecked(at: databaseURL, blobs: blobs)
        }
    }

    private static func isCorruption(_ error: DatabaseError) -> Bool {
        switch error.resultCode.primaryResultCode {
        case .SQLITE_NOTADB, .SQLITE_CORRUPT: true
        default: false
        }
    }

    private static func openChecked(at url: URL, blobs: BlobStore) throws -> ClipStore {
        let dbQueue = try DatabaseQueue(path: url.path)
        let result = try dbQueue.read { try String.fetchOne($0, sql: "PRAGMA quick_check") }
        guard result == "ok" else {
            throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: "quick_check: \(result ?? "nil")")
        }
        return try ClipStore(dbQueue: dbQueue, blobs: blobs)
    }

    /// 손상본을 옮기고 본 파일의 새 이름을 돌려준다. 같은 이름이 이미 있으면 `-1`, `-2` ... 를 붙여 덮어쓰지 않는다.
    private static func quarantine(_ url: URL, now: Date) throws -> String {
        let base = ".corrupt-\(Int(now.timeIntervalSince1970))"
        let extras = ["", "-wal", "-shm", "-journal"]
        let fileManager = FileManager.default
        var suffix = base
        var attempt = 0
        while extras.contains(where: { fileManager.fileExists(atPath: url.path + suffix + $0) }) {
            attempt += 1
            suffix = "\(base)-\(attempt)"
        }
        for extra in extras {
            let source = URL(fileURLWithPath: url.path + extra)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: url.path + suffix + extra))
        }
        return url.lastPathComponent + suffix
    }
}
```

> 리뷰 반영: 손상(NOTADB/CORRUPT)일 때만 격리, 그 외 오류는 그대로 던짐, 격리 파일 이름 충돌 시 -1, -2… (커밋 e79172e)

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 62 tests in 11 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Storage/ClipStore+Open.swift Tests/PasterCoreTests/ClipStoreOpenTests.swift
git commit -m "feat(core): open on-disk store and recover from corrupt database" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: UserDefaults 설정

스펙 4절(설정은 UserDefaults), 5.1절(제외 앱, 꺼진 타입), 7.2절(마지막 정리 날짜 기록).

**Files:**
- Create: `Sources/PasterCore/Settings/PasterSettings.swift`
- Test: `Tests/PasterCoreTests/InMemorySettingsStore.swift`
- Test: `Tests/PasterCoreTests/PasterSettingsTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/InMemorySettingsStore.swift`:

```swift
import Foundation
@testable import PasterCore

/// 테스트용 메모리 저장소. 실제 환경설정 파일을 건드리지 않는다.
final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { value(forKey: key) as? Data }
    func stringArray(forKey key: String) -> [String]? { value(forKey: key) as? [String] }
    func string(forKey key: String) -> String? { value(forKey: key) as? String }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    private func value(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }
}
```

`Tests/PasterCoreTests/PasterSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct PasterSettingsTests {
    let store = InMemorySettingsStore()
    let settings: PasterSettings

    init() {
        settings = PasterSettings(store: store)
    }

    @Test func defaultsWhenEmpty() {
        #expect(settings.retention == .default)
        #expect(settings.excludedBundleIDs.isEmpty)
        #expect(settings.lastPurgeDay == nil)
    }

    @Test func retentionPersists() {
        var retention = RetentionSettings.default
        retention.image = KindRetention(isEnabled: false, period: .day)
        settings.retention = retention
        #expect(settings.retention == retention)
    }

    @Test func excludedBundleIDsAreDedupedAndSorted() {
        settings.excludedBundleIDs = ["com.b", "com.a", "com.b"]
        #expect(settings.excludedBundleIDs == ["com.a", "com.b"])
    }

    @Test func makeCaptureReflectsSettings() {
        var retention = RetentionSettings.default
        retention.files.isEnabled = false
        settings.retention = retention
        settings.excludedBundleIDs = ["com.agilebits.onepassword7"]
        let capture = settings.makeCapture()
        #expect(capture.enabledKinds == [.text, .image])
        #expect(capture.excludedBundleIDs == ["com.agilebits.onepassword7"])
    }

    @Test func lastPurgeDayPersists() {
        settings.lastPurgeDay = "2027-01-15"
        #expect(settings.lastPurgeDay == "2027-01-15")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter PasterSettingsTests`
Expected: 빌드 실패 `error: cannot find 'PasterSettings' in scope`

- [ ] **Step 3: 구현**

`Sources/PasterCore/Settings/PasterSettings.swift`:

```swift
import Foundation

/// 설정이 쓰는 키-값 저장소. 앱은 UserDefaults, 테스트는 메모리 저장소를 쓴다.
public protocol SettingsStore: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func stringArray(forKey key: String) -> [String]?
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

/// 저장소(기본값은 UserDefaults)에 저장하는 설정.
public struct PasterSettings: Sendable {
    public enum Key {
        public static let retention = "retention"
        public static let excludedBundleIDs = "excludedBundleIDs"
        public static let lastPurgeDay = "lastPurgeDay"
    }

    private let store: any SettingsStore

    public init(store: any SettingsStore = UserDefaults.standard) {
        self.store = store
    }

    public var retention: RetentionSettings {
        get {
            guard let data = store.data(forKey: Key.retention),
                  let settings = try? JSONDecoder().decode(RetentionSettings.self, from: data)
            else { return .default }
            return settings
        }
        nonmutating set {
            store.set(try? JSONEncoder().encode(newValue), forKey: Key.retention)
        }
    }

    /// 캡처하지 않을 앱의 bundle id. 정렬해서 저장한다.
    public var excludedBundleIDs: [String] {
        get { store.stringArray(forKey: Key.excludedBundleIDs) ?? [] }
        nonmutating set { store.set(Array(Set(newValue)).sorted(), forKey: Key.excludedBundleIDs) }
    }

    /// 마지막으로 정리한 로컬 날짜 (`yyyy-MM-dd`).
    public var lastPurgeDay: String? {
        get { store.string(forKey: Key.lastPurgeDay) }
        nonmutating set { store.set(newValue, forKey: Key.lastPurgeDay) }
    }

    /// 현재 설정으로 만든 캡처 규칙.
    public func makeCapture() -> ClipCapture {
        ClipCapture(excludedBundleIDs: Set(excludedBundleIDs), enabledKinds: retention.enabledKinds)
    }
}
```

> 리뷰 반영: 저장소 주입(SettingsStore), 테스트는 메모리 저장소 사용

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 67 tests in 12 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Settings/PasterSettings.swift Tests/PasterCoreTests/InMemorySettingsStore.swift Tests/PasterCoreTests/PasterSettingsTests.swift
git commit -m "feat(core): add UserDefaults-backed settings" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: RetentionSchedule · RetentionService

스펙 7.2절: 다음 로컬 0시, 잠자기에서 깬 뒤 마지막 정리 이후 날짜가 바뀌었으면 정리, 마지막 정리 날짜 기록. 스펙 11절: 시계 주입.

**Files:**
- Create: `Sources/PasterCore/Retention/RetentionSchedule.swift`
- Create: `Sources/PasterCore/Retention/RetentionService.swift`
- Test: `Tests/PasterCoreTests/RetentionScheduleTests.swift`
- Test: `Tests/PasterCoreTests/RetentionServiceTests.swift`

- [ ] **Step 1: 실패하는 스케줄 테스트 작성**

`Tests/PasterCoreTests/RetentionScheduleTests.swift`:

```swift
import Foundation
import Testing
@testable import PasterCore

struct RetentionScheduleTests {
    func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func nextMidnightInSeoul() {
        let seoul = calendar("Asia/Seoul")
        // 2027-01-15 23:30 KST → 2027-01-16 00:00 KST
        #expect(RetentionSchedule.nextMidnight(after: date("2027-01-15T14:30:00Z"), calendar: seoul) == date("2027-01-15T15:00:00Z"))
    }

    @Test func exactlyMidnightMovesToTheNextDay() {
        let seoul = calendar("Asia/Seoul")
        #expect(RetentionSchedule.nextMidnight(after: date("2027-01-15T15:00:00Z"), calendar: seoul) == date("2027-01-16T15:00:00Z"))
    }

    @Test func missingMidnightFallsToFirstHourOfDay() {
        // 2018-11-04 상파울루는 00:00 → 01:00 으로 건너뛰었다
        let saoPaulo = calendar("America/Sao_Paulo")
        let next = RetentionSchedule.nextMidnight(after: date("2018-11-03T12:00:00Z"), calendar: saoPaulo)
        #expect(next == date("2018-11-04T03:00:00Z"))
    }

    @Test func dayKeyUsesLocalDate() {
        #expect(RetentionSchedule.dayKey(for: date("2027-01-15T15:30:00Z"), calendar: calendar("Asia/Seoul")) == "2027-01-16")
        #expect(RetentionSchedule.dayKey(for: date("2027-01-15T15:30:00Z"), calendar: calendar("UTC")) == "2027-01-15")
    }

    @Test func shouldPurgeOnlyWhenDayChanged() {
        let seoul = calendar("Asia/Seoul")
        let now = date("2027-01-15T03:00:00Z") // 12:00 KST
        #expect(RetentionSchedule.shouldPurge(lastPurgeDay: nil, now: now, calendar: seoul))
        #expect(RetentionSchedule.shouldPurge(lastPurgeDay: "2027-01-14", now: now, calendar: seoul))
        #expect(!RetentionSchedule.shouldPurge(lastPurgeDay: "2027-01-15", now: now, calendar: seoul))
    }
}
```

- [ ] **Step 2: 실패하는 서비스 테스트 작성**

`Tests/PasterCoreTests/RetentionServiceTests.swift` — `TestClock` 은 `@Sendable` 클로저로 넘기기 위해 락으로 감싼 상자다.

```swift
import Foundation
import Testing
@testable import PasterCore

/// 테스트에서 시계를 움직이기 위한 상자.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) { current = date }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

struct RetentionServiceTests {
    let store: ClipStore
    let clock = TestClock(Fixtures.now)
    let settings: PasterSettings
    let service: RetentionService
    let day: TimeInterval = 24 * 3600

    init() throws {
        store = try Fixtures.makeStore()
        settings = PasterSettings(store: InMemorySettingsStore())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let clock = clock
        service = RetentionService(store: store, calendar: calendar, now: { clock.now })
    }

    @Test func purgeDeletesExpiredPerKindAndKeepsPinned() throws {
        var retention = RetentionSettings.default
        retention.text.period = .week
        retention.image.period = .day
        try Fixtures.save(Fixtures.textClip("8 days"), in: store, at: Fixtures.now.addingTimeInterval(-8 * day))
        try Fixtures.save(Fixtures.textClip("6 days"), in: store, at: Fixtures.now.addingTimeInterval(-6 * day))
        try Fixtures.save(Fixtures.imageClip(seed: 1), in: store, at: Fixtures.now.addingTimeInterval(-2 * day))
        let pinned = try Fixtures.save(Fixtures.imageClip(seed: 2), in: store, at: Fixtures.now.addingTimeInterval(-90 * day))
        try store.pin(id: pinned, now: Fixtures.now.addingTimeInterval(-90 * day))

        let report = try service.purge(settings: retention)

        #expect(report == PurgeReport(expiredCount: 2, orphanBlobCount: 0))
        #expect(try store.fetchUnpinned(settings: retention, now: clock.now).map(\.plainText) == ["6 days"])
        #expect(try store.fetchPinned().map(\.id) == [pinned])
        #expect(store.blobs.allNames().count == 1)
    }

    @Test func purgeSweepsOrphanBlobs() throws {
        _ = try store.blobs.write(Data([1]))
        #expect(try service.purge(settings: .default).orphanBlobCount == 1)
        #expect(store.blobs.allNames().isEmpty)
    }

    @Test func expiryFollowsTheInjectedClock() throws {
        var retention = RetentionSettings.default
        retention.text.period = .day
        settings.retention = retention
        try Fixtures.save(Fixtures.textClip("today"), in: store, at: Fixtures.now)

        #expect(try service.purge(using: settings).expiredCount == 0)
        clock.advance(by: day + 1)
        #expect(try service.purge(using: settings).expiredCount == 1)
    }

    @Test func purgeRecordsTheLocalDay() throws {
        try service.purge(using: settings)
        // Fixtures.now = 2027-01-15 08:00 UTC = 17:00 KST
        #expect(settings.lastPurgeDay == "2027-01-15")
    }

    @Test func purgeIfDayChangedRunsOncePerDay() throws {
        #expect(try service.purgeIfDayChanged(using: settings) != nil)
        #expect(try service.purgeIfDayChanged(using: settings) == nil)
        clock.advance(by: 7 * 3600) // 2027-01-16 00:00 KST
        #expect(try service.purgeIfDayChanged(using: settings) != nil)
        #expect(settings.lastPurgeDay == "2027-01-16")
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter Retention`
Expected: 빌드 실패 `error: cannot find 'RetentionSchedule' in scope` (그리고 `RetentionService`, `PurgeReport`)

- [ ] **Step 4: 스케줄 작성**

`Sources/PasterCore/Retention/RetentionSchedule.swift`:

```swift
import Foundation

/// 정리 시점 계산 (스펙 7.2절). 순수 함수만 둔다.
public enum RetentionSchedule {
    /// `now` 이후 첫 로컬 0시. 0시가 없는 날(DST)에는 그날의 첫 시각.
    public static func nextMidnight(after now: Date, calendar: Calendar) -> Date {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )!
    }

    /// 로컬 날짜 키 `yyyy-MM-dd`. 마지막 정리 날짜 기록용.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    /// 마지막 정리 이후 로컬 날짜가 바뀌었으면 true. 잠자기에서 깼을 때 쓴다.
    public static func shouldPurge(lastPurgeDay: String?, now: Date, calendar: Calendar) -> Bool {
        lastPurgeDay != dayKey(for: now, calendar: calendar)
    }
}
```

- [ ] **Step 5: 서비스 작성**

`Sources/PasterCore/Retention/RetentionService.swift`:

```swift
import Foundation

public struct PurgeReport: Equatable, Sendable {
    public var expiredCount: Int
    public var orphanBlobCount: Int
}

/// 만료 항목과 고아 blob 정리.
public struct RetentionService: Sendable {
    public let store: ClipStore
    public let calendar: Calendar
    public let now: @Sendable () -> Date

    public init(store: ClipStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    @discardableResult
    public func purge(settings: RetentionSettings) throws -> PurgeReport {
        try purge(settings: settings, at: now())
    }

    /// 정리하고 오늘 날짜를 기록한다.
    @discardableResult
    public func purge(using settings: PasterSettings) throws -> PurgeReport {
        try purge(using: settings, at: now())
    }

    /// 마지막 정리 이후 날짜가 바뀌었을 때만 정리한다. 정리했으면 report, 아니면 nil.
    @discardableResult
    public func purgeIfDayChanged(using settings: PasterSettings) throws -> PurgeReport? {
        // 시계는 호출당 한 번만 읽어 자정에 걸쳐도 기준 시각이 하나로 유지된다
        let current = now()
        guard RetentionSchedule.shouldPurge(lastPurgeDay: settings.lastPurgeDay, now: current, calendar: calendar) else {
            return nil
        }
        return try purge(using: settings, at: current)
    }

    private func purge(settings: RetentionSettings, at current: Date) throws -> PurgeReport {
        let expired = try store.deleteExpired(settings: settings, now: current, calendar: calendar)
        let orphans = try store.sweepOrphanBlobs()
        Log.retention.info("정리 완료: 만료 \(expired, privacy: .public)건, 고아 blob \(orphans, privacy: .public)개")
        return PurgeReport(expiredCount: expired, orphanBlobCount: orphans)
    }

    private func purge(using settings: PasterSettings, at current: Date) throws -> PurgeReport {
        let report = try purge(settings: settings.retention, at: current)
        settings.lastPurgeDay = RetentionSchedule.dayKey(for: current, calendar: calendar)
        return report
    }
}
```

> 리뷰 반영: 공개 메서드 호출마다 `now()` 를 한 번만 읽어 자정에 걸쳐도 cutoff 와 날짜 키가 같은 시각을 쓴다 (커밋 86fa7f4).

- [ ] **Step 6: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 77 tests in 14 suites passed`

- [ ] **Step 7: 커밋**

```bash
git add Sources/PasterCore/Retention/RetentionSchedule.swift Sources/PasterCore/Retention/RetentionService.swift Tests/PasterCoreTests/RetentionScheduleTests.swift Tests/PasterCoreTests/RetentionServiceTests.swift
git commit -m "feat(core): add retention purge service and midnight schedule" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 패널 포커스 · 선택 리듀서

스펙 8.3절 포커스 규칙 전부와 8.4절 키 표의 모든 행. 리듀서는 항목 자체가 아니라 칼럼별 개수와 선택 위치만 안다. 앱(플랜 2)은 목록을 다시 읽을 때마다 `updateCounts` 를, 검색어가 바뀌면 `setQuery` 를 부르고, 반환된 `PanelEffect` 를 실행한다.

effect 의미:
- `nil`: 이벤트를 소비하고 부수 효과 없음 (예: 왼쪽 칼럼에서 ←).
- `.passThrough`: 이벤트를 검색창으로 흘려보낸다 (검색창 안 ←/→ 커서 이동, 목록에서 글자 입력).
- `.paste(column, index:, mode:)`: Enter(`.formatted`) / ⇧Enter(`.plainText`) / ⌘Enter(`.copyOnly`) / ⌘숫자 / 더블클릭.
- `.togglePin`, `.movePinned`, `.delete`, `.close`.

키 표와 테스트의 대응:

| 스펙 | 테스트 |
|---|---|
| 열면 검색창 포커스 | `opensWithSearchFocused` |
| 검색창 ↓ → Clipboard | `downFromSearchGoesToClipboard`, `downFromSearchGoesToPinnedWhenClipboardIsEmpty` |
| 목록 ←/→ 칼럼 전환 | `leftRightSwitchColumns`, `switchingToAnEmptyColumnDoesNothing` |
| 칼럼 맨 위 ↑ → 검색창 | `upFromTopOfEitherColumnGoesToSearch` |
| 왼쪽 칼럼 ←, 오른쪽 칼럼 → 무동작 | `leftInLeftColumnAndRightInRightColumnDoNothing` |
| 검색창 안 ←/→ 는 커서 이동만 | `arrowsInsideSearchMoveTheCursorOnly` |
| 목록에서 글자 입력 → 검색창 | `typingInAListReturnsToSearchAndForwardsTheKey` |
| 칼럼별 마지막 선택 기억 | `eachColumnRemembersItsSelection` |
| Enter / 더블클릭 | `enterPastesFocusedSelectionFormatted`, `enterInSearchPastesClipboardSelection`, `doubleClickSelectsAndPastes` |
| ⇧Enter | `shiftEnterPastesPlainText` |
| ⌘Enter | `cmdEnterCopiesOnly` |
| ⌘1~9 (검색창이면 Clipboard) | `cmdNumberPastesNthItemOfFocusedColumn`, `cmdNumberInSearchUsesClipboard`, `cmdNumberBeyondCountDoesNothing` |
| ⌘P | `cmdPTogglesPinOfSelection`, `cmdPInSearchDoesNothing` |
| ⌥⌘↑/↓ | `optCmdArrowsReorderPinnedAndFollowTheItem`, `optCmdArrowsStopAtEdges`, `optCmdArrowsOnlyWorkInPinned` |
| ⌘⌫ | `cmdDeleteDeletesSelection`, `cmdDeleteInSearchEditsText` |
| Esc | `escapeClearsQueryFirst`, `escapeWithEmptyQueryCloses` |
| ⌘숫자 힌트는 포커스 칼럼에만 (검색창이면 Clipboard) | `activeColumnIsClipboardWhileSearching` |

**Files:**
- Create: `Sources/PasterCore/Panel/PanelState.swift`
- Create: `Sources/PasterCore/Panel/PanelKey.swift`
- Create: `Sources/PasterCore/Panel/PanelReducer.swift`
- Test: `Tests/PasterCoreTests/PanelNavigationTests.swift`
- Test: `Tests/PasterCoreTests/PanelActionTests.swift`

- [ ] **Step 1: 실패하는 포커스 이동 테스트 작성**

`Tests/PasterCoreTests/PanelNavigationTests.swift`:

```swift
import Testing
@testable import PasterCore

/// 스펙 8.3절 포커스 이동 규칙.
struct PanelNavigationTests {
    let base = PanelState(clipboardCount: 3, pinnedCount: 2)

    func reduce(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        PanelReducer.reduce(state, key)
    }

    @Test func opensWithSearchFocused() {
        #expect(PanelState().focus == .search)
    }

    @Test func downFromSearchGoesToClipboard() {
        let (state, effect) = reduce(base, .down)
        #expect(state.focus == .clipboard)
        #expect(state.clipboardIndex == 0)
        #expect(effect == nil)
    }

    @Test func downFromSearchGoesToPinnedWhenClipboardIsEmpty() {
        var empty = base
        empty.clipboardCount = 0
        #expect(reduce(empty, .down).0.focus == .pinned)
        empty.pinnedCount = 0
        #expect(reduce(empty, .down).0.focus == .search)
    }

    @Test func arrowsInsideSearchMoveTheCursorOnly() {
        for key in [PanelKey.left, .right, .up] {
            let (state, effect) = reduce(base, key)
            #expect(state == base)
            #expect(effect == .passThrough)
        }
    }

    @Test func downAndUpMoveWithinColumn() {
        var state = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2)
        state = reduce(state, .down).0
        state = reduce(state, .down).0
        #expect(state.clipboardIndex == 2)
        state = reduce(state, .down).0
        #expect(state.clipboardIndex == 2) // 맨 아래에서 멈춤
        state = reduce(state, .up).0
        #expect(state.clipboardIndex == 1)
        #expect(state.focus == .clipboard)
    }

    @Test func upFromTopOfEitherColumnGoesToSearch() {
        let fromClipboard = reduce(PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2), .up).0
        #expect(fromClipboard.focus == .search)
        let fromPinned = reduce(PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 2), .up).0
        #expect(fromPinned.focus == .search)
    }

    @Test func leftRightSwitchColumns() {
        let start = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2)
        let right = reduce(start, .right).0
        #expect(right.focus == .pinned)
        let left = reduce(right, .left).0
        #expect(left.focus == .clipboard)
    }

    @Test func leftInLeftColumnAndRightInRightColumnDoNothing() {
        let clipboard = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2, clipboardIndex: 1)
        let (afterLeft, leftEffect) = reduce(clipboard, .left)
        #expect(afterLeft == clipboard)
        #expect(leftEffect == nil)

        let pinned = PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 2, pinnedIndex: 1)
        let (afterRight, rightEffect) = reduce(pinned, .right)
        #expect(afterRight == pinned)
        #expect(rightEffect == nil)
    }

    @Test func switchingToAnEmptyColumnDoesNothing() {
        let state = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 0)
        #expect(reduce(state, .right).0.focus == .clipboard)
    }

    @Test func eachColumnRemembersItsSelection() {
        var state = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2)
        state = reduce(state, .down).0
        state = reduce(state, .down).0      // clipboard 2
        state = reduce(state, .right).0
        state = reduce(state, .down).0      // pinned 1
        state = reduce(state, .left).0
        #expect(state.focus == .clipboard)
        #expect(state.clipboardIndex == 2)
        state = reduce(state, .right).0
        #expect(state.pinnedIndex == 1)
    }

    @Test func typingInAListReturnsToSearchAndForwardsTheKey() {
        let state = PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 2, pinnedIndex: 1)
        let (next, effect) = reduce(state, .textInput)
        #expect(next.focus == .search)
        #expect(next.pinnedIndex == 1)
        #expect(effect == .passThrough)
    }

    @Test func typingInSearchPassesThrough() {
        #expect(reduce(base, .textInput) == (base, .passThrough))
    }

    @Test func activeColumnIsClipboardWhileSearching() {
        #expect(base.activeColumn == .clipboard)
        #expect(PanelState(focus: .pinned, pinnedCount: 1).activeColumn == .pinned)
        #expect(PanelState(focus: .search).activeIndex == nil)
        #expect(PanelState(focus: .search, clipboardCount: 2, clipboardIndex: 1).activeIndex == 1)
    }

    @Test func updateCountsClampsSelectionAndMovesFocusOutOfEmptyColumns() {
        var state = PanelState(focus: .pinned, clipboardCount: 5, pinnedCount: 1, clipboardIndex: 4, pinnedIndex: 0)
        state.updateCounts(clipboard: 2, pinned: 0)
        #expect(state.clipboardIndex == 1)
        #expect(state.focus == .clipboard)
        state.updateCounts(clipboard: 0, pinned: 0)
        #expect(state.focus == .search)
        #expect(state.clipboardIndex == 0)
    }

    @Test func setQueryResetsSelections() {
        var state = PanelState(focus: .search, clipboardCount: 5, pinnedCount: 3, clipboardIndex: 4, pinnedIndex: 2)
        state.setQuery("abc")
        #expect(state.query == "abc")
        #expect(state.clipboardIndex == 0)
        #expect(state.pinnedIndex == 0)
    }

    @Test func clickSelectsAndFocusesColumn() {
        let (state, effect) = reduce(base, .click(.pinned, 1))
        #expect(state.focus == .pinned)
        #expect(state.pinnedIndex == 1)
        #expect(effect == nil)
        #expect(reduce(base, .click(.pinned, 5)).0 == base)
    }
}
```

- [ ] **Step 2: 실패하는 키 표 테스트 작성**

`Tests/PasterCoreTests/PanelActionTests.swift`:

```swift
import Testing
@testable import PasterCore

/// 스펙 8.4절 키 표.
struct PanelActionTests {
    let search = PanelState(focus: .search, clipboardCount: 3, pinnedCount: 2, clipboardIndex: 1)
    let clipboard = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2, clipboardIndex: 2)
    let pinned = PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 3, pinnedIndex: 1)

    func effect(_ state: PanelState, _ key: PanelKey) -> PanelEffect? {
        PanelReducer.reduce(state, key).1
    }

    // Enter / ⇧Enter / ⌘Enter

    @Test func enterPastesFocusedSelectionFormatted() {
        #expect(effect(clipboard, .enter) == .paste(.clipboard, index: 2, mode: .formatted))
        #expect(effect(pinned, .enter) == .paste(.pinned, index: 1, mode: .formatted))
    }

    @Test func enterInSearchPastesClipboardSelection() {
        #expect(effect(search, .enter) == .paste(.clipboard, index: 1, mode: .formatted))
    }

    @Test func shiftEnterPastesPlainText() {
        #expect(effect(clipboard, .shiftEnter) == .paste(.clipboard, index: 2, mode: .plainText))
        #expect(effect(search, .shiftEnter) == .paste(.clipboard, index: 1, mode: .plainText))
    }

    @Test func cmdEnterCopiesOnly() {
        #expect(effect(pinned, .cmdEnter) == .paste(.pinned, index: 1, mode: .copyOnly))
        #expect(effect(search, .cmdEnter) == .paste(.clipboard, index: 1, mode: .copyOnly))
    }

    @Test func enterWithNothingToPasteDoesNothing() {
        #expect(effect(PanelState(), .enter) == nil)
    }

    @Test func doubleClickSelectsAndPastes() {
        let (state, effect) = PanelReducer.reduce(search, .doubleClick(.pinned, 0))
        #expect(effect == .paste(.pinned, index: 0, mode: .formatted))
        #expect(state.focus == .pinned)
        #expect(state.pinnedIndex == 0)
    }

    // ⌘1~9

    @Test func cmdNumberPastesNthItemOfFocusedColumn() {
        #expect(effect(clipboard, .cmdNumber(1)) == .paste(.clipboard, index: 0, mode: .formatted))
        #expect(effect(pinned, .cmdNumber(3)) == .paste(.pinned, index: 2, mode: .formatted))
    }

    @Test func cmdNumberInSearchUsesClipboard() {
        #expect(effect(search, .cmdNumber(2)) == .paste(.clipboard, index: 1, mode: .formatted))
    }

    @Test func cmdNumberBeyondCountDoesNothing() {
        #expect(effect(clipboard, .cmdNumber(4)) == nil)
        #expect(effect(search, .cmdNumber(9)) == nil)
    }

    // ⌘P

    @Test func cmdPTogglesPinOfSelection() {
        #expect(effect(clipboard, .cmdP) == .togglePin(.clipboard, index: 2))
        #expect(effect(pinned, .cmdP) == .togglePin(.pinned, index: 1))
    }

    @Test func cmdPInSearchDoesNothing() {
        #expect(PanelReducer.reduce(search, .cmdP) == (search, nil))
    }

    // ⌥⌘↑ / ↓

    @Test func optCmdArrowsReorderPinnedAndFollowTheItem() {
        let (up, upEffect) = PanelReducer.reduce(pinned, .optCmdUp)
        #expect(upEffect == .movePinned(index: 1, direction: .up))
        #expect(up.pinnedIndex == 0)

        let (down, downEffect) = PanelReducer.reduce(pinned, .optCmdDown)
        #expect(downEffect == .movePinned(index: 1, direction: .down))
        #expect(down.pinnedIndex == 2)
    }

    @Test func optCmdArrowsStopAtEdges() {
        var top = pinned
        top.pinnedIndex = 0
        #expect(effect(top, .optCmdUp) == nil)
        var bottom = pinned
        bottom.pinnedIndex = 2
        #expect(effect(bottom, .optCmdDown) == nil)
    }

    @Test func optCmdArrowsOnlyWorkInPinned() {
        #expect(effect(clipboard, .optCmdUp) == nil)
        #expect(effect(search, .optCmdDown) == nil)
    }

    // ⌘⌫

    @Test func cmdDeleteDeletesSelection() {
        #expect(effect(clipboard, .cmdDelete) == .delete(.clipboard, index: 2))
        #expect(effect(pinned, .cmdDelete) == .delete(.pinned, index: 1))
    }

    @Test func cmdDeleteInSearchEditsText() {
        #expect(effect(search, .cmdDelete) == .passThrough)
    }

    // Esc

    @Test func escapeClearsQueryFirst() {
        var state = clipboard
        state.query = "abc"
        let (next, effect) = PanelReducer.reduce(state, .escape)
        #expect(next.query == "")
        #expect(next.focus == .search)
        #expect(next.clipboardIndex == 0)
        #expect(effect == nil)
    }

    @Test func escapeWithEmptyQueryCloses() {
        #expect(effect(search, .escape) == .close)
        #expect(effect(pinned, .escape) == .close)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter Panel`
Expected: 빌드 실패 `error: cannot find 'PanelState' in scope` (그리고 `PanelReducer`, `PanelKey`)

- [ ] **Step 4: 상태 작성**

`Sources/PasterCore/Panel/PanelState.swift`:

```swift
/// 패널의 두 칼럼.
public enum PanelColumn: Equatable, Sendable {
    case clipboard
    case pinned

    var focus: PanelFocus {
        switch self {
        case .clipboard: .clipboard
        case .pinned: .pinned
        }
    }
}

/// 키보드 포커스 위치.
public enum PanelFocus: Equatable, Sendable {
    case search
    case clipboard
    case pinned
}

/// 붙여넣기 방식.
public enum PasteMode: Equatable, Sendable {
    /// Enter: 서식 유지
    case formatted
    /// ⇧Enter: 일반 텍스트
    case plainText
    /// ⌘Enter: 복사만
    case copyOnly
}

/// 패널의 포커스 · 선택 상태. 항목 자체가 아니라 개수와 위치만 가진다.
public struct PanelState: Equatable, Sendable {
    public var focus: PanelFocus
    public var query: String
    public var clipboardCount: Int
    public var pinnedCount: Int
    /// 칼럼별 마지막 선택 위치
    public var clipboardIndex: Int
    public var pinnedIndex: Int

    public init(
        focus: PanelFocus = .search,
        query: String = "",
        clipboardCount: Int = 0,
        pinnedCount: Int = 0,
        clipboardIndex: Int = 0,
        pinnedIndex: Int = 0
    ) {
        self.focus = focus
        self.query = query
        self.clipboardCount = clipboardCount
        self.pinnedCount = pinnedCount
        self.clipboardIndex = clipboardIndex
        self.pinnedIndex = pinnedIndex
    }

    /// ⌘숫자 힌트 · 미리보기 · Enter 의 대상 칼럼. 검색창 포커스면 Clipboard.
    public var activeColumn: PanelColumn {
        focus == .pinned ? .pinned : .clipboard
    }

    /// 대상 칼럼의 선택 위치. 칼럼이 비어 있으면 nil.
    public var activeIndex: Int? {
        count(of: activeColumn) > 0 ? selectedIndex(in: activeColumn) : nil
    }

    public func count(of column: PanelColumn) -> Int {
        switch column {
        case .clipboard: clipboardCount
        case .pinned: pinnedCount
        }
    }

    public func selectedIndex(in column: PanelColumn) -> Int {
        switch column {
        case .clipboard: clipboardIndex
        case .pinned: pinnedIndex
        }
    }

    mutating func setIndex(_ index: Int, in column: PanelColumn) {
        switch column {
        case .clipboard: clipboardIndex = index
        case .pinned: pinnedIndex = index
        }
    }

    /// 목록을 다시 읽은 뒤 호출한다. 선택을 범위 안으로 맞추고, 비어 버린 칼럼에서 포커스를 옮긴다.
    public mutating func updateCounts(clipboard: Int, pinned: Int) {
        clipboardCount = clipboard
        pinnedCount = pinned
        clipboardIndex = min(clipboardIndex, max(clipboard - 1, 0))
        pinnedIndex = min(pinnedIndex, max(pinned - 1, 0))
        switch focus {
        case .clipboard where clipboard == 0:
            focus = pinned > 0 ? .pinned : .search
        case .pinned where pinned == 0:
            focus = clipboard > 0 ? .clipboard : .search
        default:
            break
        }
    }

    /// 검색어가 바뀌면 결과가 달라지므로 두 칼럼의 선택을 맨 위로 되돌린다.
    public mutating func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        clipboardIndex = 0
        pinnedIndex = 0
    }
}
```

- [ ] **Step 5: 입력 · 출력 타입 작성**

`Sources/PasterCore/Panel/PanelKey.swift`:

```swift
/// 리듀서 입력. 키 입력과 마우스 클릭을 함께 다룬다.
public enum PanelKey: Equatable, Sendable {
    case up
    case down
    case left
    case right
    case enter
    case shiftEnter
    case cmdEnter
    /// ⌘1~9 (1부터 시작)
    case cmdNumber(Int)
    case cmdP
    case optCmdUp
    case optCmdDown
    case cmdDelete
    case escape
    /// 글자 입력 · ⌫ 등 검색창 편집 키
    case textInput
    case click(PanelColumn, Int)
    case doubleClick(PanelColumn, Int)
}

/// 리듀서 출력 중 상태 변경 외의 동작.
public enum PanelEffect: Equatable, Sendable {
    /// 이벤트를 소비하지 않고 검색창으로 흘려보낸다.
    case passThrough
    case paste(PanelColumn, index: Int, mode: PasteMode)
    /// ⌘P: 고정 / 해제
    case togglePin(PanelColumn, index: Int)
    case movePinned(index: Int, direction: MoveDirection)
    case delete(PanelColumn, index: Int)
    case close
}
```

- [ ] **Step 6: 리듀서 작성**

`Sources/PasterCore/Panel/PanelReducer.swift`:

```swift
/// 패널 키 처리 (스펙 8.3, 8.4절). 순수 함수.
/// 반환한 effect 가 nil 이면 이벤트를 소비하고 아무 부수 효과도 없다.
public enum PanelReducer {
    public static func reduce(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        var state = state
        switch key {
        case .escape:
            guard !state.query.isEmpty else { return (state, .close) }
            state.setQuery("")
            state.focus = .search
            return (state, nil)
        case .textInput:
            state.focus = .search
            return (state, .passThrough)
        case let .click(column, index):
            guard select(&state, column, index) else { return (state, nil) }
            return (state, nil)
        case let .doubleClick(column, index):
            guard select(&state, column, index) else { return (state, nil) }
            return (state, .paste(column, index: index, mode: .formatted))
        default:
            break
        }

        switch state.focus {
        case .search: return reduceSearch(state, key)
        case .clipboard: return reduceList(state, .clipboard, key)
        case .pinned: return reduceList(state, .pinned, key)
        }
    }

    private static func reduceSearch(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        var state = state
        switch key {
        case .down:
            if state.clipboardCount > 0 {
                state.focus = .clipboard
            } else if state.pinnedCount > 0 {
                state.focus = .pinned
            }
            return (state, nil)
        case .up, .left, .right, .cmdDelete:
            // 검색창 안의 커서 이동 · 편집
            return (state, .passThrough)
        case .enter:
            return paste(state, .clipboard, state.clipboardIndex, .formatted)
        case .shiftEnter:
            return paste(state, .clipboard, state.clipboardIndex, .plainText)
        case .cmdEnter:
            return paste(state, .clipboard, state.clipboardIndex, .copyOnly)
        case let .cmdNumber(number):
            return paste(state, .clipboard, number - 1, .formatted)
        case .cmdP, .optCmdUp, .optCmdDown:
            return (state, nil)
        case .escape, .textInput, .click, .doubleClick:
            return (state, nil)
        }
    }

    private static func reduceList(_ state: PanelState, _ column: PanelColumn, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        var state = state
        let index = state.selectedIndex(in: column)
        let count = state.count(of: column)
        switch key {
        case .up:
            if index == 0 {
                state.focus = .search
            } else {
                state.setIndex(index - 1, in: column)
            }
            return (state, nil)
        case .down:
            if index + 1 < count { state.setIndex(index + 1, in: column) }
            return (state, nil)
        case .left:
            if column == .pinned, state.clipboardCount > 0 { state.focus = .clipboard }
            return (state, nil)
        case .right:
            if column == .clipboard, state.pinnedCount > 0 { state.focus = .pinned }
            return (state, nil)
        case .enter:
            return paste(state, column, index, .formatted)
        case .shiftEnter:
            return paste(state, column, index, .plainText)
        case .cmdEnter:
            return paste(state, column, index, .copyOnly)
        case let .cmdNumber(number):
            return paste(state, column, number - 1, .formatted)
        case .cmdP:
            guard index < count else { return (state, nil) }
            return (state, .togglePin(column, index: index))
        case .optCmdUp:
            guard column == .pinned, index > 0, index < count else { return (state, nil) }
            state.setIndex(index - 1, in: column)
            return (state, .movePinned(index: index, direction: .up))
        case .optCmdDown:
            guard column == .pinned, index + 1 < count else { return (state, nil) }
            state.setIndex(index + 1, in: column)
            return (state, .movePinned(index: index, direction: .down))
        case .cmdDelete:
            guard index < count else { return (state, nil) }
            return (state, .delete(column, index: index))
        case .escape, .textInput, .click, .doubleClick:
            return (state, nil)
        }
    }

    private static func paste(_ state: PanelState, _ column: PanelColumn, _ index: Int, _ mode: PasteMode) -> (PanelState, PanelEffect?) {
        guard index >= 0, index < state.count(of: column) else { return (state, nil) }
        return (state, .paste(column, index: index, mode: mode))
    }

    private static func select(_ state: inout PanelState, _ column: PanelColumn, _ index: Int) -> Bool {
        guard index >= 0, index < state.count(of: column) else { return false }
        state.focus = column.focus
        state.setIndex(index, in: column)
        return true
    }
}
```

- [ ] **Step 7: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 111 tests in 16 suites passed`

- [ ] **Step 8: 커밋**

```bash
git add Sources/PasterCore/Panel/PanelState.swift Sources/PasterCore/Panel/PanelKey.swift Sources/PasterCore/Panel/PanelReducer.swift Tests/PasterCoreTests/PanelNavigationTests.swift Tests/PasterCoreTests/PanelActionTests.swift
git commit -m "feat(core): add panel focus and selection reducer" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: 키 이벤트 → PanelKey 매핑

앱의 `NSEvent` 를 AppKit 없이 테스트하기 위해, 가상 키 코드(Carbon `kVK_*` 값) + 수정 키 + `charactersIgnoringModifiers` 를 받아 `PanelKey` 로 바꾸는 순수 함수를 둔다. 숫자 ⌘1~9 는 자판 배열과 무관하게 물리 키 코드로, ⌘P 는 글자로 판별한다. `nil` 은 "패널이 관여하지 않음"(검색창으로 그대로 전달)이다.

**Files:**
- Create: `Sources/PasterCore/Panel/PanelKeyMapper.swift`
- Test: `Tests/PasterCoreTests/PanelKeyMapperTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PasterCoreTests/PanelKeyMapperTests.swift`:

```swift
import Testing
@testable import PasterCore

struct PanelKeyMapperTests {
    typealias Code = PanelKeyMapper.KeyCode

    func key(_ code: UInt16, _ modifiers: KeyModifiers = [], _ characters: String? = nil) -> PanelKey? {
        PanelKeyMapper.key(keyCode: code, modifiers: modifiers, characters: characters)
    }

    @Test func returnVariants() {
        #expect(key(Code.returnKey) == .enter)
        #expect(key(Code.keypadEnter) == .enter)
        #expect(key(Code.returnKey, .shift) == .shiftEnter)
        #expect(key(Code.returnKey, .command) == .cmdEnter)
        #expect(key(Code.returnKey, .control) == nil)
    }

    @Test func arrows() {
        #expect(key(Code.upArrow) == .up)
        #expect(key(Code.downArrow) == .down)
        #expect(key(Code.leftArrow) == .left)
        #expect(key(Code.rightArrow) == .right)
        #expect(key(Code.upArrow, [.command, .option]) == .optCmdUp)
        #expect(key(Code.downArrow, [.command, .option]) == .optCmdDown)
        #expect(key(Code.leftArrow, .shift) == nil)
    }

    @Test func commandShortcuts() {
        #expect(key(18, .command, "1") == .cmdNumber(1))
        #expect(key(25, .command, "9") == .cmdNumber(9))
        #expect(key(35, .command, "p") == .cmdP)
        #expect(key(Code.delete, .command) == .cmdDelete)
        #expect(key(8, .command, "c") == nil)
    }

    @Test func escape() {
        #expect(key(Code.escape) == .escape)
    }

    @Test func typingIsTextInput() {
        #expect(key(0, [], "a") == .textInput)
        #expect(key(0, .shift, "A") == .textInput)
        #expect(key(49, [], " ") == .textInput)
        #expect(key(Code.delete, [], "\u{7F}") == .textInput)
        #expect(key(18, [], "1") == .textInput)
    }

    @Test func controlAndFunctionKeysAreIgnored() {
        #expect(key(Code.tab, [], "\t") == nil)
        #expect(key(0, .control, "a") == nil)
        #expect(key(122, [], "\u{F704}") == nil) // F1
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter PanelKeyMapperTests`
Expected: 빌드 실패 `error: cannot find 'PanelKeyMapper' in scope` (그리고 `KeyModifiers`)

- [ ] **Step 3: 구현**

`Sources/PasterCore/Panel/PanelKeyMapper.swift`:

```swift
/// 수정 키. 앱은 NSEvent.ModifierFlags 에서 이 네 개만 옮겨 담는다.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// keyDown (가상 키 코드 + 수정 키 + 글자) → PanelKey. nil 이면 패널이 관여하지 않는 키다.
public enum PanelKeyMapper {
    /// Carbon kVK_* 값
    public enum KeyCode {
        public static let returnKey: UInt16 = 36
        public static let keypadEnter: UInt16 = 76
        public static let tab: UInt16 = 48
        public static let delete: UInt16 = 51
        public static let escape: UInt16 = 53
        public static let leftArrow: UInt16 = 123
        public static let rightArrow: UInt16 = 124
        public static let downArrow: UInt16 = 125
        public static let upArrow: UInt16 = 126
        /// 숫자 줄 1~9 (자판 배열과 무관한 물리 키)
        public static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    /// - Parameter characters: `charactersIgnoringModifiers` (⌘P 판별용)
    public static func key(keyCode: UInt16, modifiers: KeyModifiers, characters: String?) -> PanelKey? {
        switch keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter:
            switch modifiers {
            case []: return .enter
            case .shift: return .shiftEnter
            case .command: return .cmdEnter
            default: return nil
            }
        case KeyCode.escape:
            return modifiers.isEmpty ? .escape : nil
        case KeyCode.upArrow:
            if modifiers == [.command, .option] { return .optCmdUp }
            return modifiers.isEmpty ? .up : nil
        case KeyCode.downArrow:
            if modifiers == [.command, .option] { return .optCmdDown }
            return modifiers.isEmpty ? .down : nil
        case KeyCode.leftArrow:
            return modifiers.isEmpty ? .left : nil
        case KeyCode.rightArrow:
            return modifiers.isEmpty ? .right : nil
        case KeyCode.delete:
            if modifiers == .command { return .cmdDelete }
            return modifiers.isDisjoint(with: [.command, .control]) ? .textInput : nil
        case KeyCode.tab:
            return nil
        default:
            break
        }

        if modifiers == .command {
            if let digit = KeyCode.digits.firstIndex(of: keyCode) { return .cmdNumber(digit + 1) }
            if characters?.lowercased() == "p" { return .cmdP }
            return nil
        }
        // ⌘/⌃ 없이 글자를 만드는 키는 검색창 입력이다
        if modifiers.isDisjoint(with: [.command, .control]),
           let characters, let scalar = characters.unicodeScalars.first,
           !isControl(scalar) {
            return .textInput
        }
        return nil
    }

    /// C0/C1 제어 문자와 기능 키 영역(U+F700~U+F8FF)
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || (0xF700...0xF8FF).contains(scalar.value)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test`
Expected: `✔ Test run with 117 tests in 17 suites passed`

- [ ] **Step 5: 커밋**

```bash
git add Sources/PasterCore/Panel/PanelKeyMapper.swift Tests/PasterCoreTests/PanelKeyMapperTests.swift
git commit -m "feat(core): map key codes and modifiers to panel keys" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: 마무리 점검

**Files:** 없음 (확인만)

- [ ] **Step 1: 깨끗한 빌드로 전체 테스트**

Run: `rm -rf .build && swift test 2>&1 | tail -3`
Expected: 마지막 줄 `✔ Test run with 117 tests in 17 suites passed after ...` 이고 `warning:` 이 없다 (`swift build 2>&1 | grep -c "warning:"` 의 결과가 `0`).

- [ ] **Step 2: PasterCore 가 AppKit 을 쓰지 않는지 확인**

Run: `grep -rnE "import (AppKit|Cocoa|SwiftUI)" Sources/PasterCore || echo "AppKit 없음"`
Expected: `AppKit 없음`

- [ ] **Step 3: 작업 트리 확인**

Run: `git status --short`
Expected: 이 플랜이 만든 파일 중 커밋되지 않은 것이 없다 (다른 작업자의 `README.md` 변경은 무시).
