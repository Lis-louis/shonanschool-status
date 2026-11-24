#!/bin/zsh
# キャンパスハブ.app を作成する。
#   ./scripts/build-app.sh            → build/キャンパスハブ.app
#   ./scripts/build-app.sh --install  → さらに /Applications へ入れる（ドックに固定するならこちら）
set -euo pipefail
cd "${0:A:h}/.."

# 仮のバンドルID。キーチェーン・通知・設定はこのIDに紐づくので、決めたら変えないこと。
BUNDLE_ID="${BUNDLE_ID:-local.campushub.app}"
NAME="キャンパスハブ"
# アプリの版は Windows 版と共通（windows/package.json の "version"）。Release のタグ v<版> と自動更新の比較に使う。
APP_VERSION="${APP_VERSION:-$(sed -n 's/^ *"version": *"\([0-9.]*\)".*/\1/p' windows/package.json | head -1)}"
[[ -n "$APP_VERSION" ]] || { echo "windows/package.json から版を読めませんでした" >&2; exit 1; }
VERSION="$(date +%Y%m%d.%H%M%S)"   # ビルドごとに変える（ドックのアイコンキャッシュ対策）
APP="build/${NAME}.app"

# Apple シリコンと Intel の両方で動くようにする（ARCHS="arm64" などで変えられる）
ARCH_FLAGS=()
for a in ${=ARCHS:-arm64 x86_64}; do ARCH_FLAGS+=(--arch "$a"); done
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

[[ -f packaging/AppIcon.icns ]] || ./scripts/make-icon.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CampusHub" "$APP/Contents/MacOS/CampusHub"
# アイコンの名前に内容のハッシュを付ける（macOS のアイコンキャッシュに古い絵が残らないように）
ICON_NAME="AppIcon-$(md5 -q packaging/AppIcon.icns | cut -c1-8)"
cp packaging/AppIcon.icns "$APP/Contents/Resources/${ICON_NAME}.icns"
# 鈴の画像など（SwiftPM のリソースバンドル）
cp -R "$BIN_DIR/CampusHub_CampusHub.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundleDisplayName</key><string>${NAME}</string>
  <key>CFBundleExecutable</key><string>CampusHub</string>
  <key>CFBundleIconFile</key><string>${ICON_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleDevelopmentRegion</key><string>ja</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "作成しました: $APP（版 ${APP_VERSION}・$(lipo -archs "$APP/Contents/MacOS/CampusHub")）"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/${NAME}.app"
  osascript -e "quit app \"${NAME}\"" >/dev/null 2>&1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  # Finder・ドックのアイコンを更新
  touch "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
  echo "インストールしました: $DEST"
  echo "起動: open \"$DEST\"（起動中にドックのアイコンを右クリック →「オプション」→「Dockに追加」）"
else
  echo "起動: open \"$APP\""
fi
