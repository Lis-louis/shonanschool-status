#!/bin/zsh
# packaging/AppIcon.icns を作り直す。
#   icon/campus-hub.svg があればそれを使う（既定）
#   ./scripts/make-icon.sh 画像.jpg  とすると、鈴の顔から自動で作る（scripts/make-icon.swift）
set -euo pipefail
cd "${0:A:h}/.."
TMP="$(mktemp -d)"
if [[ $# -eq 0 && -f icon/campus-hub.svg ]]; then
  swift scripts/svg-to-icon.swift icon/campus-hub.svg "$TMP/icon1024.png"
else
  swift scripts/make-icon.swift "${1:-Sources/CampusHub/Resources/Appearance/face_laugh.jpg}" "$TMP/icon1024.png"
fi
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p packaging
iconutil -c icns "$SET" -o packaging/AppIcon.icns
cp "$TMP/icon1024.png" packaging/AppIcon-1024.png
rm -rf "$TMP"
echo "作成しました: packaging/AppIcon.icns"
