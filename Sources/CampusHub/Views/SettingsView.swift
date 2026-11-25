import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var confirmReset = false
    @State private var confirmClear = false

    var body: some View {
        @Bindable var store = store
        Page(title: "設定", subtitle: "ログイン情報・URL・表示") {
            Card(title: "ログイン情報", symbol: "person.badge.key") {
                CredentialEditor(service: .moodle, title: store.prefs.sameCredentials ? "Moodle / Campus Square 共通" : "Moodle")
                Toggle("Campus Squareも同じID・パスワードを使う", isOn: $store.prefs.sameCredentials)
                if !store.prefs.sameCredentials {
                    Divider()
                    CredentialEditor(service: .campus, title: "Campus Square")
                }
                Text("""
                ID・パスワードはこのMacのキーチェーンにだけ保存されます（iCloud同期なし）。\
                使うのは、設定した大学の公式ログインページ（\(store.config.trustedDomain)）の入力欄に入れるときだけです。
                """)
                .font(.caption).foregroundStyle(p.subtle).fixedSize(horizontal: false, vertical: true)
            }

            GmailSettings()

            Card(title: "ログインの動き", symbol: "wand.and.stars") {
                Toggle("自動でログインする", isOn: $store.prefs.autoLogin)
                Toggle("大学のページに鈴テーマの配色を重ねる（再起動で反映）", isOn: $store.prefs.themeOfficialPages)
                Button("ログイン状態を消去（ログアウト）", role: .destructive) { confirmClear = true }
                    .buttonStyle(PrimaryButtonStyle(destructive: true))
            }

            Card(title: "大学・URL", symbol: "building.columns") {
                Field(title: "大学名", text: $store.config.universityName, isURL: false)
                Field(title: "大学のドメイン（自動入力・アプリ内表示を許可）", text: $store.config.trustedDomain, isURL: false)
                Field(title: "Moodle", text: $store.config.moodleBaseURL)
                Field(title: "Campus Square ログイン", text: $store.config.campusSquare.login)
                Field(title: "Campus Square ポータル", text: $store.config.campusSquare.portal)
                Field(title: "時間割（推定）", text: $store.config.campusSquare.timetable)
                Field(title: "休講・補講", text: $store.config.campusSquare.cancellations)
                Field(title: "成績（推定）", text: $store.config.campusSquare.grades)
                Field(title: "シラバス（推定）", text: $store.config.campusSquare.syllabus)
                Field(title: "出席管理", text: $store.config.campusSquare.attendance)
                Text("「推定」のページが違う場合は、Campus Squareの「ブラウザ」で正しいページを開き、右上の「…」から設定できます。")
                    .font(.caption).foregroundStyle(p.subtle)
                Button("URLを初期値に戻す") { confirmReset = true }.buttonStyle(SoftButtonStyle())
            }

            Card(title: "ホームに表示するもの", symbol: "square.grid.2x2") {
                Toggle("今日の授業", isOn: $store.prefs.showTodayClasses)
                Toggle("課題・締切", isOn: $store.prefs.showDeadlines)
                Toggle("お知らせ", isOn: $store.prefs.showNotices)
                Toggle("メール", isOn: $store.prefs.showMail)
                Picker("締切の表示期間", selection: $store.prefs.deadlineWindowDays) {
                    Text("7日").tag(7); Text("14日").tag(14); Text("30日").tag(30)
                }
            }

            Card(title: "通知", symbol: "bell.badge") {
                Toggle("締切の通知", isOn: $store.prefs.notificationsEnabled).disabled(!DeadlineNotifier.isAvailable)
                Picker("通知のタイミング", selection: $store.prefs.notifyHoursBefore) {
                    Text("1時間前").tag(1); Text("3時間前").tag(3); Text("12時間前").tag(12)
                    Text("24時間前").tag(24); Text("48時間前").tag(48)
                }
                .disabled(!store.prefs.notificationsEnabled)
                if !DeadlineNotifier.isAvailable {
                    Text("通知は .app として起動したときだけ使えます（scripts/build-app.sh）。").font(.caption).foregroundStyle(p.subtle)
                }
            }

            Card(title: "その他", symbol: "theatermasks") {
                Toggle("サンプルデータで表示を確認する", isOn: $store.prefs.useSampleData)
            }

            Card(title: "アプリ", symbol: "sparkles") {
                HStack {
                    Text("バージョン \(AppUpdater.currentVersion)").frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await store.updater.check(manual: true) } } label: {
                        Label("アップデートを確認", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(store.updater.state == .checking)
                }
                Text("新しいバージョンが出ると画面の上に知らせます。Mac 版は自分でビルドして使うので、ターミナルで git pull と ./scripts/build-app.sh --install を実行すると更新できます（「更新のしかた」で手順が開きます）。設定とログイン情報はそのまま引き継がれます。")
                    .font(.caption).foregroundStyle(p.subtle)
            }

            DiagnosticsCard()
        }
        .toggleStyle(.switch)
        .tint(p.accent)
        .confirmationDialog("URLを初期値に戻しますか？", isPresented: $confirmReset) {
            Button("初期値に戻す", role: .destructive) { store.resetConfig() }
        }
        .confirmationDialog("Moodle・Campus Squareのログイン状態を消去しますか？（保存したID・パスワードは残ります）", isPresented: $confirmClear) {
            Button("消去する", role: .destructive) { Task { await store.clearSessions() } }
        }
    }
}

