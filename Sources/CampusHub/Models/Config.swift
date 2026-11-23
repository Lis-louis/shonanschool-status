import Foundation

struct UniversityConfig: Codable, Equatable, Sendable {
    var universityName: String
    var trustedDomain: String
    var moodleBaseURL: String
    var moodleLogin: LoginSpec
    var campusSquare: CampusSquareURLs
    var campusLogin: LoginSpec
    var mail: MailConfig
}

/// 公式ログインページの入力欄（CSSセレクタ）
struct LoginSpec: Codable, Equatable, Sendable {
    var username: String
    var password: String
    var submit: String
    var error: String?
}

struct CampusSquareURLs: Codable, Equatable, Sendable {
    var login: String
    var portal: String
    var timetable: String
    var cancellations: String
    var grades: String
    var syllabus: String
    var attendance: String
}

enum MailProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknown, microsoft365, googleWorkspace, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: "未確定"
        case .microsoft365: "Microsoft 365（Outlook）"
        case .googleWorkspace: "Google Workspace（Gmail）"
        case .other: "その他"
        }
    }
}

struct MailConfig: Codable, Equatable, Sendable {
    var webURL: String
    var provider: MailProvider
    /// 大学のGoogleアカウント（ログイン時の候補として渡すだけ）
    var address: String = ""
    /// Google Cloud で作った「デスクトップアプリ」の OAuth クライアントID（公開情報。シークレットはキーチェーン）
    var googleClientID: String = ""
    /// Gmail の検索条件（Gmail の検索窓と同じ書き方）
    var searchQuery: String = MailConfig.defaultQuery

    static let defaultQuery = "newer_than:30d -category:promotions -category:social"

    init(webURL: String, provider: MailProvider, address: String = "", googleClientID: String = "", searchQuery: String = MailConfig.defaultQuery) {
        self.webURL = webURL; self.provider = provider; self.address = address
        self.googleClientID = googleClientID; self.searchQuery = searchQuery
    }

    // 古い設定（項目が少ない）も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        webURL = try c.decode(String.self, forKey: .webURL)
        provider = try c.decode(MailProvider.self, forKey: .provider)
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        googleClientID = try c.decodeIfPresent(String.self, forKey: .googleClientID) ?? ""
        searchQuery = try c.decodeIfPresent(String.self, forKey: .searchQuery) ?? MailConfig.defaultQuery
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var showTodayClasses = true
    var showDeadlines = true
    var showNotices = true
    var showMail = true
    var deadlineWindowDays = 30
    var notificationsEnabled = false
    var notifyHoursBefore = 24
    var useSampleData = false
    /// 保存したID・パスワードで公式ログインページに自動入力し、ログインボタンを押す
    var autoLogin = true
    /// Campus Square も Moodle と同じID・パスワードを使う
    var sameCredentials = true
    /// アプリ内ブラウザで大学のページに鈴テーマの配色を少しだけ重ねる
    var themeOfficialPages = true
    /// カレンダーに毎週の時間割を表示する
    var showTimetableInCalendar = true

    init() {}

    // 項目が増えても、以前の設定を読み込めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppPreferences()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        showTodayClasses = v(.showTodayClasses, d.showTodayClasses)
        showDeadlines = v(.showDeadlines, d.showDeadlines)
        showNotices = v(.showNotices, d.showNotices)
        showMail = v(.showMail, d.showMail)
        deadlineWindowDays = v(.deadlineWindowDays, d.deadlineWindowDays)
        notificationsEnabled = v(.notificationsEnabled, d.notificationsEnabled)
        notifyHoursBefore = v(.notifyHoursBefore, d.notifyHoursBefore)
        useSampleData = v(.useSampleData, d.useSampleData)
        autoLogin = v(.autoLogin, d.autoLogin)
        sameCredentials = v(.sameCredentials, d.sameCredentials)
        themeOfficialPages = v(.themeOfficialPages, d.themeOfficialPages)
        showTimetableInCalendar = v(.showTimetableInCalendar, d.showTimetableInCalendar)
    }
}

enum PortalService: String, CaseIterable, Sendable {
    case moodle, campus
    var label: String { self == .moodle ? "Moodle" : "Campus Square" }
}

enum SafeURL {
    static func https(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "https",
              let host = comps.host, !host.isEmpty,
              comps.user == nil, comps.password == nil,
              let url = comps.url
        else { return nil }
        return url
    }

    static func isPlaceholder(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return true }
        return host == "example" || host.hasSuffix(".example") || host.hasSuffix(".invalid")
            || host.hasSuffix("example.com") || host.hasSuffix("example.org") || host.hasSuffix("example.net")
    }

    static func appending(_ path: String, to base: String) -> URL? {
        guard let baseURL = https(base) else { return nil }
        var s = baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return https(s + path)
    }

    /// 大学のドメイン（またはそのサブドメイン）かどうか
    static func isTrusted(_ url: URL?, domain: String) -> Bool {
        guard let url, url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !d.isEmpty else { return false }
        return host == d || host.hasSuffix("." + d)
    }

    /// Campus Square のURLから、セッション固有の値（_flowExecutionKey など）を取り除く
    static func stableCampusURL(_ url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        if let flow = comps.queryItems?.first(where: { $0.name == "_flowId" })?.value {
            comps.queryItems = [URLQueryItem(name: "_flowId", value: flow)]
        } else {
            let kept = comps.queryItems?.filter { !$0.name.hasPrefix("_flowExecutionKey") && $0.name != "_eventId" }
            comps.queryItems = (kept?.isEmpty ?? true) ? nil : kept
        }
        comps.fragment = nil
        return comps.string ?? url.absoluteString
    }
}

extension UniversityConfig {
    var moodleHome: URL? { SafeURL.https(moodleBaseURL) }
    var moodleLoginURL: URL? { SafeURL.appending("/login/index.php", to: moodleBaseURL) }
    var moodleDashboard: URL? { SafeURL.appending("/my/", to: moodleBaseURL) }
    var moodleCourses: URL? { SafeURL.appending("/my/courses.php", to: moodleBaseURL) }
    var moodleUpcoming: URL? { SafeURL.appending("/calendar/view.php?view=upcoming", to: moodleBaseURL) }
    var moodleNotifications: URL? { SafeURL.appending("/message/output/popup/notifications.php", to: moodleBaseURL) }
    func moodleCourse(id: Int) -> URL? { SafeURL.appending("/course/view.php?id=\(id)", to: moodleBaseURL) }

    func loginSpec(for service: PortalService) -> LoginSpec { service == .moodle ? moodleLogin : campusLogin }
    func loginHost(for service: PortalService) -> String? {
        (service == .moodle ? moodleLoginURL : SafeURL.https(campusSquare.login))?.host()?.lowercased()
    }
    func startURL(for service: PortalService) -> URL? {
        service == .moodle ? moodleDashboard : SafeURL.https(campusSquare.portal)
    }
}
