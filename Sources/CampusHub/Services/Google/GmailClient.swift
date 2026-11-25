import Foundation

/// Gmail API（読み取りのみ）。件名・差出人・日時・冒頭の抜粋（snippet）だけを取得する。
/// 取得した内容はメモリ上だけで扱い、ファイルには保存しない。
struct GmailClient: Sendable {
    let token: String

    enum GmailError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(403, let m) where m.contains("accessNotConfigured") || m.contains("has not been used"):
                "Google Cloud で Gmail API が有効になっていません。プロジェクトで「Gmail API」を有効にしてください。"
            case .http(401, _): "Googleの認証が切れました。設定 → メールからもう一度ログインしてください。"
            case .http(let c, let m): "Gmail APIのエラー（\(c)）：\(m.prefix(160))"
            }
        }
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = [], as: T.Type) async throws -> T {
        var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw GmailError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    struct Profile: Decodable { let emailAddress: String }
    struct ListResponse: Decodable { let messages: [Ref]?; struct Ref: Decodable { let id: String } }
    struct Label: Decodable { let messagesUnread: Int? }
    struct Message: Decodable {
        let id: String; let threadId: String; let labelIds: [String]?; let snippet: String?; let internalDate: String?
        let payload: Payload?
        struct Payload: Decodable { let headers: [Header]? }
        struct Header: Decodable { let name: String; let value: String }
    }

    func fetch(query: String, max: Int = 60) async throws -> (email: String, unread: Int, messages: [Message]) {
        let profile = try await get("profile", as: Profile.self)
        let inbox = try? await get("labels/INBOX", as: Label.self)
        let list = try await get("messages", [.init(name: "q", value: query), .init(name: "maxResults", value: String(max))],
                                 as: ListResponse.self)
        let ids = (list.messages ?? []).map(\.id)

        // 6件ずつ並行して取得
        var messages: [Message] = []
        for chunk in stride(from: 0, to: ids.count, by: 6).map({ Array(ids[$0..<min($0 + 6, ids.count)]) }) {
            try await withThrowingTaskGroup(of: Message.self) { group in
                for id in chunk {
                    group.addTask {
                        try await get("messages/\(id)", [
                            .init(name: "format", value: "metadata"),
                            .init(name: "metadataHeaders", value: "Subject"),
                            .init(name: "metadataHeaders", value: "From"),
                        ], as: Message.self)
                    }
                }
                for try await m in group { messages.append(m) }
            }
        }
        return (profile.emailAddress, inbox?.messagesUnread ?? 0, messages)
    }

    /// Google フォームの「回答のコピー」メール（件名・抜粋・日時）
    func formReceipts(days: Int = 180) async throws -> [(text: String, date: Date)] {
        let list = try await get("messages", [
            .init(name: "q", value: "from:forms-receipts-noreply@google.com newer_than:\(days)d"),
            .init(name: "maxResults", value: "100"),
        ], as: ListResponse.self)
        var out: [(String, Date)] = []
        for ref in (list.messages ?? []).prefix(100) {
            let m = try await get("messages/\(ref.id)", [.init(name: "format", value: "metadata"), .init(name: "metadataHeaders", value: "Subject")],
                                  as: Message.self)
            let subject = m.payload?.headers?.first { $0.name.lowercased() == "subject" }?.value ?? ""
            out.append((subject + " " + (m.snippet ?? "").plainText, Date(timeIntervalSince1970: (Double(m.internalDate ?? "0") ?? 0) / 1000)))
        }
        return out
    }

    /// 課題名から「(出席課題)」「（締切:…）」などを除いた、照合用の名前
    static func coreTitle(_ title: String) -> String {
        var t = title
        for pattern in [#"[（(][^）)]*[）)]"#, #"【[^】]*】"#, #"\[[^\]]*\]"#] {
            t = t.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return t.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    /// 控えメールの中に課題名があり、日付が締切の前後なら「回答済み」とみなす
    static func hasReceipt(for d: Deadline, in receipts: [(text: String, date: Date)]) -> Bool {
        hasReceipt(title: d.title, due: d.due, in: receipts)
    }

    /// 締切の書かれていないフォーム（due が nil）は、控えメールの日付を問わない（控えメールは180日分）
    static func hasReceipt(title: String, due: Date?, in receipts: [(text: String, date: Date)]) -> Bool {
        let core = coreTitle(title)
        guard core.count >= 3 else { return false }
        return receipts.contains { r in
            guard r.text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression).contains(core) else { return false }
            guard let due else { return true }
            return r.date > due.addingTimeInterval(-21 * 86400) && r.date < due.addingTimeInterval(86400)
        }
    }

    /// API の応答を画面用のメールに変換し、分類する
    static func convert(_ m: Message, trustedDomain: String, now: Date = .now) -> MailMessage {
        let headers = m.payload?.headers ?? []
        func h(_ n: String) -> String { headers.first { $0.name.caseInsensitiveCompare(n) == .orderedSame }?.value ?? "" }
        let (name, address) = parseFrom(h("From"))
        let date = Date(timeIntervalSince1970: (Double(m.internalDate ?? "0") ?? 0) / 1000)
        var mail = MailMessage(id: m.id, threadId: m.threadId, subject: h("Subject").isEmpty ? "（件名なし）" : h("Subject"),
                               from: name, fromAddress: address, date: date, snippet: (m.snippet ?? "").plainText,
                               unread: m.labelIds?.contains("UNREAD") ?? false)
        MailClassifier.classify(&mail, trustedDomain: trustedDomain, now: now)
        return mail
    }

    /// "山田 太郎 <taro@example.jp>" → ("山田 太郎", "taro@example.jp")
    static func parseFrom(_ raw: String) -> (String, String) {
        if let lt = raw.lastIndex(of: "<"), let gt = raw.lastIndex(of: ">"), lt < gt {
            let addr = String(raw[raw.index(after: lt)..<gt])
            var name = raw[..<lt].trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? addr : name, addr)
        }
        let t = raw.trimmingCharacters(in: .whitespaces)
        return (t, t)
    }
}
