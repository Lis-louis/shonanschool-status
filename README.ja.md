<p align="center">
  <img src="packaging/AppIcon-1024.png" width="128" alt="キャンパスハブ アイコン">
</p>

<h1 align="center">キャンパスハブ — 湘南工科大学の Moodle・Campus Square・大学メールを1つに</h1>

<p align="center">
  <a href="README.md">English</a> | <b>日本語</b>
</p>

<p align="center">
  Moodle の課題・締切、Campus Square の時間割・休講、大学メールを、1つの画面にまとめる Mac / Windows アプリ。<br>
  見た目は「鈴」と同じ配色・部品で、鈴の画像を使っています。
</p>

---

## 特徴

- **1つの画面にまとめる**：今日の授業、やること（Moodle の未完了課題＋メールの要対応）、お知らせ、大学メールをホーム画面に表示
- **カレンダー**：毎週の時間割・Moodle の予定・締切・メールで見つけた期限を、月表示で日ごとに表示
- **自動ログイン**：保存した ID・パスワードを公式のログインページに入力するだけ。ログイン画面を自作・模倣しない
- **メールの自動仕分け**：Gmail を読み取り専用で取得し「要対応・締切／休講・授業変更／試験・レポート／Moodle 通知／行事／お知らせ」に仕分け。督促・未提出などの語や期限の日付も検出し、仕分けの理由も表示
- **アプリ内ブラウザ**：教材のダウンロード、課題ファイルのアップロードに対応。大学のドメイン外のリンクは既定のブラウザで開く
- **それぞれの OS 向け**：Mac 版は SwiftUI、Windows 版は Electron（`windows/`）。画面と読み取り方は同じ
- **安全第一**：パスワードは OS の安全な保存場所（キーチェーン／DPAPI）だけに保存。読み取った内容はファイルに残さない
- **昼／夜のテーマ**：OS の外観（ライト／ダーク）に合わせて鈴の画像と配色が切り替わる

## インストール

