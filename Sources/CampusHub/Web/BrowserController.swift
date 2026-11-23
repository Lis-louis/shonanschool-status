import AppKit
import Observation
import UniformTypeIdentifiers
import WebKit

/// アプリ内ブラウザ（公式サイトをそのまま表示）。
/// - 大学のドメイン以外へのリンクは既定のブラウザで開く
/// - 公式ログインページを開いたときだけ、保存済みのID・パスワードを自動入力する
/// - ファイルのダウンロード（教材）・アップロード（課題提出）に対応
@MainActor
@Observable
final class BrowserController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let service: PortalService
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored weak var store: AppStore?
    @ObservationIgnored private var lastAutoSubmit: Date?
    @ObservationIgnored private var downloadNames: [ObjectIdentifier: URL] = [:]

    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var currentURL: URL?
    var title = ""
    var message: String?
    private(set) var hasLoaded = false

    init(service: PortalService, themeDomain: String?) {
        self.service = service
        webView = WebKitFactory.make(themeDomain: themeDomain)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func load(_ url: URL) {
        hasLoaded = true
        webView.load(URLRequest(url: url))
    }

    func loadIfNeeded(_ url: URL?) {
        guard !hasLoaded, let url else { return }
        load(url)
    }

    /// 「ログイン情報を入力」ボタン用（押したときはボタンも押す）
    func fillCredentialsNow() async {
        guard let store, let (spec, creds) = loginContext(store) else {
            message = "このページは自動入力の対象外です（設定した大学のログインページではありません）。"
            return
        }
        guard let creds else { message = "ID・パスワードが保存されていません。設定で保存してください。"; return }
        let r = await AutoLogin.run(in: webView, spec: spec, credentials: creds, submit: true, checkOnly: false)
        message = switch r {
        case "submitted": "ログイン情報を入力しました。"
        case "error": "ログインページにエラーが表示されています。ID・パスワードを確認してください。"
        default: "このページにログイン欄が見つかりません。"
        }
    }

    /// 現在のページが設定した大学のログインページ（https・ホスト一致）なら、その入力欄定義と資格情報を返す
    private func loginContext(_ store: AppStore) -> (LoginSpec, Credentials?)? {
        guard let url = webView.url, url.scheme == "https",
              let host = url.host()?.lowercased(), host == store.config.loginHost(for: service) else { return nil }
        return (store.config.loginSpec(for: service), store.credentials(for: service))
    }

    private func tryAutoLogin() async {
        guard let store, store.prefs.autoLogin, let (spec, creds) = loginContext(store), let creds else { return }
        guard await AutoLogin.run(in: webView, spec: spec, credentials: nil, submit: false, checkOnly: true) == "login" else { return }
        // 同じ失敗を繰り返さないよう、自動でボタンを押すのは30秒に1回まで
        let canSubmit = lastAutoSubmit.map { Date.now.timeIntervalSince($0) > 30 } ?? true
        let r = await AutoLogin.run(in: webView, spec: spec, credentials: creds, submit: canSubmit, checkOnly: false)
        if r == "submitted" { lastAutoSubmit = .now; message = "自動ログインしています…" }
        if r == "error" { message = "ログインに失敗したようです。ID・パスワードを確認してください。" }
    }

    private func sync() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        currentURL = webView.url
        title = webView.title ?? ""
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        Task { await tryAutoLogin() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }

    private func failed(_ error: Error) {
        sync()
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled || ns.code == 102 /* frame load interrupted (download) */ { return }
        message = "ページを開けませんでした：\(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
        if ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
        let isMain = navigationAction.targetFrame?.isMainFrame ?? true
        let trusted = SafeURL.isTrusted(url, domain: store?.config.trustedDomain ?? "")
        if isMain && !trusted {
            // 大学以外のサイト・メールリンク等は既定のアプリで開く
            if ["http", "https", "mailto"].contains(scheme) { NSWorkspace.shared.open(url) }
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let safeName = (suggestedFilename as NSString).lastPathComponent.isEmpty ? "download" : (suggestedFilename as NSString).lastPathComponent
        var dest = dir.appendingPathComponent(safeName)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (safeName as NSString).deletingPathExtension, ext = (safeName as NSString).pathExtension
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        downloadNames[ObjectIdentifier(download)] = dest
        message = "ダウンロード中：\(dest.lastPathComponent)"
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let dest = downloadNames.removeValue(forKey: ObjectIdentifier(download)) {
            message = "ダウンロードしました：\(dest.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        message = "ダウンロードに失敗しました：\(error.localizedDescription)"
    }

    // MARK: WKUIDelegate

    /// target=_blank / window.open は同じ画面で開く
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if SafeURL.isTrusted(url, domain: store?.config.trustedDomain ?? "") { webView.load(navigationAction.request) }
            else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
