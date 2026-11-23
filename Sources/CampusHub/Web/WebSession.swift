import AppKit
import WebKit

enum WebError: LocalizedError {
    case timeout, needsLogin, loginFailed, loginRejected, navigation(String), script(String)
    var errorDescription: String? {
        switch self {
        case .timeout: "読み込みがタイムアウトしました。ネットワークを確認して再試行してください。"
        case .needsLogin: "ログインが必要です。設定でID・パスワードを保存するか、「ブラウザ」タブで一度ログインしてください。"
        case .loginFailed: "自動ログインできませんでした。ID・パスワードを確認するか、「ブラウザ」タブでログインしてください。"
        case .loginRejected: "ログインページにエラーが表示されています。ID・パスワードを確認してください。"
        case .navigation(let m): "ページを開けませんでした：\(m)"
        case .script(let m): "ページの読み取りに失敗しました：\(m)"
        }
    }
}

/// WKWebView の共通設定。Cookie は Safari と別の、このアプリ専用の保存場所（default）に残る。
@MainActor
enum WebKitFactory {
    static func make(themeDomain: String?) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        if let themeDomain {
            config.userContentController.addUserScript(WKUserScript(
                source: Scripts.themeCSS(trustedDomain: themeDomain),
                injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }

    static func clearAllSessions() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

enum AutoLogin {
    @MainActor
    static func run(in webView: WKWebView, spec: LoginSpec, credentials: Credentials?, submit: Bool, checkOnly: Bool) async -> String {
        let args: [String: Any] = [
            "userSel": spec.username, "passSel": spec.password, "submitSel": spec.submit, "errSel": spec.error ?? "",
            "username": credentials?.username ?? "", "password": credentials?.password ?? "",
            "submit": submit, "checkOnly": checkOnly,
        ]
        let result = try? await webView.callAsyncJavaScript(Scripts.autoLogin, arguments: args, in: nil, contentWorld: .defaultClient)
        return result as? String ?? "none"
    }
}

/// 画面に出さない WKWebView で、ログイン後のページを開いて情報を読み取る。
@MainActor
final class HeadlessSession: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var finished = 0
    private var lastError: Error?

    override init() {
        webView = WebKitFactory.make(themeDomain: nil)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL, timeout: TimeInterval = 30) async throws {
        let start = finished
        lastError = nil
        webView.load(URLRequest(url: url))
        try await waitForFinish(after: start, timeout: timeout)
    }

    func waitForFinish(after count: Int, timeout: TimeInterval) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while finished <= count {
            if Date.now > deadline { throw WebError.timeout }
            try await Task.sleep(for: .milliseconds(150))
        }
        if let lastError { throw WebError.navigation(lastError.localizedDescription) }
    }

    func run(_ script: String, args: [String: Any] = [:], world: WKContentWorld = .defaultClient) async throws -> Any? {
        do { return try await webView.callAsyncJavaScript(script, arguments: args, in: nil, contentWorld: world) }
        catch { throw WebError.script(error.localizedDescription) }
    }

    func runJSON<T: Decodable>(_ script: String, as: T.Type) async throws -> T? {
        guard let s = try await run(script) as? String, let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 今いるページ（診断ログ用。クエリは含めない）
    var where_: String { webView.url.map { ($0.host() ?? "") + $0.path() } ?? "（なし）" }

    /// target を開き、ログインページが出たら保存済みのID・パスワードで公式フォームからログインする
    func ensureLoggedIn(at target: URL, host: String, spec: LoginSpec, credentials: Credentials?,
                        log: (String, Bool) -> Void = { _, _ in }) async throws {
        try await load(target)
        log("ページを開きました: \(where_)", true)
        guard await AutoLogin.run(in: webView, spec: spec, credentials: nil, submit: false, checkOnly: true) == "login" else {
            log("ログイン済みです", true)
            return
        }
        log("ログインフォームを検出しました", true)
        guard let credentials else { log("ID・パスワードが未保存（または自動ログインがオフ）", false); throw WebError.needsLogin }
        // 入力先が設定した大学のログインページ（https・ホスト一致）であることを確認してから入れる
        guard webView.url?.scheme == "https", webView.url?.host()?.lowercased() == host else {
            log("ログインページのホストが設定と違うため入力しません: \(where_)", false)
            throw WebError.loginFailed
        }

        let before = finished
        let result = await AutoLogin.run(in: webView, spec: spec, credentials: credentials, submit: true, checkOnly: false)
        if result == "error" { log("ログインページにエラー表示があります", false); throw WebError.loginRejected }
        guard result == "submitted" else { log("ログイン欄に入力できませんでした（\(result)）", false); throw WebError.loginFailed }
        log("ID・パスワードを入力して送信しました", true)
        try await waitForFinish(after: before, timeout: 30)
        try await Task.sleep(for: .milliseconds(800))
        log("ログイン後のページ: \(where_)", true)
        if await AutoLogin.run(in: webView, spec: spec, credentials: nil, submit: false, checkOnly: true) == "login" {
            log("ログイン後もログインフォームが表示されています（ID・パスワード違いの可能性）", false)
            throw WebError.loginFailed
        }
        if webView.url?.path() != target.path() {
            try await load(target)
            log("目的のページを開き直しました: \(where_)", true)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished += 1 }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }

    private func fail(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        lastError = error
        finished += 1
    }
}
