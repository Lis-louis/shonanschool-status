# CLAUDE.md

キャンパスハブ：Mac 版（Swift / `Sources/CampusHub`）と Windows 版（Electron / `windows/`）の2本立て。
片方を直したら、もう片方にも同じ問題がないか確認すること。

リポジトリ：https://github.com/Lis-louis/shonanschool-status（旧名 my-school-status。アプリの表示名「キャンパスハブ」は変えていない）

## Windows 版の配布と自動更新

- 配布は GitHub Releases。`windows/package.json` の `version` を上げて main に push すると、
  `.github/workflows/release-windows.yml` がテスト → ビルド → Release（タグ `v<version>`）公開まで行う。
  version を上げない push では何もしない。exe はリポジトリに入れない（`.gitignore` 済み）。
  アップロードは `gh release` で行い、latest.yml を最後に上げる。途中で失敗したら Actions の Run workflow で足りないファイルを上げ直せる。
  （v0.3.0 は electron-builder の `--publish always` でのアップロードに失敗し、blockmap だけの Release が残っている。0.3.1 から今の方式）
- アプリ側は `windows/src/main/updater.js`（electron-updater）。配布版でだけ、起動10秒後と3時間ごとに確認 →
  裏でダウンロード → 画面上部に「再起動して更新」（`app.js` の `updateBanner`）。押さなくても終了時に入れ替わる。
- 0.3.0 で導入。0.2.0 以前は自動更新がないので、利用者は一度だけ手で入れ直す必要がある。

## Mac 版で後でやること

