#!/usr/bin/env bash
# AI Pulse.app 빌드 · 서명 · (선택) 공증 · DMG
#
#   ./Scripts/build-app.sh                 build/AIPulse.app (ad-hoc 서명, 이 Mac 에서 실행용)
#   ./Scripts/build-app.sh --install       위 + ~/Applications 에 설치 후 실행
#   ./Scripts/build-app.sh --dmg           위 + build/AIPulse-<버전>.dmg
#
# 환경 변수 (배포용)
#   SIGN_IDENTITY   "Developer ID Application: 이름 (TEAMID)"  → Hardened Runtime 으로 서명
#   NOTARY_PROFILE  xcrun notarytool store-credentials 로 저장한 프로필 이름 → 공증 + staple
#   BUNDLE_ID       번들 ID (기본 dev.aipulse.AIPulse)
#   UNIVERSAL=1     Apple Silicon + Intel 유니버설 바이너리
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
BUNDLE_ID="${BUNDLE_ID:-dev.aipulse.AIPulse}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
INSTALL=0; DMG=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --dmg) DMG=1 ;;
    *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

echo "▸ 빌드 (v$VERSION, $BUILD)"
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP=build/AIPulse.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AIPulse" "$BIN/aipulse-hook" "$BIN/aipulse-mcp" "$APP/Contents/MacOS/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi

# Claude 앱 확장 (.mcpb): manifest + 서명된 MCP 서버
echo "▸ Claude 앱 확장 만들기"
MCPB_DIR=build/mcpb
mkdir -p "$MCPB_DIR/server"
cp "$BIN/aipulse-mcp" "$MCPB_DIR/server/aipulse-mcp"
codesign "${SIGN_FLAGS[@]}" "$MCPB_DIR/server/aipulse-mcp"
sed "s/__VERSION__/$VERSION/" Resources/mcpb/manifest.json > "$MCPB_DIR/manifest.json"
sips -z 512 512 Resources/AppIcon-1024.png --out "$MCPB_DIR/icon.png" >/dev/null
(cd "$MCPB_DIR" && zip -qr ../AIPulse.mcpb manifest.json icon.png server)
cp build/AIPulse.mcpb "$APP/Contents/Resources/AIPulse.mcpb"

echo "▸ 서명 ($SIGN_IDENTITY)"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/aipulse-hook"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/aipulse-mcp"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "✓ $APP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "▸ 공증"
  ditto -c -k --keepParent "$APP" build/AIPulse-notarize.zip
  xcrun notarytool submit build/AIPulse-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm build/AIPulse-notarize.zip
fi

if [[ "$DMG" == "1" ]]; then
  echo "▸ DMG"
  STAGE=build/dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "AI Pulse" -srcfolder "$STAGE" -ov -format UDZO "build/AIPulse-$VERSION.dmg" >/dev/null
  rm -rf "$STAGE"
  if [[ "$SIGN_IDENTITY" != "-" ]]; then codesign --sign "$SIGN_IDENTITY" --timestamp "build/AIPulse-$VERSION.dmg"; fi
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "build/AIPulse-$VERSION.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "build/AIPulse-$VERSION.dmg"
  fi
  echo "✓ build/AIPulse-$VERSION.dmg"
fi

if [[ "$INSTALL" == "1" ]]; then
  DEST="$HOME/Applications/AIPulse.app"
  mkdir -p "$HOME/Applications"
  pkill -x AIPulse 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  # 이미 연결된 훅이 있으면 새 경로로 갱신
  if grep -qs aipulse-hook "$HOME/.claude/settings.json"; then "$DEST/Contents/MacOS/aipulse-hook" install claude >/dev/null; fi
  if grep -qs aipulse-hook "$HOME/.codex/hooks.json"; then "$DEST/Contents/MacOS/aipulse-hook" install codex >/dev/null; fi
  echo "✓ $DEST 설치"
  open "$DEST"
fi
