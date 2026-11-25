import Foundation
import Observation
import WebKit

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, calendar, moodle, campusSquare, mail, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "ホーム"
        case .calendar: "カレンダー"
        case .moodle: "Moodle"
        case .campusSquare: "Campus Square"
        case .mail: "メール"
        case .settings: "設定"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .calendar: "calendar"
        case .moodle: "book.closed"
        case .campusSquare: "building.columns"
        case .mail: "envelope"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum ViewMode: Hashable { case summary, browser }

/// 診断ログ（ID・パスワード・ページ内容は記録しない）
struct DiagEntry: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let service: String
    let message: String
    let ok: Bool
}

@MainActor
@Observable
final class AppStore {
    var selection: AppSection = .home
    var moodleMode: ViewMode = .summary
    var campusMode: ViewMode = .summary

    var config: UniversityConfig { didSet { save(config, key: Self.configKey) } }
    var prefs: AppPreferences {
        didSet {
            save(prefs, key: Self.prefsKey)
            if prefs.useSampleData != oldValue.useSampleData || prefs.deadlineWindowDays != oldValue.deadlineWindowDays {
                Task { await refresh() }
            }
            if prefs.notificationsEnabled != oldValue.notificationsEnabled || prefs.notifyHoursBefore != oldValue.notifyHoursBefore {
                Task { await updateNotifications() }
            }
        }
    }

    var moodle: LoadState<MoodleSnapshot> = .loading
    var campus: LoadState<CampusSnapshot> = .loading
    var mail: LoadState<MailSnapshot> = .loading
    var lastUpdated: Date?
    var isRefreshing = false
    var toast: String?
    var diagnostics: [DiagEntry] = []
    private(set) var savedUsername: [PortalService: String] = [:]
    /// Campus Square のメニュー（表示名, _flowId）
    private(set) var campusMenu: [(String, String)] = []
    private(set) var googleSignedIn = false
    var googleBusy = false

    /// Moodle の月ごとの予定（"2026-11" → 予定）
    private(set) var monthItems: [String: [CalendarItem]] = [:]
    private(set) var monthErrors: [String: String] = [:]
    private(set) var monthLoading: Set<String> = []

    /// 「完了」にしたやることのID（内容は保存しない）
    private(set) var doneIDs: Set<String> { didSet { defaults.set(Array(doneIDs), forKey: Self.doneKey) } }
    /// 「コース（教材）」から外したコース（もう受けていないコースなど）の ID
    private(set) var hiddenCourseIDs: Set<Int> { didSet { defaults.set(Array(hiddenCourseIDs), forKey: Self.hiddenCoursesKey) } }

    @ObservationIgnored let moodleBrowser: BrowserController
    @ObservationIgnored let campusBrowser: BrowserController
    @ObservationIgnored private var sessions: [PortalService: HeadlessSession] = [:]
    @ObservationIgnored let google = GoogleAuth()

