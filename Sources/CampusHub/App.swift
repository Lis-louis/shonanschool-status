import AppKit
import SwiftUI

@main
struct CampusHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("キャンパスハブ") {
            RootView()
                .environment(store)
                .environment(\.locale, jaLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("更新") { Task { await store.refresh() } }.keyboardShortcut("r")
                Divider()
                // Windows 版と同じ ⌘1〜6 で画面を切り替える
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { store.selection = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("診断ログのフォルダを開く") { NSWorkspace.shared.activateFileViewerSelecting([DiagFile.url]) }
            }
            CommandGroup(after: .appInfo) {
                Button("アップデートを確認…") { Task { await store.updater.check(manual: true) } }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` で起動したときも通常のアプリとして前面に出す
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// ウィンドウを閉じてもドックから再び開けるよう、終了しない
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = scheme == .dark ? Palette.night : Palette.day
        GeometryReader { geo in
            HStack(spacing: 0) {
                Sidebar(compact: geo.size.width < 720)
                ZStack(alignment: .bottom) {
                    DreamyBackground()
                    Group {
                        switch store.selection {
                        case .home: HomeView()
                        case .calendar: CalendarPage()
                        case .moodle: MoodlePage()
                        case .campusSquare: CampusPage()
                        case .mail: MailPage()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if store.updater.showsBanner { UpdateBanner().padding(.horizontal, 16).padding(.top, 30) }
                    }
                    if let t = store.toast { Toast(text: t) { store.toast = nil } }
                }
            }
        }
        .environment(\.palette, palette)
        .foregroundStyle(palette.ink)
        .background(palette.background)
        .frame(minWidth: 400, minHeight: 560)
        .task {
            // 起動時に開く画面（例: open -a キャンパスハブ --args --section calendar）
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--section"), i + 1 < args.count, let s = AppSection(rawValue: args[i + 1]) {
                store.selection = s
            }
            store.updater.start()
            await store.refresh()
        }
    }
}

/// 画面の上に出す「新しいバージョン」の知らせ（Windows 版の updateBanner と同じ）
struct UpdateBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p

    var body: some View {
        let u = store.updater
        HStack(spacing: 10) {
            switch u.state {
            case .downloading(let v, let percent):
                ProgressView().controlSize(.small)
                Text("新しいバージョン \(v) をダウンロード中…（\(percent)%）").frame(maxWidth: .infinity, alignment: .leading)
                Button { u.hiddenVersion = v } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(p.subtle).help("閉じる")
            case .ready(let v, _):
                Image(systemName: "sparkles").foregroundStyle(p.accent)
                Text("新しいバージョン \(v) の準備ができました。「更新する」を押すとインストーラーが開きます（キャンパスハブは一度閉じます）")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { u.install() } label: { Label("更新する", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("あとで") { u.hiddenVersion = v }.buttonStyle(SoftButtonStyle())
            default:
                EmptyView()
            }
        }
        .font(.system(.callout, design: .rounded))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(p.line))
        .shadow(color: p.accent.opacity(0.12), radius: 10, y: 4)
        .frame(maxWidth: 632)
    }
}

struct Sidebar: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var compact: Bool

    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 30)
            SuzuFace(image: Artwork.image(store.isRefreshing ? "face_calm" : "face_smile"), size: compact ? 40 : 84)
            if !compact {
                VStack(spacing: 2) {
                    Text("キャンパスハブ").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(store.isRefreshing ? "読み込み中…" : store.config.universityName)
                        .font(.system(.caption, design: .rounded)).foregroundStyle(p.subtle)
                }
            }
            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { s in
                    Button { withAnimation(.easeOut(duration: 0.15)) { store.selection = s } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.icon).frame(width: 20)
                            if !compact {
                                Text(s.title)
                                Spacer()
                                if let n = badge(for: s) {
                                    Text("\(n)").font(.caption2.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2).background(p.blush, in: Capsule())
                                }
                            }
                        }
                        .font(.system(.body, design: .rounded).weight(store.selection == s ? .semibold : .regular))
                        .padding(.horizontal, compact ? 10 : 14).padding(.vertical, 9)
                        .foregroundStyle(store.selection == s ? p.accent : p.ink.opacity(0.8))
                        .background(store.selection == s ? p.tint : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(s.title)
                }
            }
            .padding(.horizontal, compact ? 8 : 12).padding(.top, 6)
            Spacer()
        }
        .frame(width: compact ? 64 : 220)
        .background(
            LinearGradient(colors: [p.card, p.tint.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .trailing) { Rectangle().fill(p.line).frame(width: 1) }
                .ignoresSafeArea()
        )
    }

    private func badge(for s: AppSection) -> Int? {
        switch s {
        case .moodle:
            let n = (store.moodle.value?.deadlines ?? []).filter { [.overdue, .urgent].contains($0.urgency()) }.count
            return n > 0 ? n : nil
        case .campusSquare:
            let n = (store.campus.value?.cancellations?.rows.count ?? 0)
            return n > 0 ? n : nil
        case .mail:
            let n = store.todos().filter { $0.source == .mail }.count
            return n > 0 ? n : nil
        default: return nil
        }
    }
}

struct Toast: View {
    @Environment(\.palette) private var p
    var text: String
    var close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(p.accent)
            Text(text).font(.system(.callout, design: .rounded))
            Button { close() } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).foregroundStyle(p.subtle)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(p.card, in: Capsule())
        .overlay(Capsule().stroke(p.line))
        .shadow(color: p.accent.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 18)
        .task(id: text) { try? await Task.sleep(for: .seconds(5)); close() }
    }
}
