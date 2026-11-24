import SwiftUI
import WebKit

let jaLocale = Locale(identifier: "ja_JP")

/// スマートフォン幅を基準にした縦1列のページ
struct Page<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    PageTitle(title: title, subtitle: subtitle)
                    Spacer()
                    RefreshButton()
                }
                content
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 26)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

struct RefreshButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        Button { Task { await store.refresh() } } label: {
            HStack(spacing: 6) {
                if store.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                Text(store.isRefreshing ? "更新中" : "更新")
            }
        }
        .buttonStyle(SoftButtonStyle())
        .disabled(store.isRefreshing)
        .help("最新の情報に更新（⌘R）")
    }
}

enum MessageKind { case loading, notConfigured, error, info }

struct StatusMessage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var kind: MessageKind
    var message: String
    var retry: Bool = false
    var settings: Bool = false
    var loginService: PortalService?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch kind {
            case .loading: ProgressView().controlSize(.small)
            case .notConfigured: Image(systemName: "person.badge.key").foregroundStyle(p.accent2)
            case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(p.warn)
            case .info: Image(systemName: "leaf").foregroundStyle(p.accent2)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.system(.callout, design: .rounded))
                    .foregroundStyle(kind == .error ? p.ink : p.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                if retry || settings || loginService != nil {
                    HStack(spacing: 8) {
                        if retry { Button("再試行") { Task { await store.refresh() } }.buttonStyle(SoftButtonStyle()) }
                        if settings { Button("設定を開く") { store.selection = .settings }.buttonStyle(SoftButtonStyle()) }
                        if let s = loginService {
                            Button("ブラウザでログイン") { store.openInApp(store.config.startURL(for: s), service: s) }.buttonStyle(SoftButtonStyle())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 読み込み中・未連携・エラーをまとめて表示
struct StateContent<Value: Sendable, Content: View>: View {
    var state: LoadState<Value>
    var service: PortalService?
    /// 未連携のときに出す独自の案内（メールなど）
    var notConfigured: AnyView?
    @ViewBuilder var content: (Value) -> Content

    init(state: LoadState<Value>, service: PortalService?, notConfigured: AnyView? = nil, @ViewBuilder content: @escaping (Value) -> Content) {
        self.state = state; self.service = notConfigured == nil ? service : nil
        self.notConfigured = notConfigured; self.content = content
    }

    var body: some View {
        switch state {
        case .loading: StatusMessage(kind: .loading, message: "\(service?.label ?? "メール")から読み込み中…")
        case .notConfigured(let m):
            if let notConfigured { notConfigured }
            else { StatusMessage(kind: .notConfigured, message: m, settings: true, loginService: service) }
        case .failed(let m): StatusMessage(kind: .error, message: m, retry: true, loginService: service)
        case .loaded(let v): content(v)
        }
    }
}

/// 行として並べるボタン（アプリ内 or 既定のブラウザで開く）
struct LinkRow: View {
    @Environment(\.palette) private var p
    var title: String
    var subtitle: String?
    var symbol: String
    var external = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 26, height: 26).foregroundStyle(p.accent)
                    .background(p.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(.body, design: .rounded)).foregroundStyle(p.ink)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(p.subtle) }
                }
                Spacer()
                Image(systemName: external ? "arrow.up.right.square" : "chevron.right").font(.caption).foregroundStyle(p.subtle)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

struct DeadlineRow: View {
    @Environment(\.palette) private var p
    var deadline: Deadline
    var action: () -> Void

    var body: some View {
        let u = deadline.status.isDone ? .normal : deadline.urgency()
        let base: Color = switch u { case .overdue, .urgent: p.alert; case .soon: p.warn; case .normal: p.accent2 }
        let color: Color = deadline.status.isDone ? .green : base
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(color).frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(deadline.title).font(.system(.body, design: .rounded).weight(u == .normal ? .regular : .semibold))
                        .foregroundStyle(p.ink).multilineTextAlignment(.leading)
                    if let course = deadline.course, !course.isEmpty {
                        Text(course).font(.caption).foregroundStyle(p.subtle).lineLimit(1)
                    }
                    Text(deadline.due.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute().locale(jaLocale))
                         + (deadline.needsAction ? "" : "（提出済みかは未確認）"))
                        .font(.caption).foregroundStyle(p.subtle)
                }
                Spacer()
                if let label = deadline.status.label {
                    Chip(text: label, symbol: deadline.status.isDone ? "checkmark.circle.fill" : deadline.status == .notOpenYet ? "clock" : "questionmark.circle",
                         color: deadline.status.isDone ? .green : deadline.status == .notOpenYet ? p.subtle : p.warn)
                } else {
                    Chip(text: remainingText(deadline.due), color: u == .normal ? p.accent : color)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func remainingText(_ date: Date, now: Date = .now) -> String {
    let s = date.timeIntervalSince(now)
    if s < 0 { return "期限切れ" }
    if s < 3600 { return "あと\(max(1, Int(s / 60)))分" }
    if s < 86400 { return "あと\(Int(s / 3600))時間" }
    return "あと\(Int(s / 86400))日"
}

/// 時間割の1コマ（1行目＝科目名、2行目以降＝担当・教室など）。
/// day を渡すと対応する Moodle のコースを探し、見つかれば押すとそのコースをアプリ内で開く。
/// 見つからないとき（Moodle に登録されていない・名前が大きく違う）は、押すと Moodle のコース検索を科目名で開く
struct ClassCell: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var period: String
    var text: String
    var day: String? = nil

    var body: some View {
        let course = day.flatMap { d in
            Timetable.moodleCourse(in: store.moodle.value?.courses ?? [], text: text, day: d, period: period)
        }
        if let course {
            Button { store.openInApp(course.url, service: .moodle) } label: { cell(linked: true) }
                .buttonStyle(.plain)
                .help("Moodleの「\(course.fullName)」を開く")
        } else if day != nil, let search = Timetable.searchURL(base: store.config.moodleBaseURL, text: text) {
            Button { store.openInApp(search, service: .moodle) } label: { cell(linked: true, search: true) }
                .buttonStyle(.plain)
                .help("対応するコースが見つからないので、Moodle で「\(Timetable.split(text).title)」を検索します")
        } else {
            cell(linked: false)
        }
    }

    private func cell(linked: Bool, search: Bool = false) -> some View {
        let parts = Timetable.split(text)
        let important = Importance.isImportant(text)
        return HStack(alignment: .top, spacing: 12) {
            Text(period).font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(p.accent)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(parts.title).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(p.ink)
                    if text.contains("休講") { Chip(text: "休講", color: p.alert) }
                    else if text.contains("教室変更") { Chip(text: "教室変更", color: p.warn) }
                }
                ForEach(Array(parts.rest.prefix(3).enumerated()), id: \.offset) { _, l in
                    Text(l).font(.caption).foregroundStyle(p.subtle)
                }
                if let code = parts.code { Text(code).font(.caption2.monospaced()).foregroundStyle(p.subtle.opacity(0.7)) }
            }
            Spacer(minLength: 0)
            if linked {
                Label(search ? "Moodleで探す" : "Moodle", systemImage: search ? "magnifyingglass" : "book.closed")
                    .font(.caption2).foregroundStyle(search ? p.subtle : p.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((search ? p.subtle : p.accent).opacity(0.12), in: Capsule())
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(10)
        .background(important ? p.alert.opacity(0.08) : p.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// ポータルの1行（重要語を含む行は目立たせる）
struct NoticeLine: View {
    @Environment(\.palette) private var p
    var text: String
    var body: some View {
        let important = Importance.isImportant(text)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(important ? p.alert : p.accent2).frame(width: 6, height: 6)
            Text(text).font(.system(.callout, design: .rounded).weight(important ? .semibold : .regular))
                .foregroundStyle(important ? p.alert : p.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SampleBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var body: some View {
        if store.prefs.useSampleData {
            Label("サンプルデータを表示中です（実際の情報ではありません）", systemImage: "theatermasks")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(p.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.blush.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct Warnings: View {
    var items: [String]
    var body: some View {
        ForEach(items, id: \.self) { StatusMessage(kind: .error, message: $0) }
    }
}

// MARK: - アプリ内ブラウザ

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct BrowserPane: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var controller: BrowserController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { controller.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!controller.canGoBack)
                Button { controller.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!controller.canGoForward)
                Button { controller.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { controller.load(store.config.startURL(for: controller.service) ?? URL(string: "about:blank")!) } label: { Image(systemName: "house") }
                    .help("トップへ")
                VStack(alignment: .leading, spacing: 0) {
                    Text(controller.title.isEmpty ? controller.service.label : controller.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold)).lineLimit(1)
                    Text(controller.currentURL?.host() ?? "").font(.caption2).foregroundStyle(p.subtle).lineLimit(1)
                }
                .padding(.horizontal, 6)
                Spacer()
                if controller.isLoading { ProgressView().controlSize(.small) }
                Button { Task { await controller.fillCredentialsNow() } } label: { Image(systemName: "key.fill") }
                    .help("保存したID・パスワードでログイン")
                Menu {
                    if controller.service == .campus, let url = controller.currentURL {
                        Button("このページを「時間割」に設定") { setCampus(\.timetable, url) }
                        Button("このページを「休講・補講」に設定") { setCampus(\.cancellations, url) }
                        Button("このページを「成績」に設定") { setCampus(\.grades, url) }
                        Divider()
                    }
                    Button("既定のブラウザで開く") { if let u = controller.currentURL { NSWorkspace.shared.open(u) } }
                    Button("URLをコピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(controller.currentURL?.absoluteString ?? "", forType: .string)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(p.card.opacity(0.9))
            .overlay(alignment: .bottom) { Rectangle().fill(p.line).frame(height: 1) }

            if let msg = controller.message {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(p.accent)
                    Text(msg).font(.system(.caption, design: .rounded))
                    Spacer()
                    Button { controller.message = nil } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(p.tint)
                .task(id: msg) { try? await Task.sleep(for: .seconds(6)); if controller.message == msg { controller.message = nil } }
            }
            WebViewHost(webView: controller.webView)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(p.line))
        .padding(12)
        .onAppear { controller.loadIfNeeded(store.config.startURL(for: controller.service)) }
    }

    private func setCampus(_ key: WritableKeyPath<CampusSquareURLs, String>, _ url: URL) {
        store.config.campusSquare[keyPath: key] = SafeURL.stableCampusURL(url)
        store.toast = "設定しました。次の更新から反映されます"
    }
}

/// まとめ / ブラウザ の切り替え
struct ModeSwitch: View {
    @Binding var mode: ViewMode
    var body: some View {
        Picker("", selection: $mode) {
            Label("まとめ", systemImage: "sparkles.rectangle.stack").tag(ViewMode.summary)
            Label("ブラウザ", systemImage: "globe").tag(ViewMode.browser)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
        .padding(.top, 14)
    }
}
