import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                SampleBanner()
                if store.prefs.showTodayClasses { todayClasses }
                if store.prefs.showDeadlines { todo }
                if store.prefs.showNotices { notices }
                if store.prefs.showMail { mail }
                if let updated = store.lastUpdated {
                    Text("最終更新 " + updated.formatted(.dateTime.hour().minute().locale(jaLocale)))
                        .font(.caption).foregroundStyle(p.subtle).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: "おはようございます"
        case 11..<17: "こんにちは"
        default: "こんばんは"
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = Artwork.image(scheme == .dark ? "hero_night" : "hero_day") {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(height: 170).frame(maxWidth: .infinity).clipped()
            } else {
                p.tint.frame(height: 170)
            }
            LinearGradient(colors: [.clear, p.ink.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(.system(.callout, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(jaLocale)))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(store.config.universityName).font(.system(.caption, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                RefreshButton()
            }
            .padding(16)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: p.accent.opacity(0.18), radius: 16, y: 8)
    }

    private var todayClasses: some View {
        let day = Timetable.dayChar(for: .now)
        return Card(title: "今日の授業", symbol: "clock", trailing: "\(day)曜日") {
            StateContent(state: store.campus, service: .campus) { snap in
                if let tt = snap.timetable {
                    let today = tt.classes(on: day)
                    if today.isEmpty {
                        StatusMessage(kind: .info, message: "今日の授業はありません。ゆっくり休んでね。")
                    } else {
                        ForEach(Array(today.enumerated()), id: \.offset) { _, c in ClassCell(period: c.period, text: c.text) }
                    }
                } else {
                    StatusMessage(kind: .info, message: "時間割を読み取れていません。Campus Squareのページで確認してください。")
                }
            }
            Button("Campus Squareの時間割へ") { store.openInApp(SafeURL.https(store.config.campusSquare.timetable), service: .campus) }
                .buttonStyle(SoftButtonStyle())
        }
    }

    private var todo: some View {
        Group {
            switch (store.moodle, store.mail) {
            case (.loading, _), (_, .loading) where store.todos().isEmpty:
                Card(title: "やること（まだできていないこと）", symbol: "checklist") {
                    StatusMessage(kind: .loading, message: "Moodleとメールから読み込み中…")
                }
            default:
                VStack(spacing: 8) {
                    TodoCard(limit: 6)
                    if case .failed(let m) = store.moodle { StatusMessage(kind: .error, message: "Moodle：" + m, retry: true, loginService: .moodle) }
                    if case .notConfigured(let m) = store.moodle { StatusMessage(kind: .notConfigured, message: "Moodle：" + m, settings: true, loginService: .moodle) }
                }
            }
        }
    }

    private var notices: some View {
        Card(title: "大学からのお知らせ", symbol: "megaphone") {
            if let m = store.moodle.value, !m.notices.isEmpty {
                HStack {
                    Text("Moodleの通知").font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(p.ink)
                    if m.unreadCount > 0 { Chip(text: "未読 \(m.unreadCount)", color: p.blush) }
                }
                ForEach(m.notices.prefix(3)) { n in
                    Button { store.openInApp(n.url ?? store.config.moodleNotifications, service: .moodle) } label: {
                        NoticeLine(text: n.subject).opacity(n.read ? 0.6 : 1)
                    }.buttonStyle(.plain)
                }
            }
            StateContent(state: store.campus, service: .campus) { snap in
                let important = snap.portlets.flatMap(\.lines).filter(Importance.isImportant)
                let cancelRows = (snap.cancellations?.rows ?? []).map { $0.filter { !$0.isEmpty }.joined(separator: " ") }
                if important.isEmpty && cancelRows.isEmpty && snap.portlets.isEmpty {
                    StatusMessage(kind: .info, message: "新しいお知らせは見つかりませんでした。")
                } else {
                    Text("Campus Square").font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(p.ink)
                    ForEach(Array((cancelRows.prefix(3) + important.prefix(5)).enumerated()), id: \.offset) { _, l in NoticeLine(text: l) }
                    if important.isEmpty && cancelRows.isEmpty {
                        ForEach(Array(snap.portlets.flatMap(\.lines).prefix(4).enumerated()), id: \.offset) { _, l in NoticeLine(text: l) }
                    }
                    Button("Campus Squareのお知らせを見る") { store.selection = .campusSquare; store.campusMode = .summary }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    private var mail: some View {
        Card(title: "大学メール", symbol: "envelope", trailing: store.mail.value.map { "未読 \($0.unreadCount)" }) {
            StateContent(state: store.mail, service: nil,
                         notConfigured: AnyView(StatusMessage(kind: .notConfigured, message: store.mail.notConfiguredMessage ?? "", settings: true))) { snap in
                let school = snap.messages.filter { $0.isFromSchool && ($0.unread || $0.category == .action || $0.category == .classChange) }
                if school.isEmpty {
                    StatusMessage(kind: .info, message: "大学からの未読・要対応メールはありません。")
                } else {
                    Text("学校から届いていること").font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(p.ink)
                    ForEach(school.prefix(4)) { MailRow(mail: $0) }
                }
                Button("メールをすべて見る") { store.selection = .mail }.buttonStyle(SoftButtonStyle())
            }
        }
    }
}
