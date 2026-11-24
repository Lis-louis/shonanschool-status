# CLAUDE.md

キャンパスハブ：Mac 版（Swift / `Sources/CampusHub`）と Windows 版（Electron / `windows/`）の2本立て。
片方を直したら、もう片方にも同じ問題がないか確認すること。

## Mac で確認が必要な未検証の変更

Windows 上で作業したため、以下の Swift の変更はビルド・動作確認ができていない。
Mac で `swift build`（または `scripts/build-app.sh`）を通し、動作を確認したらこの項目を消すこと。

### 2026-11-24：アプリ内ブラウザでページが自分を閉じたとき・表示プロセスが落ちたときの対応
- 発端：Windows 版でキャンパススクエアを操作中に
  `TypeError: Cannot read properties of undefined (reading 'navigationHistory')`（BrowserController.info）で落ちた。
  原因は、ポップアップを同じ画面に読み込んだあと、そのページの「閉じる」ボタンが `window.close()` を呼び、
  WebContentsView の webContents が破棄されたこと。
  → `windows/src/main/browser.js` で、破棄・クラッシュ時に view を作り直して開く前のページへ戻すよう修正済み（Electron で再現・確認済み）。
- Mac 版は WKWebView なので落ちはしないが、「閉じる」が無反応、表示プロセス終了時に真っ白のままだったため、
  `Sources/CampusHub/Web/BrowserController.swift` に以下を追加した（**未ビルド・未確認**）：
  - `createWebViewWith` で開く前の URL を `returnURL` に保存
  - `webViewDidClose(_:)`：`returnURL`（なければ戻る）へ戻る
  - `webViewWebContentProcessDidTerminate(_:)`：開き直してメッセージを表示
- 確認手順：キャンパススクエアで別ウィンドウで開くリンク（シラバス等）→ そのページの「閉じる」を押す → 元のページに戻ること。