private struct Field: View {
    @Environment(\.palette) private var p
    var title: String
    @Binding var text: String
    var isURL = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(p.subtle)
            TextField(title, text: $text, prompt: Text(isURL ? "https://…" : ""))
                .autocorrectionDisabled()
                .softField()
            if isURL {
                let url = SafeURL.https(text)
                if url == nil {
                    Text("https:// で始まる正しいURLを入力してください").font(.caption).foregroundStyle(p.alert)
                } else if SafeURL.isPlaceholder(url) {
                    Text("仮の値です。大学の公式URLに置き換えてください。").font(.caption).foregroundStyle(p.warn)
                }
            }
        }
    }
}

private struct CredentialEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var service: PortalService
    var title: String
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(p.ink)
                Spacer()
                if let saved = store.savedUsername[service] ?? nil {
                    Chip(text: "保存済み：\(saved)", symbol: "checkmark.seal.fill", color: .green)
                    Button("削除") { store.deleteCredentials(for: service) }.buttonStyle(SoftButtonStyle())
                } else {
                    Chip(text: "未保存", color: p.subtle)
                }
            }
            TextField("学籍番号（ユーザー名）", text: $username).autocorrectionDisabled().textContentType(.username).softField()
            SecureField("パスワード", text: $password).textContentType(.password).softField()
                .onSubmit(save)
            HStack {
                Button("キーチェーンに保存", action: save).buttonStyle(PrimaryButtonStyle())
                    .disabled(username.isEmpty || password.isEmpty)
                if let error { Text(error).font(.caption).foregroundStyle(p.alert) }
            }
        }
    }

    private func save() {
        error = store.saveCredentials(username: username, password: password, for: service)
        if error == nil { password = ""; username = "" }
    }
}

