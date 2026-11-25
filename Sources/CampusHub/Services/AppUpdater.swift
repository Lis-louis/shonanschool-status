import AppKit
import Foundation

// 新しい版のお知らせ（Mac 版）。
// Mac 版はインストーラーを配らず、各自がソースからビルドする（scripts/build-app.sh --install）。
// そのため自動で入れ替えはせず、GitHub の Releases（Lis-louis/shonanschool-status）に今より新しい版が出ていたら
// 画面の上に知らせ、「更新のしかた」で README の手順（git pull → ビルドし直す）を開くだけにする。
// Windows 版（windows/src/main/updater.js）と同じく、起動10秒後と3時間ごとに確認する。
// 送るのは GitHub への普通の問い合わせだけで、ID・パスワード・読み取った内容は送らない。

enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case available(version: String)

    var version: String? {
        if case .available(let v) = self { v } else { nil }
    }
}

/// Releases の中から、今より新しい版を選ぶ（テストできるよう、通信と切り離してある）
enum UpdateCheck {
    static let repository = "Lis-louis/shonanschool-status"
    static let releasesURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=15")!
    /// 「更新のしかた」で開くページ（README の Mac 版のアップデート）
    static let howToUpdateURL = URL(string: "https://github.com/\(repository)/blob/main/README.ja.md#mac-版")!

    struct Release: Decodable, Sendable {
        var tag_name: String
        var draft: Bool
        var prerelease: Bool
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

    /// 下書き・プレリリースを除いた、今より新しい最も新しい版
    static func pick(_ releases: [Release], current: String) -> String? {
        var best: String?
        for r in releases where !r.draft && !r.prerelease {
            guard let v = parse(r.tag_name).map({ $0.map(String.init).joined(separator: ".") }) else { continue }
            guard isNewer(v, than: current), best.map({ isNewer(v, than: $0) }) ?? true else { continue }
            best = v
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
    @ObservationIgnored private var busy = false

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
        if state == .checking || busy { return }
        busy = true
        defer { busy = false }
        let previous = state
        // すでにお知らせを出しているときは、確認中もそのまま出しておく
        if previous == .idle { state = .checking }
        do {
            var req = URLRequest(url: UpdateCheck.releasesURL, timeoutInterval: 30)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("CampusHub-mac", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http((resp as? HTTPURLResponse)?.statusCode ?? 0) }
            let releases = try JSONDecoder().decode([UpdateCheck.Release].self, from: data)
            guard let v = UpdateCheck.pick(releases, current: Self.currentVersion) else {
                state = .idle
                if manual { store?.toast = "最新のバージョン（\(Self.currentVersion)）です" }
                return
            }
            if previous.version != v { store?.diag("アプリ", "新しいバージョン \(v) が出ています") }
            state = .available(version: v)
            if manual {
                hiddenVersion = nil
                store?.toast = "新しいバージョン \(v) が出ています。画面の上の「更新のしかた」を見てください"
            }
        } catch {
            store?.diag("アプリ", "アップデートの確認に失敗: \(String(describing: error).prefix(200))", ok: false)
            if manual { store?.toast = "アップデートを確認できませんでした（インターネット接続を確認してください）" }
            state = previous
        }
    }

    /// 「更新のしかた」：README の手順をブラウザで開く
    func openHowToUpdate() {
        NSWorkspace.shared.open(UpdateCheck.howToUpdateURL)
    }
}

enum UpdateError: Error, CustomStringConvertible {
    case http(Int)
    var description: String {
        switch self {
        case .http(let c): "HTTP \(c)"
        }
    }
}
