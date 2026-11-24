#!/bin/zsh
# Windows 用のインストーラー（.exe）を Mac 上で作る。
#   ./scripts/build-windows.sh          → CampusHub-Setup-<版>.exe（リポジトリ直下）
#   ./scripts/build-windows.sh --test   → テストだけ
#   ./scripts/build-windows.sh --run    → Mac 上で Windows 版の画面を起動して確認する
#
# 必要なもの: Node.js（node / npm）。PATH に無ければ .build/node/bin を使う。
#   Node.js が無いときは https://nodejs.org/ から LTS 版を入れてください。
set -euo pipefail
cd "${0:A:h}/../windows"

if ! command -v npm >/dev/null 2>&1; then
  if [[ -x ../.build/node/bin/npm ]]; then
    export PATH="${PWD:h}/.build/node/bin:$PATH"
  else
    echo "Node.js が見つかりません。https://nodejs.org/ から LTS 版を入れてから、もう一度実行してください。" >&2
    exit 1
  fi
fi

# 依存（Electron と electron-builder）。package-lock.json があればその版で入れる
if [[ -f package-lock.json ]]; then
  [[ -d node_modules/electron ]] || npm ci
else
  npm install --save-dev --save-exact electron electron-builder
fi

npm test

case "${1:-}" in
  --test) exit 0 ;;
  --run) exec npx electron . ;;
esac

npm run dist:win
