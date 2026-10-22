#!/bin/bash
# Paster.app 을 조립하고 서명한다.
# 사용법: scripts/bundle.sh [release|debug]
#   release -> build/Paster.app        (make app, make install, make release)
#   debug   -> build/debug/Paster.app  (make run)
# 환경 변수:
#   VERSION       CFBundleShortVersionString (기본 0.0.0).
#                 debug 빌드와 0.0.0 빌드는 Sparkle 피드(SUFeedURL)가 빠진다 (개발 빌드가 릴리스로 덮어쓰이지 않도록)
#   SIGN_IDENTITY 서명 인증서 이름 (기본 "Paster Local Signing").
#                 "-" 를 명시하면 ad-hoc 서명 (CI 등 인증서가 없는 곳 전용. 손쉬운 사용 권한이 빌드마다 초기화된다)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="${VERSION:-0.0.0}"
IDENTITY="${SIGN_IDENTITY:-Paster Local Signing}"
KEY_FILE="Resources/sparkle-public-key.txt"
PLIST_BUDDY=/usr/libexec/PlistBuddy
CODESIGN_TIMEOUT=60

case "$CONFIG" in
    release)
        APP="build/Paster.app"
        # 기본값 0.0.0 (make app) 은 그대로 허용하고, 지정한 버전만 x.y.z 형식인지 검사한다
        if [ "$VERSION" != "0.0.0" ] && [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "error: VERSION 은 x.y.z 형식이어야 합니다 (받은 값: '$VERSION')." >&2
            exit 1
        fi
        ;;
    debug) APP="build/debug/Paster.app" ;;
    *)
        echo "error: 사용법: $0 [release|debug]" >&2
        exit 1
        ;;
esac

if [ ! -s "$KEY_FILE" ]; then
    echo "error: $KEY_FILE 가 없습니다. 먼저 'make sparkle-keys' 를 실행하세요." >&2
    exit 1
fi
PUBLIC_KEY="$(tr -d '[:space:]' < "$KEY_FILE")"

if [ "$IDENTITY" = "-" ]; then
    echo "warning: SIGN_IDENTITY=- : ad-hoc 서명합니다 (배포용이 아님)." >&2
elif ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "error: 코드 서명 인증서 '$IDENTITY' 가 키체인에 없습니다." >&2
    echo "       먼저 'make cert' 를 실행해 인증서를 만드세요." >&2
    echo "       (인증서 없이 빌드만 확인하려면 SIGN_IDENTITY=- 로 ad-hoc 서명할 수 있습니다.)" >&2
    exit 1
fi

# 경고: CFBundleVersion 은 Sparkle 이 업데이트 여부를 가르는 값이라 반드시 단조 증가해야 한다.
# 작업 브랜치(Paster)를 main 에 squash merge 하면 커밋 수가 줄어 빌드 번호가 되돌아가고,
# 이미 설치된 앱이 새 릴리스를 업데이트로 인식하지 못한다. main 에는 merge commit 이나 fast-forward 로만 합친다.
BUILD_NUMBER="$(git rev-list --count HEAD)"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
EXECUTABLE="$APP/Contents/MacOS/Paster"
cp "$BIN_DIR/Paster" "$EXECUTABLE"
# SwiftPM 리소스 번들 (KeyboardShortcuts 지역화 문자열 등). Bundle.module 이 Contents/Resources 에서 찾는다.
# 빠지면 KeyboardShortcuts 단축키 입력기가 크래시한다.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# 앱 아이콘 (Resources/AppIcon.icns 는 scripts/make-icon.sh 로 만들어 커밋해 둔다)
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sparkle.framework. 심볼릭 링크를 유지해야 하므로 ditto 로 복사한다
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
"$PLIST_BUDDY" -c "Set :SUPublicEDKey $PUBLIC_KEY" "$PLIST"

# 개발 빌드 (debug, 또는 VERSION=0.0.0) 는 실제 릴리스 피드를 보지 않게 한다.
# 같은 번들 ID · 데이터를 쓰는데 빌드 번호가 더 낮으면 Sparkle 이 정식 릴리스로 개발 빌드를 덮어쓸 수 있다.
# SUFeedURL 이 없으면 "업데이트 확인…" 은 Sparkle 설정 오류를 보여 준다 (개발 빌드에서는 정상).
if [ "$CONFIG" = "debug" ] || [ "$VERSION" = "0.0.0" ]; then
    "$PLIST_BUDDY" -c "Delete :SUFeedURL" "$PLIST"
    "$PLIST_BUDDY" -c "Add :SUEnableAutomaticChecks bool false" "$PLIST"
    echo "note: 개발 빌드라 Sparkle 업데이트 피드(SUFeedURL)를 끕니다."
fi

# rpath 정리: SwiftPM 이 넣는 빌드 머신의 절대 경로 rpath (예: /Users/<이름>/.../.build/...) 는
# 공개 바이너리에 사용자 이름을 남기고 쓸모도 없으므로 지운다. 서명 전에 해야 한다.
rpaths() {
    otool -l "$EXECUTABLE" | awk '$1 == "cmd" { rpath = ($2 == "LC_RPATH") } rpath && $1 == "path" { print $2 }'
}
while IFS= read -r rpath; do
    case "$rpath" in
        /Users/* | "$PWD"*)
            install_name_tool -delete_rpath "$rpath" "$EXECUTABLE"
            ;;
    esac
done < <(rpaths)
if rpaths | grep -qE "^(/Users/|$PWD)"; then
    echo "error: 실행 파일에 절대 경로 rpath 가 남아 있습니다:" >&2
    rpaths >&2
    exit 1
fi
if ! rpaths | grep -qx "@executable_path/../Frameworks"; then
    echo "error: 실행 파일에 rpath @executable_path/../Frameworks 가 없습니다 (Package.swift linkerSettings 확인)." >&2
    exit 1
fi

# codesign 이 로그인 키체인의 개인 키에 처음 접근할 때 macOS 가 "codesign 이(가) 키에 접근하려고 합니다" 창을 띄운다.
# 응답이 없으면 무한정 기다리므로 시간 제한을 둔다.
sign() {
    local status=0
    if command -v timeout >/dev/null 2>&1; then
        timeout "$CODESIGN_TIMEOUT" codesign --force --sign "$IDENTITY" "$@" || status=$?
    else
        codesign --force --sign "$IDENTITY" "$@" || status=$?
    fi
    if [ "$status" -eq 124 ]; then
        echo "error: codesign 이 ${CODESIGN_TIMEOUT}초 안에 끝나지 않았습니다." >&2
        echo "       키체인 접근 허용 창이 떠 있다면 로그인 암호를 입력하고 '항상 허용' 을 누른 뒤 다시 실행하세요." >&2
    fi
    if [ "$status" -ne 0 ]; then
        exit "$status"
    fi
}

# 안쪽부터 서명: Sparkle XPC 서비스 · 도우미 → 프레임워크 → 앱. --deep 은 쓰지 않는다.
# Hardened Runtime(-o runtime)은 쓰지 않는다: notarize 하지 않고, Team ID 없는 자체 서명 인증서에서
# library validation 이 Sparkle 로딩을 막을 수 있다.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"
codesign --verify --deep --strict "$APP"

echo "$APP ($VERSION, build $BUILD_NUMBER, $CONFIG)"