    private static let configKey = "universityConfig.v2"
    private static let prefsKey = "appPreferences.v2"
    private static let doneKey = "doneTodoIDs.v1"
    private static let hiddenCoursesKey = "hiddenCourseIDs.v1"
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var cfg = Self.load(UniversityConfig.self, key: Self.configKey, defaults: defaults) ?? DefaultConfig.university
        // 以前の仮のメール設定は Google の初期値へ置き換える
        if cfg.mail.provider == .unknown && SafeURL.isPlaceholder(SafeURL.https(cfg.mail.webURL)) {
            cfg.mail.webURL = DefaultConfig.university.mail.webURL
            cfg.mail.provider = DefaultConfig.university.mail.provider
        }
        let pr = Self.load(AppPreferences.self, key: Self.prefsKey, defaults: defaults) ?? AppPreferences()
        config = cfg
        prefs = pr
        doneIDs = Set(defaults.stringArray(forKey: Self.doneKey) ?? [])
        hiddenCourseIDs = Set(defaults.array(forKey: Self.hiddenCoursesKey) as? [Int] ?? [])
        let theme = pr.themeOfficialPages ? cfg.trustedDomain : nil
        moodleBrowser = BrowserController(service: .moodle, themeDomain: theme)
        campusBrowser = BrowserController(service: .campus, themeDomain: theme)
        moodleBrowser.store = self
        campusBrowser.store = self
        refreshSavedUsernames()
        googleSignedIn = GoogleSecrets.read(.refreshToken) != nil
    }

    func browser(for s: PortalService) -> BrowserController { s == .moodle ? moodleBrowser : campusBrowser }

    /// アプリ内ブラウザで開く
    func openInApp(_ url: URL?, service: PortalService) {
        guard let url else { return }
        if service == .moodle { selection = .moodle; moodleMode = .browser }
        else { selection = .campusSquare; campusMode = .browser }
        browser(for: service).load(url)
    }

    func diag(_ service: String, _ message: String, ok: Bool = true) {
        let e = DiagEntry(time: .now, service: service, message: message, ok: ok)
        diagnostics.append(e)
        if diagnostics.count > 300 { diagnostics.removeFirst(diagnostics.count - 300) }
        DiagFile.append(e)
    }

    // MARK: - Credentials

    func credentials(for s: PortalService) -> Credentials? {
        CredentialStore.read(s == .campus && prefs.sameCredentials ? .moodle : s)
    }

    func refreshSavedUsernames() {
        for s in PortalService.allCases { savedUsername[s] = CredentialStore.read(s)?.username }
    }

    func saveCredentials(username: String, password: String, for s: PortalService) -> String? {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !password.isEmpty else { return "IDとパスワードを入力してください。" }
        guard CredentialStore.save(Credentials(username: u, password: password), for: s) else { return "キーチェーンへの保存に失敗しました。" }
        refreshSavedUsernames()
        toast = "\(s.label)のログイン情報を保存しました"
        Task { await refresh() }
        return nil
    }

    func deleteCredentials(for s: PortalService) {
        CredentialStore.delete(s)
        refreshSavedUsernames()
        toast = "\(s.label)のログイン情報を削除しました"
    }

    func clearSessions() async {
        await WebKitFactory.clearAllSessions()
        sessions = [:]
        toast = "ログイン状態（Cookie）を消去しました"
        await refresh()
    }

    func resetConfig() {
        let mail = config.mail
        config = DefaultConfig.university
        config.mail.address = mail.address
        config.mail.googleClientID = mail.googleClientID
    }

    // MARK: - Google

    func saveGoogleClient(id: String, secret: String) -> String? {
        let i = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard i.hasSuffix(".apps.googleusercontent.com") else { return "クライアントIDは「….apps.googleusercontent.com」の形です。" }
        guard !s.isEmpty else { return "クライアントシークレットを入力してください。" }
        config.mail.googleClientID = i
        GoogleSecrets.save(s, .clientSecret)
        toast = "Googleのクライアント情報を保存しました"
        return nil
    }

    var googleClientReady: Bool { !config.mail.googleClientID.isEmpty && GoogleSecrets.read(.clientSecret) != nil }

    func signInGoogle() async {
        googleBusy = true
        defer { googleBusy = false }
        do {
            diag("メール", "ブラウザでGoogleのログインを開きました")
            try await google.signIn(clientID: config.mail.googleClientID, loginHint: config.mail.address)
            googleSignedIn = true
            diag("メール", "Googleとの連携が完了しました")
            toast = "Googleと連携しました"
            mail = .loading
            mail = await fetchMail()
        } catch {
            diag("メール", "Googleのログインに失敗: \(error.localizedDescription)", ok: false)
            toast = error.localizedDescription
        }
    }

    func signOutGoogle() async {
        await google.signOut()
        googleSignedIn = false
        mail = .notConfigured("Googleとの連携を解除しました。")
        toast = "Googleとの連携を解除しました"
    }

    // MARK: - やること

    func toggleDone(_ id: String) {
        if doneIDs.contains(id) { doneIDs.remove(id) } else { doneIDs.insert(id) }
    }

    /// コースを「コース（教材）」の一覧から外す・戻す
    func setCourseHidden(_ id: Int, _ hidden: Bool) {
        if hidden { hiddenCourseIDs.insert(id) } else { hiddenCourseIDs.remove(id) }
    }

    func gmailURL(for m: MailMessage) -> URL? {
        let user = mail.value?.email ?? config.mail.address
        return URL(string: "https://mail.google.com/mail/u/?authuser=\(user.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "@.-_"))) ?? "")#all/\(m.threadId)")
    }

    /// Moodle の未完了課題 ＋ メールで見つけた要対応。
    /// thisWeek（ホーム）のときは、受付開始前のものと、あと8日以上先のものを出さない。
    /// ただし先の締切でも、もう提出できるもの・締切までに休講があるもの（早めに出ている課題）は出す
    func todos(includeDone: Bool = false, now: Date = .now, thisWeek: Bool = false) -> [TodoItem] {
        var items: [TodoItem] = []
        let cancels = thisWeek ? ThisWeek.cancellations(campus.value, now: now) : []
        for d in moodle.value?.deadlines ?? [] where !d.status.isDone {
            var early: String?
            if thisWeek {
                if d.status == .notOpenYet { continue }
                if ThisWeek.isLater(d.due, now: now) {
                    if let course = d.course,
                       let c = ThisWeek.cancelledBefore(course: course, due: d.due, in: cancels, now: now,
                                                        code: ThisWeek.courseCode(moodle.value?.courses.first { $0.fullName == course }?.shortName)) {
                        let md = c.date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "ja_JP")))
                        early = "締切は先ですが、\(md)が休講なので早めに出ている課題です"
                    } else if d.status == .notSubmitted || d.status == .form {
                        early = "締切は先ですが、もう提出できます（早めに出ている課題）"
                    } else {
                        continue
                    }
                }
            }
            let overdue = d.due < now
            var reason: String = switch d.status {
            case .form: "外部フォームです。提出したかはアプリから分からないので、済んだらチェックしてください"
            case .notSubmitted: overdue ? "期限を過ぎていて、まだ提出していません（ページで確認）" : "まだ提出していません（ページで確認）"
            case .notOpenYet: "まだ受付が始まっていません（開始されたら取り組む）"
            default: !d.needsAction ? "Moodleの予定にある締切（提出済みかは未確認）"
                : overdue ? "期限を過ぎていますが、Moodle上でまだ完了していません" : "Moodleで未提出・未完了"
            }
            if let early { reason = early + (d.status == .form ? "（外部フォーム。済んだらチェック）" : "") }
            items.append(TodoItem(id: d.id, title: d.title, detail: d.course, due: d.due, source: .moodle,
                                  url: d.formURL ?? d.url ?? config.moodleUpcoming, reason: reason,
                                  overdueHint: overdue && d.needsAction && d.status != .form && d.status != .notOpenYet))
        }
        // コースのページにある、締切の書かれていないフォーム（今の回のものだけ。前の回のものは Moodle 画面にまとめる）
        for f in moodle.value?.forms ?? [] where f.recent && !f.status.isDone {
            items.append(TodoItem(id: f.id, title: f.title, detail: f.course, due: nil, source: .moodle, url: f.formURL ?? f.url,
                                  reason: "外部フォームです（締切の記載なし）。提出したかはアプリから分からないので、済んだらチェックしてください"))
        }
        for m in mail.value?.messages ?? [] where m.category == .action {
            if let due = m.dueDate, due < now.addingTimeInterval(-14 * 86400) { continue }
            if m.dueDate == nil && m.date < now.addingTimeInterval(-21 * 86400) { continue }
            items.append(TodoItem(id: "mail-" + m.id, title: m.subject, detail: m.from, due: m.dueDate, source: .mail,
                                  url: gmailURL(for: m), reason: m.reasons.joined(separator: " / "), overdueHint: m.looksOverdue))
        }
        if !includeDone { items.removeAll { doneIDs.contains($0.id) } }
        return items.sorted { a, b in
            if a.overdueHint != b.overdueHint { return a.overdueHint }
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.title < b.title
            }
        }
    }

    // MARK: - カレンダー

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    func loadMonth(_ date: Date, force: Bool = false) async {
        let key = Self.monthKey(date)
        if prefs.useSampleData || monthLoading.contains(key) || (!force && monthItems[key] != nil) { return }
        guard let dash = config.moodleDashboard, let host = config.loginHost(for: .moodle) else { return }
        monthLoading.insert(key)
        defer { monthLoading.remove(key) }
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        let s = session(.moodle)
        do {
            var raw = try await s.run(Scripts.moodleMonth, args: ["year": c.year!, "mon": c.month!], world: .page) as? String
            if raw?.contains("nosesskey") ?? true {
                try await s.ensureLoggedIn(at: dash, host: host, spec: config.moodleLogin, credentials: loginCredentials(.moodle)) { [weak self] m, ok in
                    self?.diag("Moodle", m, ok: ok)
                }
                raw = try await s.run(Scripts.moodleMonth, args: ["year": c.year!, "mon": c.month!], world: .page) as? String
            }
            let items = try MoodleParser.parseMonth(raw ?? "", config: config)
            monthItems[key] = items
            monthErrors[key] = nil
            diag("Moodle", "カレンダー \(key): \(items.count)件")
        } catch {
            monthErrors[key] = error.localizedDescription
            diag("Moodle", "カレンダー \(key): \(error.localizedDescription)", ok: false)
        }
    }

    /// その日の予定（授業・Moodleの予定・締切・メールの期限）
    func calendarItems(on day: Date, calendar: Calendar = .current) -> [CalendarItem] {
        var items: [CalendarItem] = []
        if prefs.showTimetableInCalendar, let tt = campus.value?.timetable {
            let dayChar = Timetable.dayChar(for: day, calendar: calendar)
            for (i, c) in tt.classes(on: dayChar).enumerated() {
                let parts = Timetable.split(c.text)
                items.append(CalendarItem(id: "tt-\(dayChar)-\(i)", title: parts.title,
                                          start: calendar.startOfDay(for: day).addingTimeInterval(Double(i)),
                                          kind: .classSession, course: parts.rest.first, periodLabel: c.period))
            }
        }
        var seen = Set<String>()
        let month = monthItems[Self.monthKey(day, calendar: calendar)] ?? []
        for e in month + (moodle.value?.upcoming ?? []) where calendar.isDate(e.start, inSameDayAs: day) && seen.insert(e.id).inserted {
            items.append(e)
        }
        for d in moodle.value?.deadlines ?? [] where calendar.isDate(d.due, inSameDayAs: day) {
            let id = "c-" + d.id.dropFirst(2)
            if seen.insert(id).inserted {
                items.append(CalendarItem(id: id, title: d.title, start: d.due, kind: .deadline, course: d.course, url: d.url))
            }
        }
        for m in mail.value?.messages ?? [] where m.category == .action || m.category == .classChange {
            if let due = m.dueDate, calendar.isDate(due, inSameDayAs: day) {
                items.append(CalendarItem(id: "mail-" + m.id, title: m.subject, start: due, kind: .mail, course: m.from, url: gmailURL(for: m)))
            }
        }
        return items.sorted { a, b in
            if (a.kind == .classSession) != (b.kind == .classSession) { return a.kind == .classSession }
            return a.start < b.start
        }
    }

    // MARK: - Loading

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if prefs.useSampleData {
            moodle = .loaded(SampleData.moodle())
            campus = .loaded(SampleData.campus())
            mail = .loaded(SampleData.mail(trustedDomain: config.trustedDomain))
            lastUpdated = .now
            return
        }
        diag("全体", "更新を開始しました")
        moodle = .loading
        campus = .loading
        // 未連携ならすぐに案内を出す（他の読み込みを待たない）
        mail = googleSignedIn ? .loading : await fetchMail()
        moodleGen += 1
        async let m = fetchMoodle()
        async let c = fetchCampus()
        async let g = fetchMail()
        moodle = await m
        // コースのページを見て回るのは時間がかかる（URL の活動が数百件）ので、締切を先に出してから裏で行う
        if moodle.value != nil { Task { await scanCourseForms() } }
        campus = await c
        mail = await g
        monthItems = [:]
        lastUpdated = .now
        await loadMonth(.now)
        await updateNotifications()
    }

    private func session(_ s: PortalService) -> HeadlessSession {
        if let existing = sessions[s] { return existing }
        let new = HeadlessSession()
        sessions[s] = new
        return new
    }

    private func loginCredentials(_ s: PortalService) -> Credentials? {
        prefs.autoLogin ? credentials(for: s) : nil
    }

    private func fetchMoodle() async -> LoadState<MoodleSnapshot> {
        guard let dash = config.moodleDashboard, let host = config.loginHost(for: .moodle) else {
            return .notConfigured("MoodleのURLが正しくありません。設定を確認してください。")
        }
        let s = session(.moodle)
        let log: (String, Bool) -> Void = { [weak self] m, ok in self?.diag("Moodle", m, ok: ok) }
        do {
            try await s.ensureLoggedIn(at: dash, host: host, spec: config.moodleLogin, credentials: loginCredentials(.moodle), log: log)
            let cal = Calendar.current
            let from = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: .now))!
            let to = Date.now.addingTimeInterval(Double(prefs.deadlineWindowDays) * 86400)
            let raw = try await s.run(Scripts.moodleFetch,
                                      args: ["from": Int(from.timeIntervalSince1970), "to": Int(to.timeIntervalSince1970)],
                                      world: .page)
            guard let json = raw as? String else { log("読み取りスクリプトの結果が空です", false); throw MoodleParser.ParseError.invalid }
            var snap = try MoodleParser.parse(json, config: config, log: log)
            await checkSubmissions(&snap, session: s, log: log)
            snap.calendarDue = []
            snap.formsLoading = true
            return .loaded(snap)
        } catch WebError.needsLogin {
            return .notConfigured(WebError.needsLogin.localizedDescription)
        } catch {
            log(error.localizedDescription, false)
            return .failed(error.localizedDescription)
        }
    }

    /// 課題・アンケートのページを開いて提出状況を確かめ、外部フォームは Gmail の控えメールと照合する
    private func checkSubmissions(_ snap: inout MoodleSnapshot, session s: HeadlessSession, log: (String, Bool) -> Void) async {
        let targets = snap.deadlines.filter { $0.url != nil }.prefix(60)
        // 通知（「提出期限 …: 第7回課題」など）も、リンク先が課題などのページなら同じように確かめる
        let noticeIdx = snap.notices.indices.filter { snap.notices[$0].linksToActivity }
        // 月のカレンダーにだけある締切（表示期間内）。ページに外部フォームがあれば締切に加える
        let limit = Date.now.addingTimeInterval(Double(prefs.deadlineWindowDays) * 86400)
        let calendarDue = Array(snap.calendarDue.filter { $0.url != nil && $0.due <= limit }.prefix(40))
        var urls: [String] = []
        for u in targets.compactMap({ $0.url?.absoluteString }) + noticeIdx.compactMap({ snap.notices[$0].url?.absoluteString })
            + calendarDue.compactMap({ $0.url?.absoluteString }) where !urls.contains(u) {
            urls.append(u)
        }
        guard !urls.isEmpty else { return }
        struct R: Decodable { let url: String; let status: String; let hit: String; let form: String? }
        do {
            let raw = try await s.run(Scripts.moodleSubmissionStatus, args: ["urls": urls], world: .page)
            guard let json = raw as? String, let results = try? JSONDecoder().decode([R].self, from: Data(json.utf8)) else {
                log("提出状況の確認: 結果を読めませんでした", false); return
            }
            let byURL = Dictionary(results.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
            for i in snap.deadlines.indices {
                guard let u = snap.deadlines[i].url?.absoluteString, let r = byURL[u] else { continue }
                snap.deadlines[i].status = SubmissionStatus(rawValue: r.status) ?? .unknown
                snap.deadlines[i].formURL = r.form.flatMap(SafeURL.https)
            }
            for i in noticeIdx {
                guard let u = snap.notices[i].url?.absoluteString, let r = byURL[u] else { continue }
                snap.notices[i].status = SubmissionStatus(rawValue: r.status) ?? .unknown
            }
            var added = 0
            for var d in calendarDue {
                guard let u = d.url?.absoluteString, let r = byURL[u], r.status == "form" else { continue }
                d.status = .form
                d.formURL = r.form.flatMap(SafeURL.https)
                snap.deadlines.append(d)
                added += 1
            }
            if !calendarDue.isEmpty { log("カレンダーにだけある締切 \(calendarDue.count)件のうち、外部フォームの課題 \(added)件を追加", true) }
            snap.deadlines.sort { $0.due < $1.due }
            // 何の文言で判定したかを集計してログに残す（内容は残さない）
            let summary = Dictionary(grouping: results, by: { "\($0.status):\($0.hit)" }).map { "\($0.key)×\($0.value.count)" }.sorted()
            log("提出状況の確認 \(results.count)件: " + summary.joined(separator: " / "), true)
            if !noticeIdx.isEmpty {
                let doneN = noticeIdx.filter { snap.notices[$0].status.isDone }.count
                log("通知のうち課題などへのリンク \(noticeIdx.count)件: 提出済み \(doneN)件を「提出済みの通知」にまとめます", true)
            }
        } catch {
            log("提出状況の確認に失敗: \(error.localizedDescription)", false)
        }
    }

    /// Moodle の読み込みごとに増やす（裏で確認している間に更新し直したら、古い結果は使わない）
    private var moodleGen = 0
    /// URL の活動のリンク先は変わらないので、確かめた結果（cm → フォームの URL か ""）を覚えておき、次からは開かない
    private var formCache: [String: String] = [:]

    /// コースのページから、カレンダーに載らないフォーム（「URL」「ページ」「ラベル」に置かれた Google フォームなど）を探し、
    /// 締切のあるものは締切に、ないものは forms に入れる。そのあと外部フォームを Gmail の控えメールと照合する
    private func scanCourseForms() async {
        guard var snap = moodle.value else { return }
        let gen = moodleGen
        let s = session(.moodle)
        let log: (String, Bool) -> Void = { [weak self] m, ok in self?.diag("Moodle", m, ok: ok) }
        let now = Date.now
        let ids = snap.courses.filter { c in
            !hiddenCourseIDs.contains(c.id) && (c.endDate.map { $0 > now.addingTimeInterval(-14 * 86400) } ?? true)
        }.map(\.id).prefix(40)
        if !ids.isEmpty {
            do {
                let raw = try await s.run(Scripts.moodleCourseForms, args: ["ids": Array(ids), "known": formCache], world: .page)
                let known = Set(snap.deadlines.compactMap { MoodleParser.cmID($0.url) ?? $0.formURL.map { "form:\($0.absoluteString)" } })
                let r = MoodleParser.parseCourseForms(raw as? String ?? "", config: config, courses: snap.courses, known: known,
                                                      now: now, windowDays: prefs.deadlineWindowDays)
                formCache.merge(r.checked) { _, new in new }
                snap.deadlines = (snap.deadlines + r.deadlines).sorted { $0.due < $1.due }
                snap.forms = r.forms
                let st = r.stats
                var pages = "活動 \(st?.activities ?? 0)件・URL \(st?.urls ?? 0)件・開いたページ \(st?.opened ?? 0)件"
                if let c = st?.cached, c > 0 { pages += "・確認済み \(c)件" }
                if let k = st?.skippedPages, k > 0 { pages += "・開かなかった \(k)件" }
                if let e = st?.errors, e > 0 { pages += "・失敗 \(e)件" }
                log("コースのページ \(st?.courses ?? 0)件（\(pages)）から外部フォーム: 締切あり \(r.deadlines.count)件・締切の記載なし \(r.forms.count)件"
                    + "（うち今の回 \(r.forms.filter(\.recent).count)件）・締切を過ぎた／1か月以上前の回／表示期間より先 \(r.skipped)件", (st?.errors ?? 0) == 0)
            } catch {
                log("コースのページからフォームを探せませんでした: \(error.localizedDescription)", false)
            }
        }
        if gen == moodleGen { await checkFormReceipts(&snap, log: log) }
        snap.formsLoading = false
        guard gen == moodleGen, moodle.value != nil else { return }
        moodle = .loaded(snap)
        await updateNotifications()
    }

    /// 外部フォーム：Gmail に Google フォームの控え（回答のコピー）があれば回答済みとみなす
    private func checkFormReceipts(_ snap: inout MoodleSnapshot, log: (String, Bool) -> Void) async {
        let forms = snap.deadlines.indices.filter { snap.deadlines[$0].status == .form }
        let undated = snap.forms.indices.filter { snap.forms[$0].status == .form }
        guard !forms.isEmpty || !undated.isEmpty, googleSignedIn else { return }
        do {
            let token = try await google.validAccessToken(clientID: config.mail.googleClientID)
            let receipts = try await GmailClient(token: token).formReceipts()
            var matched = 0
            for i in forms where GmailClient.hasReceipt(for: snap.deadlines[i], in: receipts) {
                snap.deadlines[i].status = .formReceipt
                matched += 1
            }
            for i in undated where GmailClient.hasReceipt(title: snap.forms[i].title, due: nil, in: receipts) {
                snap.forms[i].status = .formReceipt
                matched += 1
            }
            log("フォームの控えメール \(receipts.count)通と照合: \(matched)/\(forms.count + undated.count)件が回答済み", true)
        } catch {
            log("フォームの控えメールを確認できませんでした: \(error.localizedDescription)", false)
        }
        // 同じ課題の締切が「控えメールあり」になったら、その通知も回答済みにする
        let receipted = Set(snap.deadlines.filter { $0.status == .formReceipt }.compactMap { $0.url?.absoluteString })
        for i in snap.notices.indices where snap.notices[i].linksToActivity
            && (snap.notices[i].url.map { receipted.contains($0.absoluteString) } ?? false) {
            snap.notices[i].status = .formReceipt
        }
    }

    private func fetchCampus() async -> LoadState<CampusSnapshot> {
        guard let portal = SafeURL.https(config.campusSquare.portal), let host = config.loginHost(for: .campus) else {
            return .notConfigured("Campus SquareのURLが正しくありません。設定を確認してください。")
        }
        let s = session(.campus)
        let log: (String, Bool) -> Void = { [weak self] m, ok in self?.diag("Campus Square", m, ok: ok) }
        do {
            try await s.ensureLoggedIn(at: portal, host: host, spec: config.campusLogin, credentials: loginCredentials(.campus), log: log)
            try await Task.sleep(for: .seconds(1.5)) // ポータルの枠は後から読み込まれることがある
            let portlets = try await s.runJSON(Scripts.campusPortlets, as: [Portlet].self) ?? []
            log("ポータルの枠: \(portlets.count)個（\(portlets.map(\.title).joined(separator: "、"))）", true)
            struct MenuLink: Decodable { let flow: String; let text: String }
            let menu = try await s.runJSON(Scripts.campusMenu, as: [MenuLink].self) ?? []
            campusMenu = menu.map { ($0.text, $0.flow) }
            log("メニュー: " + menu.map { "\($0.text.isEmpty ? "?" : $0.text)=\($0.flow)" }.joined(separator: " / "), true)
            var warnings: [String] = []

            var timetable: Timetable?
            if let url = SafeURL.https(config.campusSquare.timetable) {
                do {
                    try await s.load(url)
                    try await Task.sleep(for: .seconds(3))
                    timetable = try await s.runJSON(Scripts.campusTimetable, as: Timetable.self)
                    if timetable == nil, let h = try? await s.run(Scripts.pageHeading) as? String {
                        log("時間割ページの見出し: \(h)", false)
                        if let shapes = try? await s.run(Scripts.tableShapes) as? String { log("表の構造: \(shapes)", false) }
                    }
                    log("時間割ページ \(s.where_): " + (timetable.map { "\($0.periods.count)時限分" } ?? "表が見つかりません"), timetable != nil)
                    if timetable == nil { warnings.append("時間割ページで表を見つけられませんでした。「ブラウザ」タブで時間割を開き、「このページを時間割に設定」を押してください。") }
                } catch { warnings.append("時間割: " + error.localizedDescription); log("時間割: \(error.localizedDescription)", false) }
            }

            var cancellations: ExtractedTable?
            if let url = SafeURL.https(config.campusSquare.cancellations) {
                do {
                    try await s.load(url)
                    try await Task.sleep(for: .seconds(1))
                    if let list = try await s.runJSON(Scripts.campusCancellations, as: ExtractedTable.self) {
                        cancellations = list
                        let kinds = Dictionary(grouping: list.rows, by: { $0.count > 4 ? $0[4] : "" }).map { " \($0.key)×\($0.value.count)" }.sorted().joined()
                        log("休講・補講（一覧・今日から5週間）: \(list.rows.count)件" + kinds, true)
                    } else {
                        // 休講補講参照以外のページが設定されているときは、いちばん大きい表を読む
                        cancellations = try await s.runJSON(Scripts.largestTable, as: ExtractedTable.self)
                        log("休講ページ \(s.where_): \(cancellations?.rows.count ?? 0)行", true)
                    }
                } catch { warnings.append("休講情報: " + error.localizedDescription); log("休講: \(error.localizedDescription)", false) }
            }
            return .loaded(CampusSnapshot(timetable: timetable, portlets: portlets, cancellations: cancellations, warnings: warnings))
        } catch WebError.needsLogin {
            return .notConfigured(WebError.needsLogin.localizedDescription)
        } catch {
            log(error.localizedDescription, false)
            return .failed(error.localizedDescription)
        }
    }

    private func fetchMail() async -> LoadState<MailSnapshot> {
        guard googleSignedIn else {
            return .notConfigured(googleClientReady
                ? "Googleと連携していません。設定 → メール →「Googleでログイン」を押してください。"
                : "メールを読み込むには、設定 → メール でGoogleとの連携を設定してください。")
        }
        do {
            let token = try await google.validAccessToken(clientID: config.mail.googleClientID)
            let r = try await GmailClient(token: token).fetch(query: config.mail.searchQuery)
            let domain = config.trustedDomain
            let messages = r.messages.map { GmailClient.convert($0, trustedDomain: domain) }.sorted { $0.date > $1.date }
            diag("メール", "\(messages.count)通を取得（未読 \(r.unread)）")
            return .loaded(MailSnapshot(email: r.email, messages: messages, unreadCount: r.unread))
        } catch GoogleAuthError.notSignedIn {
            googleSignedIn = false
            return .notConfigured(GoogleAuthError.notSignedIn.localizedDescription)
        } catch {
            diag("メール", error.localizedDescription, ok: false)
            return .failed(error.localizedDescription)
        }
    }

    private func updateNotifications() async {
        guard prefs.notificationsEnabled, !prefs.useSampleData else {
            await DeadlineNotifier.cancelAll()
            return
        }
        if await DeadlineNotifier.requestAuthorization() {
            let upcoming = (moodle.value?.deadlines ?? []).filter { $0.due > .now && $0.needsAction && !$0.status.isDone }
            await DeadlineNotifier.reschedule(upcoming, hoursBefore: prefs.notifyHoursBefore)
        }
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

/// 診断ログのファイル（~/Library/Logs/CampusHub/diagnostics.log）。ID・パスワード・内容は書かない。
enum DiagFile {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CampusHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.log")
    }()

    static func append(_ e: DiagEntry) {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        let line = "\(f.string(from: e.time)) [\(e.service)] \(e.ok ? "OK" : "NG") \(e.message)\n"
        // 1MB を超えたら作り直す
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