### 自動更新（Windows 版は 0.3.0 で実装済み、Mac 版は未着手）
- Windows 版と同じく「新しい版があれば知らせて、ボタンで更新できる」ようにする。
- 候補：[Sparkle](https://sparkle-project.org/)（SwiftPM で入る。appcast.xml と EdDSA 署名が必要）。
  署名・公証していない .app だと更新後に Gatekeeper に止められる可能性があるので、そこも確認する。
- 配布の流れも Windows 版に合わせる：version を上げて push → GitHub Actions（macos ランナー）で
  `scripts/build-pkg.sh` 相当をビルドし、同じ Release に Mac 用ファイルと appcast を追加する。
  Windows 用ワークフローは「その版の Release が既にあればスキップ」するので、Mac 用を足すときは同じ Release に相乗りできるよう調整すること。
- 設定画面の「アプリ」カード（バージョン表示・アップデートを確認）も Mac 版に追加する。
- 終わったら README（日本語・英語）の「Mac 版の自動アップデートは準備中」「開発状況」の行を直すこと。

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

### 2026-11-24：提出済みの課題についての Moodle 通知を一覧から外す
- 発端：Moodle の「通知」に「提出期限 …: 第7回課題」など、もう提出した課題の通知が並んでいた。
- Windows 版で修正・実データで確認済み：通知のリンク先が `/mod/*/view.php?id=…` なら、締切と同じ
  `moodleSubmissionStatus` でページを確かめ、提出済み・回答済みなら「提出済み・回答済みの課題の通知（N件）」に折りたたむ
  （ホームの通知3件からも外す）。小テストの「もう一度受験する」も受験済みとして扱うよう判定語に追加。
- Mac 版に同じ変更を入れた（**未ビルド・未確認**）：
  - `Models/Domain.swift`：`MoodleNotice.status`・`linksToActivity`
  - `Store/AppStore.swift`：`checkSubmissions` で通知のリンク先も確認（`defer` で控えメールの結果も通知に反映）
  - `Views/ServicePages.swift`：通知カードを未提出／提出済みに分け、`noticeRow` を追加
  - `Views/HomeView.swift`：提出済みの通知を出さない（`activeNotices` を追加）
  - `Web/Scripts.swift`：判定語に「もう一度受験する」「Re-attempt quiz」
- 確認手順：Moodle 画面の「通知」で、提出済みの課題の「提出期限 …」が下の折りたたみに入ること。診断ログに
  「通知のうち課題などへのリンク N件: 提出済み M件…」が出ること。

### 2026-11-24：もう受けていないコースを「コース（教材）」から外す・戻す
- Windows 版で実装・確認済み（0.3.1）：各コースの右に「非表示」、外したものは「非表示にしたコース（N件）」に入り「戻す」で戻る。
  保存先は settings.json の `hiddenCourses`（コース ID の配列）。
- Mac 版に同じ変更を入れた（**未ビルド・未確認**）：
  - `Store/AppStore.swift`：`hiddenCourseIDs`（UserDefaults `hiddenCourseIDs.v1`）と `setCourseHidden(_:_:)`
  - `Views/ServicePages.swift`：コース一覧を表示中／非表示に分け、`courseRow(_:hidden:)` を追加（目のアイコンのボタン）
- 確認手順：Moodle 画面の「コース（教材）」で「非表示」を押す → 下の「非表示にしたコース」に移る →「戻す」で元に戻る。
  アプリを再起動しても非表示が保たれること。

### 2026-11-24：時間割のコマを押すと、対応する Moodle のコースを開く
- Windows 版で実装・実データで確認済み（0.3.2）：`logic.js` の `Timetable.moodleCourse`。
  科目コード（時間割 `B31L07K1` ⇔ Moodle 短縮名 `…-B31L07K101`）→ 科目名（【担当】・[曜限]・学期・全角半角を無視）の順に照合し、
  同名が複数なら曜限と今の学期で選ぶ。実際の時間割16コマすべてが正しいコースに対応した。
  表記ゆれ（「心理をよむ」⇔「心理を読む」、カタカナ⇔ひらがな）は2文字組の似ている度合いで拾う。英数字が違う（基礎1⇔基礎2、実習A⇔実習B）ものは結び付けない。
  対応するコースが無いときは「Moodleで探す」＝ `course/search.php?search=科目名` を開く（他の学生の時間割でも必ず押せるように）。
  正しいコースを抜いた一覧で試し、16コマとも別のコースに誤って結び付かないことを確認済み。
- Mac 版に同じ変更を入れた：
  - `Models/Domain.swift`：`Timetable.courseKey`・`Timetable.moodleCourse(in:text:day:period:)`
    → **Windows の swiftc でこのファイルだけコンパイル・実行し、Windows 版と同じ結果になることは確認済み**
  - `Views/Components.swift`：`ClassCell` に `day` を追加し、対応コースがあればボタンにして「Moodle」ラベルを出す（**未ビルド・未確認**。`@Environment(AppStore.self)` を使うようになった）
  - `Views/HomeView.swift`・`Views/ServicePages.swift`：`ClassCell(..., day:)` を渡す
  - `Tests/CampusHubTests/CampusHubTests.swift`：`TimetableCourseTests` を追加（未実行）
- 確認手順：ホームの「今日の授業」と Campus Square の「時間割」で、コマの右に「Moodle」が出て、押すとそのコースが開くこと。

### 2026-11-24：ホームの「やること」を今週の分だけにする
- Windows 版で実装・実データで確認済み（0.3.3）：`logic.js` の `todos(S, …, { thisWeek: true })`（ホームだけ。Moodle 画面の「課題・締切」は従来どおり全部）。
  - 受付開始前（notOpenYet）は出さない。「あと○日」（切り捨て）が 8 以上の Moodle の締切は出さない（メール由来は対象外）。
  - 例外（早めに出ている課題）：締切が先でも、もう提出できる（notSubmitted / form）か、Campus Square の休講（休講ページの表・ポータルの「休講」を含む行）に
    今日〜締切の間のその科目の休講があれば出す。理由欄に「○月○日が休講なので早めに出ている課題です」などと出る。
  - 隠した件数は「あと8日以上先・受付開始前の課題 N件は…」として出し、押すと Moodle 画面へ。
  - 実データ：17件 → 3件（隠した14件はすべて受付開始前）。
  - **休講の読み取りを修正（0.3.5）**：休講補講参照ページの初期表示はコマ形式（1週間分のマス目・入れ子の表）で、従来の largestTable では
    表示設定のフォームしか読めていなかった（常に0行）。`scripts.js` の `campusCancellations` で、ページのフォームを
    「一覧形式・変更情報のみ・履修中のみ・今日から5週間」で送って `table.normal` を読む（行の class：kyuko-kyuko=休講 / kyuko-hoko=補講 / kyuko-kyoshitsu=教室変更）。
    列は 日付・時限・時間割コード・科目・区分・教室。休講補講参照以外のページが設定されていれば従来の largestTable。
    実データで「12月19日(土) 1限 社会連携講座 補講」を読めた（全科目・10月〜1月では約100件、休講・補講の両方の class を確認）。
    締切の科目との照合は科目名に加えて時間割コード（Moodle 短縮名 …-B31N04K101 → B31N04K1）でも行う。
    Mac 版も同じ（`Web/Scripts.swift` の `campusCancellations` は Windows 版と同一の文字列であることを確認済み、`AppStore.fetchCampus`・`ThisWeek.courseCode`）。
  - **表示の修正（0.3.6）**：題名の「（今日から5週間）」と「教室」の列から「5週間その教室」と読めてしまうため、題名は「休講・補講・教室変更」、
    列名は「この日の教室」にし、「どれも書かれている日の1回だけで、ほかの週はいつもどおり」と説明を付けた。各行は「日付 時限」＋区分のチップ＋
    「この日だけ ○○ で授業（ほかの週はいつもの教室）」などの文。ホームのお知らせも「12月19日(土) 1限 科目 → 補講（この日だけ・教室）」。
    書き方は `logic.js` の `ChangeList`／Mac `Domain.swift` の `enum ChangeList`（swiftc で確認済み）。Mac の `ServicePages.swift`・`HomeView.swift` は**未ビルド**。
- Mac 版に同じ変更を入れた：
  - `Models/Domain.swift`：`enum ThisWeek`（isLater・guessDate・cancellations・cancelledBefore）→ **swiftc でコンパイル・実行し Windows 版と同じ結果を確認済み**
  - `Store/AppStore.swift`：`todos(…, thisWeek:)`（**未ビルド**）
  - `Views/MailView.swift`：`TodoCard(thisWeek:)` と隠した件数の案内、`Views/HomeView.swift`：`TodoCard(limit: 6, thisWeek: true)`（**未ビルド**）
  - `Tests/CampusHubTests/CampusHubTests.swift`：`ThisWeekTests`（未実行）
- 確認手順：ホームの「やること」に受付開始前・あと8日以上先が出ず、下に「…N件は、Moodle の『課題・締切』で見られます」が出ること。
