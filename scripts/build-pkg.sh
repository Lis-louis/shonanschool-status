#!/bin/zsh
# Mac 用のインストーラー（.pkg）を作る。
#   ./scripts/build-pkg.sh   → dist/CampusHub-<版>.pkg
# ダブルクリックすると /Applications/キャンパスハブ.app に入ります。
# Apple の開発者署名はしていないため、初回は「右クリック → 開く」か
# 「システム設定 → プライバシーとセキュリティ → このまま開く」が必要です。
set -euo pipefail
cd "${0:A:h}/.."

NAME="キャンパスハブ"
BUNDLE_ID="${BUNDLE_ID:-local.campushub.app}"
VERSION="${VERSION:-0.2.0}"
APP="build/${NAME}.app"
OUT="dist/CampusHub-${VERSION}.pkg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

./scripts/build-app.sh

# pkgbuild は .app を丸ごと入れる「コンポーネント」として扱う。
# 再配置（別の場所にある古い .app を上書き）は混乱のもとなので無効にする。
mkdir -p "$TMP/root/Applications"
ditto "$APP" "$TMP/root/Applications/${NAME}.app"
pkgbuild --analyze --root "$TMP/root" "$TMP/components.plist"
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$TMP/components.plist"

pkgbuild --root "$TMP/root" \
  --component-plist "$TMP/components.plist" \
  --identifier "${BUNDLE_ID}.pkg" \
  --version "$VERSION" \
  --install-location / \
  "$TMP/CampusHub-component.pkg"

cat > "$TMP/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>${NAME}</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <domains enable_localSystem="true"/>
  <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="${NAME}"><pkg-ref id="${BUNDLE_ID}.pkg"/></choice>
  <pkg-ref id="${BUNDLE_ID}.pkg" version="${VERSION}" onConclusion="none">CampusHub-component.pkg</pkg-ref>
</installer-gui-script>
XML

mkdir -p "$TMP/resources"
cat > "$TMP/resources/welcome.html" <<HTML
<!doctype html><meta charset="utf-8">
<body style="font-family:-apple-system,'Hiragino Sans',sans-serif;color:#2B3A6E">
<h2>${NAME} ${VERSION}</h2>
<p>湘南工科大学の Moodle・Campus Square・大学メールを1つにまとめるアプリです。</p>
<p>「アプリケーション」フォルダに入ります。起動後、「設定 → ログイン情報」で学籍番号とパスワードを保存してください（キーチェーンにだけ保存されます）。</p>
</body>
HTML

mkdir -p dist
productbuild --distribution "$TMP/distribution.xml" \
  --package-path "$TMP" \
  --resources "$TMP/resources" \
  "$OUT"
echo "作成しました: $OUT"
