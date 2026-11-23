# キャンパスハブ（my-school-status）

湘南工科大学の Moodle・Campus Square・大学メールを1つにまとめるアプリ。Mac版（SwiftUI）と Windows版（Electron、`windows/`）があります。
見た目は鈴（`../suzu_ai`）と同じ配色・部品で、鈴の画像を使っています（昼／夜はmacOSの外観に連動）。

## 画面

| 画面 | 内容 |
| --- | --- |
| ホーム | 今日の授業／**やること（まだできていないこと）**＝Moodleの未完了課題＋メールの要対応／お知らせ／学校から届いているメール |
| カレンダー | 月表示。毎週の時間割・Moodleの予定・締切・メールで見つけた期限を日ごとに表示 |
| Moodle | **まとめ**：課題・締切、通知、コース（進捗つき）。**ブラウザ**：公式サイトをアプリ内で表示 |
| Campus Square | **まとめ**：曜日別の時間割、休講・補講の表、ポータルの各お知らせ。**ブラウザ**：公式サイト |
| メール | Gmail を読み取り専用で取得し「要対応・締切／休講・授業変更／試験・レポート／Moodle通知／行事／お知らせ」に自動で仕分け。督促・未提出などの語や期限の日付も検出 |
| 設定 | ログイン情報、Gmail連携、自動ログイン、URL、表示項目、通知、サンプル表示、**接続の診断** |

## しくみ

1. **自動ログイン**：保存したID・パスワードを、公式ログインページ（Moodle: `#username`/`#password`、Campus Square: `#userNameInput`/`#passwordInput`）の入力欄に入れてボタンを押します。ログイン画面を自作・模倣はしません。
2. **まとめ表示**：画面に出さない WebView でログイン後のページを開き、
   - Moodle：Moodle自身のダッシュボードが使う AJAX サービス（`core_course_get_enrolled_courses_by_timeline_classification`、`core_calendar_get_action_events_by_timesort`、`message_popup_get_popup_notifications`）をログイン中のページから呼びます。
   - Campus Square：ポータルの各枠の文字、曜日が並ぶ表（時間割）、休講ページの表を読み取ります。
3. **アプリ内ブラウザ**：教材のダウンロード（~/Downloads）、課題ファイルのアップロード、`_blank` リンクに対応。大学のドメイン外のリンクは既定のブラウザで開きます。

### 安全のための決まり
- ID・パスワードは macOS キーチェーンにだけ保存（`WhenUnlockedThisDeviceOnly`：iCloud同期・移行なし）。コード・設定ファイル・ログには出しません。
- 自動入力は「https で、設定したログインホストと完全一致するページ」だけ。ページのスクリプトから隔離された環境（`WKContentWorld.defaultClient`）で入力します。
- 自動でボタンを押すのは30秒に1回まで（失敗を繰り返してアカウントロックされないように）。
- 読み取った内容はメモリ上だけで、ファイルに保存しません。Cookie はこのアプリ専用の保存場所に残ります（設定 →「ログイン状態を消去」で削除）。
- 自動ログインや画面の読み取りが大学の利用規約・情報ポリシーで認められているかは、各自で確認してください。更新は手動（起動時と「更新」ボタン）だけで、大学のサーバーに負荷をかける定期取得はしません。

## 未確定・推定の値

| 項目 | 値 | 状態 |
| --- | --- | --- |
| Moodle | `https://moodle2026.shonan-it.ac.jp` | 確認済み（ログインフォームも確認） |
| Campus Square | `https://portal.shonan-it.ac.jp/campusweb/` | 確認済み（ログインフォームも確認） |
| 時間割 | `campussquare.do?_flowId=RSW0001000-flow` | 確認済み（ポータルのメニュー「履修登録・登録状況照会」） |
| 休講・補講 | `_flowId=KHW0001100-flow` | **推定** |
| 成績 / シラバス | `SIW0001300-flow` / `SYW0001000-flow` | **推定** |
| 出席管理 | `https://syusseki.shonan-it.ac.jp/campusaa/` | ログインページのリンクより |
| 大学メール | Google Workspace（Gmail） | DNS（MXレコード）で確認 |

推定のページが違う場合：Campus Square の「ブラウザ」で正しいページを開き、右上の「…」→「このページを『時間割』に設定」。

## メール（Gmail）の連携手順

Google は、アプリに埋め込んだブラウザでのログインを認めていないため、Google 公式の OAuth（既定のブラウザでログイン）と Gmail API（読み取り専用）を使います。最初に一度だけ、次の準備が必要です。

