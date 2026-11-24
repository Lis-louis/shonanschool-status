import AppKit
import CryptoKit
import Foundation

// アプリの更新（Mac 版）。
// GitHub の Releases（Lis-louis/shonanschool-status）に新しい版の CampusHub-<版>.pkg が出たら裏でダウンロードし、
// 画面の上に「更新する」を出す。押すとインストーラーが開き、アプリは終了する（インストールが終わったら開き直す）。
// Windows 版（windows/src/main/updater.js）と同じく、起動10秒後と3時間ごとに確認する。
// Releases は windows/package.json の version を上げて main に push すると、
// GitHub Actions（.github/workflows/release-mac.yml）が .pkg を同じ版の Release に追加する。
//
// Windows 版と違い、終了時に黙って入れ替えることはしない（/Applications への書き込みには管理者の確認が要るため）。
// 送るのは GitHub への普通の問い合わせとダウンロードだけで、ID・パスワード・読み取った内容は送らない。

enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case downloading(version: String, percent: Int)
    case ready(version: String, file: URL)

    var version: String? {
        switch self {
        case .downloading(let v, _), .ready(let v, _): v
        default: nil
        }
    }
}

/// Releases の中から、今より新しい Mac 用の .pkg を選ぶ（テストできるよう、通信と切り離してある）
enum UpdateCheck {
    static let repository = "Lis-louis/shonanschool-status"
    static let releasesURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=15")!
    /// ダウンロードを許すホスト（GitHub の Releases と、その転送先）
    static let downloadHosts: Set<String> = ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]

    struct Release: Decodable, Sendable {
        var tag_name: String
        var draft: Bool
        var prerelease: Bool
        var assets: [Asset]
    }

    struct Asset: Decodable, Sendable {
        var name: String
        var size: Int
        var digest: String?
        var browser_download_url: URL
    }

    struct Candidate: Equatable, Sendable {
        var version: String
        var url: URL
        var size: Int
        /// 小文字16進の SHA-256
        var sha256: String
    }

    /// "0.3.10" → [0, 3, 10]。数字以外が混ざっていれば nil
    static func parse(_ v: String) -> [Int]? {
        let s = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        guard let x = parse(a), let y = parse(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// 下書き・プレリリースを除き、CampusHub-<版>.pkg（SHA-256 付き）がある、今より新しい最も新しい版
    static func pick(_ releases: [Release], current: String) -> Candidate? {
        var best: Candidate?
        for r in releases where !r.draft && !r.prerelease {
            guard let v = parse(r.tag_name).map({ $0.map(String.init).joined(separator: ".") }) else { continue }
            guard let a = r.assets.first(where: { $0.name == "CampusHub-\(v).pkg" }),
                  let d = a.digest, d.hasPrefix("sha256:"), a.size > 0,
                  a.browser_download_url.scheme == "https", a.browser_download_url.host == "github.com"
            else { continue }
            let hex = String(d.dropFirst("sha256:".count)).lowercased()
            guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { continue }
            guard isNewer(v, than: current), best.map({ isNewer(v, than: $0.version) }) ?? true else { continue }
            best = Candidate(version: v, url: a.browser_download_url, size: a.size, sha256: hex)
        }
        return best
    }
}

@MainActor
@Observable
final class AppUpdater {
    private(set) var state: UpdateState = .idle
    /// 「あとで」を押した版（同じ版の表示は出さない）
    var hiddenVersion: String?

    @ObservationIgnored weak var store: AppStore?
    @ObservationIgnored private var timer: Timer?
    /// ダウンロード済みで「更新する」を待っている版（さらに新しい版の取得に失敗したら、こちらに戻す）
    @ObservationIgnored private var ready: UpdateState?

    static let firstCheckDelay: Duration = .seconds(10)   // 起動直後は読み込みを優先する
    static let checkInterval: TimeInterval = 3 * 60 * 60   // 起動しっぱなしでも3時間ごとに確認

    /// Info.plist の版（scripts/build-app.sh が windows/package.json の version を入れる）
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開発版"
    }

    /// .app として起動したときだけ（`swift run` の開発中は確認しない）
    static var isEnabled: Bool { Bundle.main.bundleURL.pathExtension == "app" && UpdateCheck.parse(currentVersion) != nil }

    var showsBanner: Bool {
        guard let v = state.version else { return false }
        return hiddenVersion != v
    }

    func start() {
        guard Self.isEnabled, timer == nil else { return }
        Task {
            try? await Task.sleep(for: Self.firstCheckDelay)
            await check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check(manual: Bool = false) async {
        guard Self.isEnabled else {
            if manual { store?.toast = "開発中の起動（swift run）ではアップデートを確認しません" }
            return
        }
        switch state {
        case .checking, .downloading:
            if manual { store?.toast = "アップデートを確認・ダウンロード中です" }
            return
        case .ready:
            // 「更新する」を押さずに使い続けている間に、さらに新しい版が出ていないかも裏で確かめる
            if manual { store?.toast = "新しいバージョンの準備ができています。画面の上の「更新する」を押してください" }
        case .idle: break
        }
        if case .idle = state { state = .checking }
        do {
            var req = URLRequest(url: UpdateCheck.releasesURL, timeoutInterval: 30)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("CampusHub-mac", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http((resp as? HTTPURLResponse)?.statusCode ?? 0) }
            let releases = try JSONDecoder().decode([UpdateCheck.Release].self, from: data)
            let current = ready?.version ?? Self.currentVersion
            guard let c = UpdateCheck.pick(releases, current: current) else {
                if case .checking = state { state = .idle }
                if manual && ready == nil { store?.toast = "最新のバージョン（\(Self.currentVersion)）です" }
                return
            }
            store?.diag("アプリ", "新しいバージョン \(c.version) が見つかりました。ダウンロードします")
            try await download(c)
        } catch {
            store?.diag("アプリ", "アップデートの確認・ダウンロードに失敗: \(String(describing: error).prefix(200))", ok: false)
            if manual { store?.toast = "アップデートを確認できませんでした（インターネット接続を確認してください）" }
            state = ready ?? .idle
        }
    }

    private func download(_ c: UpdateCheck.Candidate) async throws {
        state = .downloading(version: c.version, percent: 0)
        let progress = DownloadProgress { [weak self] p in
            Task { @MainActor in
                guard let self, case .downloading(let v, let old) = self.state, v == c.version, old != p else { return }
                self.state = .downloading(version: v, percent: p)
            }
        }
        let (tmp, resp) = try await URLSession.shared.download(from: c.url, delegate: progress)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.http((resp as? HTTPURLResponse)?.statusCode ?? 0) }
        guard let host = http.url?.host, http.url?.scheme == "https", UpdateCheck.downloadHosts.contains(host) else { throw UpdateError.untrustedHost }

        let data = try Data(contentsOf: tmp, options: .mappedIfSafe)
        guard data.count == c.size else { throw UpdateError.sizeMismatch }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == c.sha256 else { throw UpdateError.digestMismatch }

        let dir = try Self.updatesDirectory()
        // 古い版のインストーラーは消す
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? FileManager.default.removeItem(at: f) }
        let dest = dir.appendingPathComponent("CampusHub-\(c.version).pkg")
        try data.write(to: dest, options: .atomic)

        let r = UpdateState.ready(version: c.version, file: dest)
        ready = r
        state = r
        store?.diag("アプリ", "新しいバージョン \(c.version) の準備ができました")
    }

    /// 「更新する」：インストーラーを開いてアプリを終了する
    func install() {
        guard case .ready(_, let file) = state, FileManager.default.fileExists(atPath: file.path) else {
            state = .idle; ready = nil
            store?.toast = "インストーラーが見つかりませんでした。もう一度「アップデートを確認」を押してください"
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Installer.app"),
                                configuration: cfg) { _, error in
            Task { @MainActor in
                if let error {
                    self.store?.toast = "インストーラーを開けませんでした：\(error.localizedDescription)"
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func updatesDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("CampusHub/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum UpdateError: Error, CustomStringConvertible {
    case http(Int), untrustedHost, sizeMismatch, digestMismatch
    var description: String {
        switch self {
        case .http(let c): "HTTP \(c)"
        case .untrustedHost: "GitHub 以外からのダウンロードになったため中止"
        case .sizeMismatch: "ダウンロードしたファイルの大きさが Release と違う"
        case .digestMismatch: "ダウンロードしたファイルの SHA-256 が Release と違う"
        }
    }
}

/// ダウンロードの進み具合（％）を知らせる
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let onPercent: @Sendable (Int) -> Void
    init(_ onPercent: @escaping @Sendable (Int) -> Void) { self.onPercent = onPercent }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onPercent(Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
