import Foundation

/// メールを「要対応・休講・試験…」に分け、期限や「まだできていない」可能性を見つける。
/// 決まった言葉と日付の書き方で判断する（理由を画面に出すので、なぜそう分けたか分かる）。
enum MailClassifier {
    static let actionWords = ["提出", "締切", "締め切り", "〆切", "期限", "までに", "回答", "申請", "手続", "登録", "支払", "納付",
                              "必ず", "至急", "要確認", "確認してください", "受付", "予約", "履修"]
    static let overdueWords = ["未提出", "未登録", "未納", "未回答", "未完了", "督促", "再提出", "まだ提出", "提出されていません",
                               "期限を過ぎ", "期限切れ", "最終案内", "リマインド", "再送"]
    static let classChangeWords = ["休講", "補講", "教室変更", "授業変更", "遠隔授業", "オンライン授業", "時間割変更"]
    static let examWords = ["試験", "テスト", "レポート", "追試", "再試"]
    static let eventWords = ["説明会", "ガイダンス", "セミナー", "イベント", "就職", "インターンシップ", "健康診断", "オリエンテーション"]

    static func classify(_ m: inout MailMessage, trustedDomain: String, now: Date = .now) {
        let text = m.subject + " " + m.snippet
        let domain = trustedDomain.lowercased()
        let addr = m.fromAddress.lowercased()
        let senderDomain = addr.split(separator: "@").last.map(String.init) ?? ""
        m.isFromSchool = !domain.isEmpty && (senderDomain == domain || senderDomain.hasSuffix("." + domain))

        func hits(_ words: [String]) -> [String] { words.filter { text.contains($0) } }
        var reasons: [String] = []
        let overdue = hits(overdueWords)
        let action = hits(actionWords)
        let change = hits(classChangeWords)
        let exam = hits(examWords)
        let event = hits(eventWords)
        let isMoodle = addr.contains("moodle") || m.from.lowercased().contains("moodle")

        m.dueDate = DateExtractor.findDeadline(in: text, reference: m.date)
        m.looksOverdue = !overdue.isEmpty

        if !change.isEmpty {
            m.category = .classChange; reasons.append("「\(change.joined(separator: "・"))」を含む")
        } else if !overdue.isEmpty || (!action.isEmpty && (m.dueDate != nil || m.isFromSchool)) {
            m.category = .action
            if !overdue.isEmpty { reasons.append("「\(overdue.joined(separator: "・"))」＝まだできていない可能性") }
            if !action.isEmpty { reasons.append("「\(action.prefix(3).joined(separator: "・"))」を含む") }
        } else if isMoodle {
            m.category = .moodle; reasons.append("Moodleからの通知")
        } else if !exam.isEmpty {
            m.category = .exam; reasons.append("「\(exam.joined(separator: "・"))」を含む")
        } else if !event.isEmpty {
            m.category = .event; reasons.append("「\(event.joined(separator: "・"))」を含む")
        } else if m.isFromSchool {
            m.category = .info
        } else {
            m.category = .other
        }
        if let due = m.dueDate { reasons.append("期限らしき日付: " + due.formatted(.dateTime.month().day().locale(Locale(identifier: "ja_JP")))) }
        if m.isFromSchool { reasons.append("大学のアドレスから") }
        m.reasons = reasons
    }
}

/// 日本語の文章から日付を見つける（「12月5日まで」「12/5(金)17:00締切」「2026年1月10日」など）
enum DateExtractor {
    private static let patterns: [String] = [
        #"(20\d{2})[年/\-.](\d{1,2})[月/\-.](\d{1,2})日?"#,
        #"(\d{1,2})月(\d{1,2})日"#,
        #"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"#,
    ]
    private static let deadlineMarkers = ["まで", "締切", "締め切り", "〆切", "期限", "必着"]

    struct Found { let date: Date; let range: Range<String.Index> }

    static func findAll(in text: String, reference: Date, calendar: Calendar = .current) -> [Found] {
        var out: [Found] = []
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text) else { continue }
                if out.contains(where: { $0.range.overlaps(r) }) { continue }
                let g = (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text).flatMap { Int(text[$0]) } }
                var comps = DateComponents()
                if g.count == 3 { comps.year = g[0]; comps.month = g[1]; comps.day = g[2] }
                else if g.count == 2 { comps.month = g[0]; comps.day = g[1] }
                else { continue }
                guard let mo = comps.month, (1...12).contains(mo), let d = comps.day, (1...31).contains(d) else { continue }
                if comps.year == nil {
                    // 年が書かれていない場合：基準日より大きく前なら翌年とみなす
                    let refYear = calendar.component(.year, from: reference)
                    let refMonth = calendar.component(.month, from: reference)
                    comps.year = mo + 3 < refMonth ? refYear + 1 : refYear
                }
                // 時刻（17:00 / 17時）
                let tail = text[r.upperBound...].prefix(16)
                if let tm = tail.range(of: #"(\d{1,2})[:：時](\d{2})?"#, options: .regularExpression) {
                    let nums = tail[tm].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                    if let hh = nums.first, hh < 24 { comps.hour = hh; comps.minute = nums.count > 1 ? nums[1] : 0 }
                }
                if comps.hour == nil { comps.hour = 23; comps.minute = 59 }
                if let date = calendar.date(from: comps) { out.append(Found(date: date, range: r)) }
            }
        }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// 「まで」「締切」などのすぐ近くにある日付だけを返す（長い文の中の関係ない日付を拾わない）
    static func findMarked(in text: String, reference: Date, calendar: Calendar = .current) -> Date? {
        for f in findAll(in: text, reference: reference, calendar: calendar) {
            let around = text[f.range.lowerBound...].prefix(24)
            let before = text[..<f.range.lowerBound].suffix(10)
            if deadlineMarkers.contains(where: { around.contains($0) || before.contains($0) }) { return f.date }
        }
        return nil
    }

    /// 「まで」「締切」などの近くにある日付を優先して1つ返す
    static func findDeadline(in text: String, reference: Date, calendar: Calendar = .current) -> Date? {
        let all = findAll(in: text, reference: reference, calendar: calendar)
        guard !all.isEmpty else { return nil }
        for f in all {
            let around = text[f.range.lowerBound...].prefix(24)
            let before = text[..<f.range.lowerBound].suffix(10)
            if deadlineMarkers.contains(where: { around.contains($0) || before.contains($0) }) { return f.date }
        }
        let markersPresent = deadlineMarkers.contains { text.contains($0) }
        return markersPresent ? all.first?.date : nil
    }
}
