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
