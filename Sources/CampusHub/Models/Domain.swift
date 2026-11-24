import Foundation

enum LoadState<Value: Sendable>: Sendable {
    case notConfigured(String)
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? { if case .loaded(let v) = self { v } else { nil } }
}

// MARK: - Moodle

struct Deadline: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var course: String?
    var due: Date
    var url: URL?
    /// Moodle が「まだ行動が必要（未提出・未受験）」と判断しているもの
    var needsAction: Bool = true
    /// 活動の種類（assign / quiz / questionnaire / feedback / url など）
    var module: String?
    /// 活動ページを開いて確かめた提出状況
    var status: SubmissionStatus = .unknown
    /// 外部フォーム（Google フォーム等）のURL
    var formURL: URL?

    enum Urgency { case overdue, urgent, soon, normal }

    func urgency(now: Date = .now) -> Urgency {
        let remaining = due.timeIntervalSince(now)
        if remaining < 0 { return .overdue }
        if remaining < 24 * 3600 { return .urgent }
        if remaining < 72 * 3600 { return .soon }
        return .normal
    }
}

enum SubmissionStatus: String, Sendable, Hashable {
    /// 確認できなかった
    case unknown
    /// 活動ページに「あなたの回答」「提出済み」などがある
    case submitted
    /// 活動ページに「未提出」「回答していません」などがある
    case notSubmitted
    /// まだ受付が始まっていない（開始予定）
    case notOpenYet
    /// 外部フォームへのリンク（アプリから提出状況は分からない）
    case form
    /// 外部フォームだが、Gmail に回答の控えメールがあった
    case formReceipt

    var label: String? {
        switch self {
        case .unknown, .notSubmitted: nil
        case .submitted: "提出済み"
        case .notOpenYet: "受付開始前"
        case .form: "フォーム（提出は要確認）"
        case .formReceipt: "フォーム回答済み（控えメールあり）"
        }
    }
    var isDone: Bool { self == .submitted || self == .formReceipt }
}

struct Course: Identifiable, Hashable, Sendable {
    var id: Int
    var fullName: String
    var shortName: String
    var category: String?
    var progress: Double?
    var url: URL?
}

struct MoodleNotice: Identifiable, Hashable, Sendable {
    var id: Int
    var subject: String
    var time: Date
    var read: Bool
    var url: URL?
    /// 課題・小テストなどの通知は、リンク先のページで提出済みか確かめる（AppStore.checkSubmissions）
    var status: SubmissionStatus = .unknown

    /// Moodle の活動（課題・小テスト・アンケートなど）のページへのリンクか
    var linksToActivity: Bool {
        guard let url, url.path.range(of: #"/mod/[a-z]+/view.php$"#, options: .regularExpression) != nil else { return false }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "id" } ?? false
    }
}

struct MoodleSnapshot: Sendable {
    var courses: [Course]
    /// 未完了（行動が必要）の課題・小テスト
    var deadlines: [Deadline]
    /// 今後の予定（提出済みも含む締切・授業の予定など）
    var upcoming: [CalendarItem] = []
    var notices: [MoodleNotice]
    var unreadCount: Int
    var warnings: [String]
}

// MARK: - Campus Square

/// Campus Square の時間割表から読み取った内容（曜日 × 時限）
struct Timetable: Codable, Hashable, Sendable {
    struct Period: Codable, Hashable, Sendable {
        var label: String
        var byDay: [String: String]
    }
    var days: [String]
    var periods: [Period]

    static let weekdayChars = ["日", "月", "火", "水", "木", "金", "土"]

    static func dayChar(for date: Date, calendar: Calendar = .current) -> String {
        weekdayChars[calendar.component(.weekday, from: date) - 1]
    }

    /// セルの文字を「科目名・その他の行」に分ける。1行目が科目コード（英数字だけ）なら2行目を科目名にする
    static func split(_ text: String) -> (title: String, code: String?, rest: [String]) {
        var lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var code: String?
        if lines.count > 1, lines[0].range(of: "^[A-Za-z0-9_\\-]{4,}$", options: .regularExpression) != nil {
            code = lines.removeFirst()
        }
        let title = lines.first ?? text
        return (title, code, Array(lines.dropFirst()))
    }

    /// 指定曜日の授業（空きコマは除く）
    func classes(on day: String) -> [(period: String, text: String)] {
        periods.compactMap { p in
            let t = (p.byDay[day] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "-" || t == "－" ? nil : (p.label, t)
        }
    }

    /// 科目名を比べやすくする：全角→半角、カタカナ→ひらがな、【担当】・[曜限]・「後学期_」などの前置き・空白を除く
    static func courseKey(_ s: String) -> String {
        let k = s.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "【[^】]*】", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*(前学期|後学期|通年活動|通年)_", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\\s_]", with: "", options: .regularExpression)
            .lowercased()
        // カタカナ（ァ〜ヶ）だけをひらがなにする（長音「ー」などはそのまま。Windows 版と同じ）
        return String(String.UnicodeScalarView(k.unicodeScalars.map { u in
            (0x30A1...0x30F6).contains(u.value) ? Unicode.Scalar(u.value - 0x60)! : u
        }))
    }

