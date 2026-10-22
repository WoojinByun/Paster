#!/bin/bash
# 개발용: debug 빌드를 build/debug/Paster.app 으로 묶고 ad-hoc 서명한다.
# ad-hoc 서명은 빌드마다 바뀌므로 손쉬운 사용 권한을 다시 허용해야 할 수 있다 (플랜 3 의 make cert 로 해결).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
BIN_DIR="$(swift build --show-bin-path)"
APP="build/debug/Paster.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Paster" "$APP/Contents/MacOS/Paster"
# SwiftPM 리소스 번들 (KeyboardShortcuts 지역화 문자열 등). Bundle.module 이 Contents/Resources 에서 찾는다.
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Paster</string>
    <key>CFBundleIdentifier</key><string>com.wjbyun.Paster</string>
    <key>CFBundleName</key><string>Paster</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.0</string>
    <key>CFBundleVersion</key><string>$(git rev-list --count HEAD 2>/dev/null || echo 0)</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "$APP"