1. [Google Cloud Console](https://console.cloud.google.com/) で新しいプロジェクトを作る（個人の Google アカウントで可）
2. 「APIとサービス → ライブラリ」で **Gmail API** を有効にする
3. 「OAuth 同意画面」を作る（種類：外部、公開ステータス：テスト）。**テストユーザーに大学のメールアドレスを追加**する
4. 「認証情報 → 認証情報を作成 → OAuth クライアント ID」で、種類 **デスクトップアプリ** を作る
5. キャンパスハブの「設定 → メール（Gmail）」に、クライアントIDとシークレットを入れて保存
6. 「Googleでログイン」→ ブラウザで大学のアカウントを選び、読み取りを許可する

- 大学の管理者が外部アプリを制限している場合は、手順6で「アクセスがブロックされました」と出ます。その場合は大学（情報センター等）に確認してください。
- 取得するのは件名・差出人・日時・冒頭の一部（snippet）だけで、保存しません。リフレッシュトークンとシークレットはキーチェーンに入ります。
- 仕分けは決まった言葉と日付の書き方で行い、各メールに「仕分けの理由」を表示します（`Sources/CampusHub/Services/MailClassifier.swift`）。

## うまく読み込めないとき

「設定 → 接続の診断」か `~/Library/Logs/CampusHub/diagnostics.log` に、どこで止まったか（開いたページのホスト名・パス、件数、エラー）が出ます。ID・パスワード・メールや授業の内容は書きません。

## インストーラーを作る

| | コマンド | できるもの |
| --- | --- | --- |
| Mac | `./scripts/build-pkg.sh` | `CampusHub-0.2.0.pkg`（リポジトリ直下。/Applications/キャンパスハブ.app に入る） |
| Windows | `./scripts/build-windows.sh` | `CampusHub-Setup-0.2.0.exe`（リポジトリ直下。Mac上でも Windows 上（`cd windows && npm run dist:win`）でも作れる。Node.js が必要） |

- どちらも開発者署名はしていません。Mac は初回「右クリック → 開く」、Windows は SmartScreen の「詳細情報 → 実行」が必要です。
- Windows版は `./scripts/build-windows.sh --run` で Mac 上でも画面を確認できます（`--test` はテストだけ）。
- Windows 上で作るとき（Node.js の LTS 版を入れておく）:
  ```bat
  cd windows
  npm install --save-dev --save-exact electron electron-builder
  npm test
  npm run dist:win
  ```
  → `dist\windows\CampusHub-Setup-0.2.0.exe`。`npm start` でインストールせずに起動できます。

## Windows版（`windows/`）

Mac版と同じ画面・同じ読み取り方（自動ログイン → 画面に出さないブラウザで読み取り、Gmail API）を Electron で作ったものです。

| Mac版 | Windows版 |
| --- | --- |
| キーチェーン | Windows の DPAPI で暗号化して `%APPDATA%\キャンパスハブ\secrets.json` に保存（Electron safeStorage） |
| UserDefaults | `%APPDATA%\キャンパスハブ\settings.json` |
| `~/Library/Logs/CampusHub/diagnostics.log` | `%APPDATA%\キャンパスハブ\logs\diagnostics.log` |
| WKWebView（`.defaultClient` で自動入力） | Chromium（隔離された実行環境で自動入力。Cookie は `persist:campushub` に保存） |
| 締切の通知（予約） | アプリを起動している間だけ、Windows の通知センターに出す |

- 起動時に開く画面：`CampusHub.exe --section calendar`
- 構成：`src/main/`（ログイン・読み取り・Gmail・保存）、`src/renderer/`（画面）、`test/`（`npm test`）
- 大学ごとの初期値は `windows/src/main/config.js`（Mac版の `DefaultConfig.swift` と同じ値。片方を変えたらもう片方も）
- ページ内で動かすスクリプトは `windows/src/main/scripts.js`（Mac版の `Scripts.swift` と同じ内容）

## 起動方法

```sh
./scripts/build-app.sh --install                     # /Applications/キャンパスハブ.app に入れる（ドックに固定するならこれ）
open -a キャンパスハブ --args --section calendar       # 指定の画面で開く（home / calendar / moodle / campusSquare / mail / settings）
swift run                                            # 開発用
swift test                                           # テスト
```

初回は「設定 → ログイン情報」で学籍番号とパスワードを保存し、「更新」を押してください。
画面だけ確認したいときは「設定 → サンプルデータで表示を確認する」。

## 設定する場所

- 大学ごとの初期値（URL・ログインフォームのセレクタ）：`Sources/CampusHub/Config/DefaultConfig.swift`
- 自分のMacだけで変える：アプリの「設定」（UserDefaults に保存）
- ID・パスワード：アプリの「設定 → ログイン情報」（キーチェーン）
- 配色：`Sources/CampusHub/Theme/Theme.swift`（鈴の `appearance.palette` と同じ値）
- 画像：`Sources/CampusHub/Resources/Appearance/`（鈴の `face_*.jpg`・`hero_*.jpg`）
- アプリアイコン：`icon/campus-hub.svg` を差し替えて `./scripts/make-icon.sh && ./scripts/build-app.sh --install`
  （ドックの表示が古いままなら `rm "$(getconf DARWIN_USER_CACHE_DIR)com.apple.dock.iconcache"; killall Dock`）

## ディレクトリ

```
Sources/CampusHub/
  App.swift                 起動・サイドバー・全体の配置
  Config/DefaultConfig.swift 大学ごとの初期値
  Models/                   設定・データ型・URL検証
  Services/                 キーチェーン、通知、サンプルデータ
  Store/AppStore.swift      状態管理・読み込みの流れ
  Theme/Theme.swift         鈴テーマ（色・カード・顔・背景）
  Web/                      自動ログイン、裏で動くWebView、アプリ内ブラウザ、ページ内スクリプト
  Views/                    各画面
Tests/CampusHubTests/       URL検証・Moodle応答の解析・時間割などのテスト
```