    /// 2つの科目名の似ている度合い（0〜1、2文字ずつの組の重なり）。「心理をよむ」と「心理を読む」のような表記ゆれ用
    static func similarity(_ a: String, _ b: String) -> Double {
        func grams(_ s: String) -> [String] {
            let c = Array(s)
            return c.count < 2 ? [] : (0..<(c.count - 1)).map { String(c[$0...$0 + 1]) }
        }
        let ga = grams(a)
        var rest = grams(b)
        guard !ga.isEmpty, !rest.isEmpty else { return 0 }
        let total = ga.count + rest.count
        var hit = 0
        for g in ga { if let i = rest.firstIndex(of: g) { hit += 1; rest.remove(at: i) } }
        return Double(2 * hit) / Double(total)
    }

    /// 英数字の部分（「基礎1」の 1、「実習B」の b、「I」など）。ここが違えば別の科目とみなす
    private static func alnum(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "[a-z0-9]+") else { return "" }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .compactMap { Range($0.range, in: s).map { String(s[$0]) } }.joined(separator: ",")
    }

    /// 対応するコースが見つからないときに開く、Moodle のコース検索（科目名で探す）
    static func searchURL(base: String, text: String) -> URL? {
        let b = base.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let q = split(text).title.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "【[^】]*】", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard b.lowercased().hasPrefix("https://"), !q.isEmpty, var c = URLComponents(string: b + "/course/search.php") else { return nil }
        c.queryItems = [URLQueryItem(name: "search", value: q)]
        return c.url
    }

    /// 時間割のコマに対応する Moodle のコース（Windows版 logic.js の Timetable.moodleCourse と同じ規則）。
    /// ① 科目コード（時間割の B31L07K1 → Moodle の短縮名 …-B31L07K101）② 科目名 の順に強く見て、
    /// 同じ名前が複数あるときは曜限（[火1]）と今の学期（4〜9月は前学期）が合うものを選ぶ
    static func moodleCourse(in courses: [Course], text: String, day: String, period: String,
                             now: Date = .now, calendar: Calendar = .current) -> Course? {
        let parts = split(text)
        let key = courseKey(parts.title)
        let per = period.precomposedStringWithCompatibilityMapping
            .range(of: "\\d+", options: .regularExpression).map { String(period.precomposedStringWithCompatibilityMapping[$0]) }
        let month = calendar.component(.month, from: now)
        let term = (4...9).contains(month) ? "前学期" : "後学期"
        var best: Course?
        var bestScore = 0
        for c in courses where c.url != nil {
            let full = c.fullName.precomposedStringWithCompatibilityMapping
            let short = c.shortName.precomposedStringWithCompatibilityMapping
            var s = 0
            if let code = parts.code, code.count >= 6, short.contains(code) || full.contains(code) { s += 10 }
            let ck = courseKey(c.fullName)
            var samePeriod = false
            if let r = full.range(of: "\\[(.)(\\d+)", options: .regularExpression) {
                let tag = full[r].dropFirst()  // 例: "火1"
                if let d = tag.first, String(d) == day, String(tag.dropFirst()) == per { samePeriod = true }
            }
            if key.count >= 2, ck == key { s += 6 }
            else if min(key.count, ck.count) >= 3, ck.contains(key) || key.contains(ck) { s += 3 }
            else if alnum(key) == alnum(ck) {
                // 表記ゆれ（ひらがな／漢字、副題の有無など）。「基礎1」と「基礎2」、「実習A」と「実習B」のように英数字が違うものは別の科目とみなす
                let sim = similarity(key, ck)
                if sim >= 0.75 { s += 4 } else if sim >= 0.5 { s += 3 } else if sim >= 0.3, samePeriod { s += 2 }
            }
            if s == 0 { continue }
            if samePeriod { s += 2 }
            if full.contains(term) { s += 1 }
            else if full.contains("前学期") || full.contains("後学期") { s -= 3 }
            if s >= 3, s > bestScore { best = c; bestScore = s }
        }
        return best
    }
}

/// ポータルの各枠（お知らせ・掲示など）
struct Portlet: Codable, Hashable, Identifiable, Sendable {
    var title: String
    var lines: [String]
    var id: String { title }
}

/// ページ内の表をそのまま読み取ったもの
struct ExtractedTable: Codable, Hashable, Sendable {
    var title: String?
    var header: [String]
    var rows: [[String]]
}

struct CampusSnapshot: Sendable {
    var timetable: Timetable?
    var portlets: [Portlet]
    var cancellations: ExtractedTable?
    var warnings: [String]
}

/// ホームの「やること」を今週の分だけにするための規則（Windows版 logic.js の todos({ thisWeek }) と同じ）
enum ThisWeek {
    /// 授業は週1回なので、ホームに出す Moodle の締切は「あと7日」まで
    static let days = 7