private struct GmailSettings: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var clientID = ""
    @State private var secret = ""
    @State private var error: String?
    @State private var showGuide = false

    var body: some View {
        @Bindable var store = store
        Card(title: "メール（Gmail）", symbol: "envelope.badge") {
            HStack {
                Text("状態").foregroundStyle(p.subtle)
                Spacer()
                if store.googleSignedIn { Chip(text: "連携中", symbol: "checkmark.seal.fill", color: .green) }
                else if store.googleClientReady { Chip(text: "ログイン待ち", color: p.warn) }
                else { Chip(text: "未設定", color: p.subtle) }
            }
            Field(title: "大学のメールアドレス（ログイン時の候補）", text: $store.config.mail.address, isURL: false)

            if !store.googleClientReady || showGuide {
                Text("① Google Cloud で OAuth クライアント（デスクトップアプリ）を作り、IDとシークレットを入れてください。")
                    .font(.caption).foregroundStyle(p.subtle).fixedSize(horizontal: false, vertical: true)
                TextField("クライアントID（….apps.googleusercontent.com）", text: $clientID).autocorrectionDisabled().softField()
                SecureField("クライアントシークレット", text: $secret).softField()
                HStack {
                    Button("保存") {
                        error = store.saveGoogleClient(id: clientID, secret: secret)
                        if error == nil { clientID = ""; secret = ""; showGuide = false }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(clientID.isEmpty || secret.isEmpty)
                    Button("作り方を見る") { NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!) }
                        .buttonStyle(SoftButtonStyle())
                }
                if let error { Text(error).font(.caption).foregroundStyle(p.alert) }
            } else {
                HStack {
                    Text("クライアントID").font(.caption).foregroundStyle(p.subtle)
                    Text(store.config.mail.googleClientID).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    Button("変更") { showGuide = true }.buttonStyle(SoftButtonStyle())
                }
            }

            HStack {
                if store.googleSignedIn {
                    Button("連携を解除", role: .destructive) { Task { await store.signOutGoogle() } }.buttonStyle(PrimaryButtonStyle(destructive: true))
                } else {
                    Button { Task { await store.signInGoogle() } } label: {
                        HStack { if store.googleBusy { ProgressView().controlSize(.small) }; Text(store.googleBusy ? "ブラウザでログインしてください…" : "② Googleでログイン") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!store.googleClientReady || store.googleBusy)
                }
            }
            Field(title: "取得するメールの条件（Gmailの検索と同じ書き方）", text: $store.config.mail.searchQuery, isURL: false)
            Text("""
            読み取り専用（gmail.readonly）で、件名・差出人・日時・冒頭の一部だけを取得します。\
            取得した内容は保存しません。ログインはGoogleの公式ページ（既定のブラウザ）で行い、アプリはGoogleのパスワードを扱いません。
            """).font(.caption).foregroundStyle(p.subtle).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DiagnosticsCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var expanded = false

    var body: some View {
        let entries = store.diagnostics.suffix(expanded ? 200 : 25)
        Card(title: "接続の診断", symbol: "stethoscope", trailing: "\(store.diagnostics.count)件") {
            Text("うまく読み込めないときは、ここに「どこで止まったか」が出ます。ID・パスワード・メール本文は記録しません。")
                .font(.caption).foregroundStyle(p.subtle).fixedSize(horizontal: false, vertical: true)
            if entries.isEmpty {
                StatusMessage(kind: .info, message: "まだ記録はありません。「更新」を押してください。")
            }
            ForEach(Array(entries)) { e in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: e.ok ? "checkmark.circle" : "xmark.octagon.fill").foregroundStyle(e.ok ? Color.green : p.alert).font(.caption)
                    Text(e.time.formatted(.dateTime.hour().minute().second())).font(.caption2.monospacedDigit()).foregroundStyle(p.subtle)
                    Text(e.service).font(.caption.bold()).foregroundStyle(p.accent)
                    Text(e.message).font(.caption).foregroundStyle(e.ok ? p.ink : p.alert).textSelection(.enabled)
                }
            }
            HStack {
                Button(expanded ? "最近のものだけ" : "すべて表示") { expanded.toggle() }.buttonStyle(SoftButtonStyle())
                Button("コピー") {
                    let text = store.diagnostics.map { "\($0.time.formatted(.dateTime.hour().minute().second())) [\($0.service)] \($0.ok ? "OK" : "NG") \($0.message)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    store.toast = "診断ログをコピーしました"
                }.buttonStyle(SoftButtonStyle())
            }
        }
    }
}