[Releases（最新版）](https://github.com/Lis-louis/shonanschool-status/releases/latest) から、お使いの OS のインストーラーをダウンロードしてください。

| OS | ファイル | 手順 |
|---|---|---|
| Windows | [Releases](https://github.com/Lis-louis/shonanschool-status/releases/latest) の `CampusHub-Setup-<バージョン>.exe` | 実行してセットアップの案内に従う（インストール先 → インストール）。自分のユーザー用にインストールするので管理者権限は不要。デスクトップとスタートメニューにショートカットができます |
| macOS | [Releases](https://github.com/Lis-louis/shonanschool-status/releases/latest) の `CampusHub-<バージョン>.pkg` | 開いてインストーラーの案内に従う（続ける → インストール。Mac のパスワードを聞かれます）。「アプリケーション」に キャンパスハブ.app が入り、終わると自動で開きます。Apple シリコン・Intel の両方で動きます |

アンインストール：Windows は **設定 → アプリ → インストールされているアプリ → キャンパスハブ → アンインストール**。macOS は「アプリケーション」の キャンパスハブ をゴミ箱へ。

> インストーラーはまだコード署名していないため、初回に OS の警告が出ることがあります。
> Windows：SmartScreen が出たときは **詳細情報 → 実行** をクリック。
> macOS：「開けません」と出たときは、**システム設定 → プライバシーとセキュリティ** の下のほうにある「このまま開く」をクリックしてから、もう一度 .pkg を開いてください（macOS 14 では「右クリック → 開く」でも開けます）。インストールしたアプリはそのまま起動できます。

### アップデート

#### Windows 版

Windows 版（0.3.0 以降）は自動でアップデートします。

1. 起動したとき（とその後 3 時間ごと）に、[Releases](https://github.com/Lis-louis/shonanschool-status/releases) に新しいバージョンがないか確認します
2. あれば裏でダウンロードし、画面の上に「**新しいバージョン x.y.z の準備ができました［再起動して更新］**」が出ます
3. **再起動して更新** を押すと、数秒でアプリが起動し直して新しいバージョンになります。押さずに終了しても、終了するときに更新されます

**設定 → アプリ → アップデートを確認**（またはメニューの **ファイル → アプリのアップデートを確認**）で、すぐに確認することもできます。

> 0.2.0 以前には自動アップデートがないため、一度だけ Releases から最新のインストーラーを入れ直してください（設定・ログイン情報はそのまま引き継がれます）。

#### Mac 版

Mac 版（0.3.6 以降）も、新しいバージョンを自動で見つけてダウンロードします。

1. 起動したとき（とその後 3 時間ごと）に、[Releases](https://github.com/Lis-louis/shonanschool-status/releases) に新しいバージョンの `.pkg` がないか確認します
2. あれば裏でダウンロードし（GitHub に載っている SHA-256 と一致するか確かめます）、画面の上に「**新しいバージョン x.y.z の準備ができました［更新する］**」が出ます
3. **更新する** を押すとインストーラーが開き、キャンパスハブは一度閉じます。案内に沿ってインストールすると（Mac のパスワードを聞かれます）、終わったときに新しいバージョンで開き直します

**設定 → アプリ → アップデートを確認**（またはメニューの **キャンパスハブ → アップデートを確認…**）で、すぐに確認することもできます。

> Windows 版と違い、終了するときに黙って入れ替えることはしません（「アプリケーション」フォルダへの書き込みに Mac のパスワードが必要なため）。
> 0.3.5 以前（自分でビルドしたもの）には自動アップデートがないため、一度だけ Releases から `.pkg` を入れてください（設定・ログイン情報はそのまま引き継がれます）。

## 動作環境

- Windows 10 / 11 の 64 ビット版（x64）
- macOS 14 Sonoma 以降
- ビルドする場合：Node.js の LTS 版（Windows 版）、Xcode 16 以降 / Swift 6 ツールチェーン（Mac 版）

## はじめての設定

1. **設定 → ログイン情報** で学籍番号とパスワードを保存し、**更新** を押す
2. 大学メールも見るときは、下の「[メール（Gmail）の連携手順](#メールgmailの連携手順)」で Google との連携を設定する
3. 画面だけ確認したいときは **設定 → サンプルデータで表示を確認する**

## 画面

| 画面 | 内容 |
|---|---|
| ホーム | 今日の授業（押すと対応する Moodle のコースを開く。見つからないときは Moodle で科目名を検索）／**やること（まだできていないこと）**＝ Moodle の未完了課題＋メールの要対応（授業は週1回なので「あと7日」まで。受付開始前は出さない。来週が休講などで早めに出ている課題は出す）／お知らせ／学校から届いているメール |
| カレンダー | 月表示。毎週の時間割・Moodle の予定・締切・メールで見つけた期限を日ごとに表示 |
| Moodle | **まとめ**：課題・締切、通知（提出済みの課題の通知は折りたたむ）、コース（進捗つき。もう受けていないコースは「非表示」で外せて、「非表示にしたコース」から戻せる）。**ブラウザ**：公式サイトをアプリ内で表示 |
| Campus Square | **まとめ**：曜日別の時間割（押すと対応する Moodle のコースを開く。見つからないときは Moodle で科目名を検索）、休講・補講の表、ポータルの各お知らせ。**ブラウザ**：公式サイト |
| メール | Gmail を読み取り専用で取得し、内容ごとに自動で仕分け |
| 設定 | ログイン情報、Gmail 連携、自動ログイン、URL、表示項目、通知、サンプル表示、アプリのバージョンとアップデート確認、**接続の診断** |

### ショートカット

| 操作 | 内容 |
|---|---|
| Ctrl+R（Windows）／⌘R（Mac） | 更新 |
| Ctrl+1〜6（Windows）／⌘1〜6（Mac） | ホーム・カレンダー・Moodle・Campus Square・メール・設定 に切り替え |
| `CampusHub.exe --section calendar`（Windows）<br>`open -a キャンパスハブ --args --section calendar`（Mac） | 指定の画面で開く（`home` / `calendar` / `moodle` / `campusSquare` / `mail` / `settings`） |

## しくみ

1. **自動ログイン**：保存した ID・パスワードを、公式ログインページ（Moodle：`#username` / `#password`、Campus Square：`#userNameInput` / `#passwordInput`）の入力欄に入れてボタンを押します。
2. **まとめ表示**：画面に出さないブラウザでログイン後のページを開き、
   - Moodle：Moodle 自身のダッシュボードが使う AJAX サービス（`core_course_get_enrolled_courses_by_timeline_classification`、`core_calendar_get_action_events_by_timesort`、`message_popup_get_popup_notifications`）をログイン中のページから呼びます。
   - Campus Square：ポータルの各枠の文字、曜日が並ぶ表（時間割）、休講ページの表を読み取ります。
3. **アプリ内ブラウザ**：教材のダウンロード（ダウンロードフォルダ）、課題ファイルのアップロード、`_blank` リンクに対応。大学のドメイン外のリンクは既定のブラウザで開きます。

## 安全とプライバシー

- ID・パスワードは OS の安全な保存場所にだけ保存します。コード・設定ファイル・ログには出しません。
  - Mac：キーチェーン（`WhenUnlockedThisDeviceOnly`：iCloud 同期・移行なし）
  - Windows：DPAPI で暗号化して `%APPDATA%\キャンパスハブ\secrets.json` に保存（Electron の safeStorage）
- 自動入力は「https で、設定したログインホストと完全一致するページ」だけ。ページのスクリプトから隔離された環境で入力します。
- 自動でボタンを押すのは 30 秒に 1 回まで（失敗を繰り返してアカウントがロックされないように）。
- 読み取った内容はメモリ上だけで、ファイルに保存しません。Cookie はこのアプリ専用の保存場所に残ります（**設定 → ログイン状態を消去** で削除）。
- 更新は手動（起動時と「更新」ボタン）だけで、大学のサーバーに負荷をかける定期取得はしません。
- アプリのアップデート確認は GitHub（github.com・api.github.com と、そのダウンロード用のホスト）にだけ接続し、送るのはふつうのダウンロードと同じ情報だけです（ID・パスワードや読み取った内容は送りません）。

> 自動ログインや画面の読み取りが大学の利用規約・情報ポリシーで認められているかは、各自で確認してください。

## メール（Gmail）の連携手順

Google は、アプリに埋め込んだブラウザでのログインを認めていないため、Google 公式の OAuth（既定のブラウザでログイン）と Gmail API（読み取り専用）を使います。最初に一度だけ、次の準備が必要です。

1. [Google Cloud Console](https://console.cloud.google.com/) で新しいプロジェクトを作る（個人の Google アカウントで可）
2. 「API とサービス → ライブラリ」で **Gmail API** を有効にする
3. 「OAuth 同意画面」を作る（種類：外部、公開ステータス：テスト）。**テストユーザーに大学のメールアドレスを追加**する
4. 「認証情報 → 認証情報を作成 → OAuth クライアント ID」で、種類 **デスクトップアプリ** を作る
5. キャンパスハブの **設定 → メール（Gmail）** に、クライアント ID とシークレットを入れて保存
6. **Google でログイン** → ブラウザで大学のアカウントを選び、読み取りを許可する

- 大学の管理者が外部アプリを制限している場合は、手順 6 で「アクセスがブロックされました」と出ます。その場合は大学（情報センター等）に確認してください。
- 取得するのは件名・差出人・日時・冒頭の一部（snippet）だけで、保存しません。リフレッシュトークンとシークレットは ID・パスワードと同じ安全な保存場所に入ります。
- 仕分けは決まった言葉と日付の書き方で行います（Mac 版：`Sources/CampusHub/Services/MailClassifier.swift`）。

## ビルドと起動

### Windows（`windows/`）

[Node.js](https://nodejs.org/) の LTS 版が必要です。

```bat
cd windows
npm install
npm test             & rem 単体テスト
npm start            & rem インストールせずに起動
npm run dist:win     & rem インストーラーを作成
```

`npm run dist:win` で `dist\windows\CampusHub-Setup-<バージョン>.exe` ができます（自分の PC で試す用。配布は下の「[新しいバージョンの配り方](#新しいバージョンの配り方windows-版mac-版)」で自動で行います）。

### macOS

```sh
git clone https://github.com/Lis-louis/shonanschool-status.git
cd shonanschool-status

./scripts/build-app.sh --install   # /Applications/キャンパスハブ.app に入れる（Dock に固定するならこれ）
swift run                          # 開発用に起動
swift test                         # 単体テスト
```

### インストーラーの作成

| インストーラー | コマンド | できるもの |
|---|---|---|
| Windows `.exe` | `cd windows && npm run dist:win`（Windows で）<br>`./scripts/build-windows.sh`（Mac で） | `dist/windows/CampusHub-Setup-<バージョン>.exe` |
| macOS `.pkg` | `./scripts/build-pkg.sh`（Mac で） | `dist/CampusHub-<バージョン>.pkg`（/Applications/キャンパスハブ.app に入る。Apple シリコン・Intel 両対応） |

- Mac の `.pkg` は Windows では作れません。Windows の `.exe` は Mac 上でも作れます（`./scripts/build-windows.sh --run` で画面の確認、`--test` でテストだけ）。

### 新しいバージョンの配り方（Windows 版・Mac 版）

バージョンは Windows 版と Mac 版で共通です（`windows/package.json` の `"version"`。Mac 版の `scripts/build-app.sh`・`build-pkg.sh` もここから読みます）。

1. 直したいところを直す
2. `windows/package.json` の `"version"` を上げる（例：`0.3.6` → `0.3.7`）
3. main に push する

あとは GitHub Actions が、テスト → インストーラーのビルド → [Releases](https://github.com/Lis-louis/shonanschool-status/releases) への公開（タグ `v<バージョン>`）まで自動で行います。Windows 版と Mac 版は同じ Release に入ります。

| | ワークフロー | Release に上がるもの |
|---|---|---|
| Windows 版 | `.github/workflows/release-windows.yml`（Windows で動く） | `CampusHub-Setup-<バージョン>.exe`・`.exe.blockmap`・`latest.yml` |
| Mac 版 | `.github/workflows/release-mac.yml`（macOS で動く） | `CampusHub-<バージョン>.pkg` |

公開されると、インストール済みのアプリに「再起動して更新」（Windows）／「更新する」（Mac）が出ます。

- `version` を上げずに push したときは何もしません（同じバージョンの Release にファイルがそろっているため）。
- 進み具合は GitHub の **Actions** タブで見られます。手動で動かすときは Actions → 「Windows 版をリリース」／「Mac 版をリリース」→ **Run workflow**。途中で失敗したときも、これで足りないファイルを上げ直せます。
- Windows 版は `latest.yml`、Mac 版は `CampusHub-<バージョン>.pkg`（と GitHub が付ける SHA-256）を見て新しいバージョンに気づくので、消さないでください。

## うまく読み込めないとき

**設定 → 接続の診断** か、次の診断ログに、どこで止まったか（開いたページのホスト名・パス、件数、エラー）が出ます。ID・パスワード・メールや授業の内容は書きません。

- Mac：`~/Library/Logs/CampusHub/diagnostics.log`（メニューの **表示 → 診断ログのフォルダを開く**）
- Windows：`%APPDATA%\キャンパスハブ\logs\diagnostics.log`（メニューの **ファイル → 診断ログのフォルダを開く**）

## 設定する場所

| 項目 | 場所 |
|---|---|
| 大学ごとの初期値（URL・ログインフォームのセレクタ） | Mac：`Sources/CampusHub/Config/DefaultConfig.swift`<br>Windows：`windows/src/main/config.js`（同じ値。片方を変えたらもう片方も） |
| 自分のパソコンだけで変える | アプリの「設定」（Mac：UserDefaults、Windows：`%APPDATA%\キャンパスハブ\settings.json`） |
| ID・パスワード | アプリの **設定 → ログイン情報** |
| ページ内で動かすスクリプト | Mac：`Sources/CampusHub/Web/Scripts.swift`、Windows：`windows/src/main/scripts.js`（同じ内容） |
| 配色 | `Sources/CampusHub/Theme/Theme.swift`（鈴の `appearance.palette` と同じ値） |
| 画像 | `Sources/CampusHub/Resources/Appearance/`（鈴の `face_*.jpg`・`hero_*.jpg`。Windows 版も同じファイルを使う） |
| アプリアイコン | `icon/campus-hub.svg` を差し替えて `./scripts/make-icon.sh && ./scripts/build-app.sh --install` |

## プロジェクト構成

```
Sources/CampusHub/        Mac 版（SwiftUI）
├─ App.swift              起動・サイドバー・全体の配置
├─ Config/                大学ごとの初期値
├─ Models/                設定・データ型・URL 検証
├─ Services/              キーチェーン、通知、Gmail、メールの仕分け、サンプルデータ
├─ Store/                 状態管理・読み込みの流れ
├─ Theme/                 鈴テーマ（色・カード・顔・背景）
├─ Web/                   自動ログイン、裏で動く WebView、アプリ内ブラウザ、ページ内スクリプト
├─ Views/                 各画面
└─ Resources/Appearance/  鈴の画像
Tests/CampusHubTests/     URL 検証・Moodle 応答の解析・時間割などのテスト
windows/                  Windows 版（Electron）
├─ src/main/              ログイン・読み取り・Gmail・保存（メインプロセス）
├─ src/renderer/          画面
├─ src/preload.js         画面とメインプロセスの橋渡し
└─ test/                  単体テスト（npm test）
icon/                     アプリアイコンの元画像（SVG）
packaging/                Mac 用のアイコン（.icns・PNG）
scripts/                  .app / .pkg / Windows 版 .exe のビルドスクリプト
.github/workflows/        Windows 版・Mac 版を Releases に公開する GitHub Actions
```

## 開発状況

| 項目 | 状態 |
|---|---|
| Mac 版（SwiftUI） | 完成（インストーラー・自動アップデートあり） |
| Windows 版（Electron） | 完成（インストーラー・自動アップデートあり） |
| Moodle・Campus Square の自動ログインと読み取り | 完成 |
| Gmail の連携と自動仕分け | 完成 |
| Mac 版インストーラー（.pkg）の配布 | 完成（Releases。Apple シリコン・Intel 両対応） |
| Mac 版の自動アップデート | 完成（0.3.6 以降。インストーラーを開いて更新） |

### 未確定・推定の値

| 項目 | 値 | 状態 |
|---|---|---|
| Moodle | `https://moodle2026.shonan-it.ac.jp` | 確認済み（ログインフォームも確認） |
| Campus Square | `https://portal.shonan-it.ac.jp/campusweb/` | 確認済み（ログインフォームも確認） |
| 時間割 | `campussquare.do?_flowId=RSW0001000-flow` | 確認済み（ポータルのメニュー「履修登録・登録状況照会」） |
| 休講・補講 | `_flowId=KHW0001100-flow` | 確認済み（ページ名「休講補講参照」。一覧形式・今日から5週間で読み取る） |
| 成績 / シラバス | `SIW0001300-flow` / `SYW0001000-flow` | **推定** |
| 出席管理 | `https://syusseki.shonan-it.ac.jp/campusaa/` | ログインページのリンクより |
| 大学メール | Google Workspace（Gmail） | DNS（MX レコード）で確認 |

推定のページが違う場合：Campus Square の「ブラウザ」で正しいページを開き、右上の「…」→「このページを『時間割』に設定」。

### 既知の制限

- 成績、シラバスのページ URL は推定のため、大学側の画面と違うことがある（上記の方法で直せる）
- Windows 版の締切の通知は、アプリを起動している間だけ Windows の通知センターに出る
- 大学がサイトの作りを変えると、読み取りがうまくいかなくなることがある（**設定 → 接続の診断** で確認）

## ライセンス

このリポジトリは、プログラムとキャラクターでライセンスが分かれています。

| 対象 | ライセンス |
|---|---|
| プログラム（`Sources/`、`Tests/`、`windows/`、`scripts/` など） | [MIT License](LICENSE) |
| キャラクター「鈴」（名前・デザイン・`Sources/CampusHub/Resources/Appearance/` の画像・鈴の絵が入ったアイコン） | [キャラクター利用ガイドライン](CHARACTER_GUIDELINES.md) |

鈴のファンアートは、クレジット表記をすれば非営利で自由に描いて公開できます。
次のことは禁止しています。

- 公序良俗に反する使用
- 無断転載・再配布
- 商用利用
- AI の学習への利用

改造版のアプリを配布するときは、鈴の画像とアイコンをすべて削除してください（公式版ではなくなるため）。

```
キャラクター「鈴」© Lis-louis
```