    /// 締切まで「あと○日」の○（画面の表示と同じく切り捨て）が 7 を超えるか
    static func isLater(_ due: Date, now: Date) -> Bool {
        Int(floor(due.timeIntervalSince(now) / 86400)) > days
    }

    /// 文の中の日付（「12/2(水)」「12月2日」「2026/12/2」）。年が無ければ now に近い年にする
    static func guessDate(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let s = text.precomposedStringWithCompatibilityMapping
        guard let re = try? NSRegularExpression(pattern: "(?:(\\d{4})\\s*[/年.-]\\s*)?(\\d{1,2})\\s*[/月]\\s*(\\d{1,2})\\s*日?"),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func group(_ i: Int) -> Int? { Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } }
        guard let mon = group(2), let day = group(3), (1...12).contains(mon), (1...31).contains(day) else { return nil }
        func date(_ y: Int) -> Date? { calendar.date(from: DateComponents(year: y, month: mon, day: day)) }
        if let y = group(1) { return date(y) }
        let y = calendar.component(.year, from: now)
        return [y - 1, y, y + 1].compactMap(date).min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    /// Campus Square で見つけた休講（休講ページの表の行と、ポータルのお知らせのうち「休講」を含む行）
    static func cancellations(_ c: CampusSnapshot?, now: Date = .now, calendar: Calendar = .current) -> [(text: String, date: Date)] {
        guard let c else { return [] }
        let lines = (c.cancellations?.rows ?? []).map { $0.filter { !$0.isEmpty }.joined(separator: " ") } + c.portlets.flatMap(\.lines)
        return lines.filter { $0.contains("休講") }.compactMap { t in guessDate(t, now: now, calendar: calendar).map { (t, $0) } }
    }

    /// 締切の科目に、今日から締切までの間の休講があるか（「来週は休講なので2週間前から出ている課題」）
    static func cancelledBefore(course: String, due: Date, in list: [(text: String, date: Date)],
                                now: Date = .now, calendar: Calendar = .current) -> (text: String, date: Date)? {
        func core(_ s: String) -> String {
            Timetable.courseKey(s).replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        }
        let key = core(course)
        guard key.count >= 3 else { return nil }
        let start = calendar.startOfDay(for: now)
        return list.first { $0.date >= start && $0.date <= due && core($0.text).contains(key) }
    }
}

enum Importance {
    static let keywords = ["休講", "教室変更", "補講", "締切", "期限", "重要", "緊急", "至急", "変更"]
    static func isImportant(_ text: String) -> Bool { keywords.contains { text.contains($0) } }
}

// MARK: - カレンダー

struct CalendarItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case classSession, moodleEvent, deadline, mail }
    var id: String
    var title: String
    var start: Date
    var end: Date?
    var allDay: Bool = false
    var kind: Kind
    var course: String?
    var location: String?
    var url: URL?
    /// 時間割の「1限」など（時刻が分からない授業用）
    var periodLabel: String?
}

// MARK: - メール

enum MailCategory: String, CaseIterable, Sendable, Hashable {
    case action, classChange, exam, moodle, event, info, other
    var label: String {
        switch self {
        case .action: "要対応・締切"
        case .classChange: "休講・授業変更"
        case .exam: "試験・レポート"
        case .moodle: "Moodle通知"
        case .event: "行事・説明会"
        case .info: "大学からのお知らせ"
        case .other: "その他"
        }
    }
    var symbol: String {
        switch self {
        case .action: "exclamationmark.circle.fill"
        case .classChange: "calendar.badge.exclamationmark"
        case .exam: "pencil.and.list.clipboard"
        case .moodle: "book.closed"
        case .event: "person.3"
        case .info: "building.columns"
        case .other: "envelope"
        }
    }
}

struct MailMessage: Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String
    var subject: String
    var from: String
    var fromAddress: String
    var date: Date
    var snippet: String
    var unread: Bool
    var category: MailCategory = .other
    var isFromSchool = false
    /// 本文の一部から見つけた期限
    var dueDate: Date?
    /// 督促・未提出など「まだできていない」可能性を示す語を含む
    var looksOverdue = false
    /// 分類の理由（画面に表示する）
    var reasons: [String] = []
}

struct MailSnapshot: Sendable {
    var email: String
    var messages: [MailMessage]
    var unreadCount: Int
}

/// やること（Moodle の未完了課題 ＋ メールで見つけた要対応）
struct TodoItem: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable { case moodle, mail }
    var id: String
    var title: String
    var detail: String?
    var due: Date?
    var source: Source
    var url: URL?
    var reason: String
    var overdueHint: Bool = false
}

extension String {
    /// Moodle の文字列に残る HTML 実体参照・タグを取り除く
    var plainText: String {
        var s = replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        // &#12345; / &#x30A2; 形式
        while let r = s.range(of: "&#(x[0-9A-Fa-f]+|[0-9]+);", options: .regularExpression) {
            let body = s[r].dropFirst(2).dropLast()
            let code = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            s.replaceSubrange(r, with: code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
        }
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
