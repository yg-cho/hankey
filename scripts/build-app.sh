#!/bin/bash
# 릴리스 빌드 후 dist/HanKey.app 으로 묶는다. --install 을 주면 /Applications 에 복사한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=dist/HanKey.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HanKey "$APP/Contents/MacOS/HanKey"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.hankey.app</string>
    <key>CFBundleName</key><string>HanKey</string>
    <key>CFBundleExecutable</key><string>HanKey</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# 기본은 ad-hoc 서명. HANKEY_SIGN_ID 에 인증서 해시를 주면 그것으로 서명한다
# (다시 빌드해도 손쉬운 사용 권한이 유지된다. 키체인 허용 창이 뜰 수 있다).
codesign --force --sign "${HANKEY_SIGN_ID:--}" "$APP"
echo "built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x HanKey 2>/dev/null || true
    rm -rf /Applications/HanKey.app
    cp -R "$APP" /Applications/HanKey.app
    echo "installed: /Applications/HanKey.app"
fi
