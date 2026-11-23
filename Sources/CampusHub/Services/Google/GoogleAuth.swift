import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Google 公式の OAuth 2.0（デスクトップアプリ向け：ループバック＋PKCE）。
/// - ログインは既定のブラウザで Google のページから行う（アプリはパスワードを見ない）
/// - 権限は Gmail の読み取りのみ（gmail.readonly）
/// - リフレッシュトークンとクライアントシークレットはキーチェーンに保存
///   （デスクトップ用クライアントのシークレットは Google の仕様上「秘密として扱われない」値だが、コードには埋め込まない）
enum GoogleAuthError: LocalizedError {
    case notConfigured, cancelled, timeout, denied(String), stateMismatch, token(String), notSignedIn
    var errorDescription: String? {
        switch self {
        case .notConfigured: "GoogleのクライアントIDとシークレットが未設定です（設定 → メール）。"
        case .cancelled: "ログインが中止されました。"
        case .timeout: "ログインの完了を待ちましたが、時間切れになりました。"
        case .denied(let e):
            e == "access_denied" ? "アクセスが許可されませんでした。大学の管理者が外部アプリを制限している可能性があります。" : "Googleがエラーを返しました（\(e)）。"
        case .stateMismatch: "ログインの応答が正しくありません（state不一致）。もう一度お試しください。"
        case .token(let e): "トークンを取得できませんでした（\(e)）。"
        case .notSignedIn: "Googleにログインしていません。設定 → メール →「Googleでログイン」を押してください。"
        }
    }
}

enum GoogleSecrets {
    private static let service = "local.campushub.google"
    enum Key: String { case clientSecret, refreshToken }

    static func save(_ value: String, _ key: Key) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key.rawValue, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: Key) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key.rawValue, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: key.rawValue] as CFDictionary)
    }
}

/// アクセストークンの管理（メモリ上のみ）
actor GoogleAuth {
    static let scope = "https://www.googleapis.com/auth/gmail.readonly"
    private var accessToken: String?
    private var expiry = Date.distantPast

    func signOut() {
        accessToken = nil
        expiry = .distantPast
        GoogleSecrets.delete(.refreshToken)
    }

    var isSignedIn: Bool { GoogleSecrets.read(.refreshToken) != nil }

    /// ブラウザでログイン → 認可コード → トークン
    func signIn(clientID: String, loginHint: String?) async throws {
        guard !clientID.isEmpty, let secret = GoogleSecrets.read(.clientSecret) else { throw GoogleAuthError.notConfigured }
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomURLSafe(24)

        let server = try LoopbackServer()
        let port = try await server.start()
        defer { server.stop() }
        let redirect = "http://127.0.0.1:\(port)"

        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
        ]
        if let hint = loginHint, !hint.isEmpty { c.queryItems?.append(.init(name: "login_hint", value: hint)) }
        let authURL = c.url!
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }

        let callback = try await server.waitForCallback(timeout: 300)
        if let err = callback["error"] { throw GoogleAuthError.denied(err) }
        guard callback["state"] == state else { throw GoogleAuthError.stateMismatch }
        guard let code = callback["code"] else { throw GoogleAuthError.cancelled }

        let tokens = try await Self.tokenRequest([
            "client_id": clientID, "client_secret": secret, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirect,
        ])
        guard let refresh = tokens.refresh_token else { throw GoogleAuthError.token("refresh_tokenがありません") }
        GoogleSecrets.save(refresh, .refreshToken)
        accessToken = tokens.access_token
        expiry = Date.now.addingTimeInterval(TimeInterval(tokens.expires_in ?? 3000) - 60)
    }

    func validAccessToken(clientID: String) async throws -> String {
        if let accessToken, Date.now < expiry { return accessToken }
        guard let refresh = GoogleSecrets.read(.refreshToken) else { throw GoogleAuthError.notSignedIn }
        guard !clientID.isEmpty, let secret = GoogleSecrets.read(.clientSecret) else { throw GoogleAuthError.notConfigured }
        do {
            let t = try await Self.tokenRequest([
                "client_id": clientID, "client_secret": secret, "refresh_token": refresh, "grant_type": "refresh_token",
            ])
            accessToken = t.access_token
            expiry = Date.now.addingTimeInterval(TimeInterval(t.expires_in ?? 3000) - 60)
            return t.access_token
        } catch GoogleAuthError.token(let e) where e.contains("invalid_grant") {
            GoogleSecrets.delete(.refreshToken)
            throw GoogleAuthError.notSignedIn
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String; let expires_in: Int?; let refresh_token: String?
    }
    private struct TokenError: Decodable { let error: String; let error_description: String? }

    private static func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode(form).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let t = try? JSONDecoder().decode(TokenResponse.self, from: data) { return t }
        let e = try? JSONDecoder().decode(TokenError.self, from: data)
        throw GoogleAuthError.token(e.map { "\($0.error) \($0.error_description ?? "")" } ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
    }

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// 127.0.0.1 で一度だけ認可コードを受け取る小さなHTTPサーバー
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "campushub.oauth.loopback")
    private let lock = NSLock()
    private var readyCont: CheckedContinuation<UInt16, Error>?
    private var callbackCont: CheckedContinuation<[String: String], Error>?
    private var pendingResult: Result<[String: String], Error>?

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            lock.withLock { readyCont = cont }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready: self.resumeReady(.success(self.listener.port?.rawValue ?? 0))
                case .failed(let e): self.resumeReady(.failure(e))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
        }
    }

    private func resumeReady(_ r: Result<UInt16, Error>) {
        let c = lock.withLock { () -> CheckedContinuation<UInt16, Error>? in defer { readyCont = nil }; return readyCont }
        c?.resume(with: r)
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    let pending = self.lock.withLock { () -> Result<[String: String], Error>? in
                        if let p = self.pendingResult { return p }
                        self.callbackCont = cont
                        return nil
                    }
                    if let pending { cont.resume(with: pending) }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GoogleAuthError.timeout
            }
            defer { group.cancelAll(); self.finish(.failure(GoogleAuthError.cancelled)) }
            return try await group.next()!
        }
    }

    private func finish(_ r: Result<[String: String], Error>) {
        let c = lock.withLock { () -> CheckedContinuation<[String: String], Error>? in
            defer { callbackCont = nil }
            if callbackCont == nil && pendingResult == nil { pendingResult = r }
            return callbackCont
        }
        c?.resume(with: r)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            var params: [String: String] = [:]
            URLComponents(string: "http://127.0.0.1" + path)?.queryItems?.forEach { params[$0.name] = $0.value }

            let ok = params["code"] != nil
            let html = """
            <!doctype html><meta charset="utf-8"><title>キャンパスハブ</title>
            <body style="font-family:-apple-system;background:#F6F8FF;color:#2B3A6E;display:grid;place-items:center;height:90vh">
            <div style="background:#fff;border:1px solid #DCE4FA;border-radius:22px;padding:32px 40px;text-align:center">
            <h2>\(ok ? "Googleとの連携ができました" : "連携できませんでした")</h2>
            <p>このタブを閉じて、キャンパスハブに戻ってください。</p></div></body>
            """
            let body = Data(html.utf8)
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
            if params["code"] != nil || params["error"] != nil { self.finish(.success(params)) }
        }
    }

    func stop() { listener.cancel() }
}
