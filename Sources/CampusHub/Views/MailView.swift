import SwiftUI

struct MailPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var filter: MailCategory?
    @State private var schoolOnly = true

    var body: some View {
        Page(title: "メール", subtitle: "大学のGmailを自動で仕分け") {
            SampleBanner()
            StateContent(state: store.mail, service: .moodle, notConfigured: AnyView(setupGuide)) { snap in
                summary(snap)
                TodoCard(onlySource: .mail)
                list(snap)
            }
        }
    }

    private var setupGuide: some View {
        Card(title: "Gmailとの連携", symbol: "envelope.badge") {
            StatusMessage(kind: .notConfigured, message: store.mail.notConfiguredMessage ?? "")
            Text("大学メールは Google Workspace（Gmail）です。Google公式のログイン（ブラウザ）で読み取り専用の許可を出すと、メールを取得して自動で仕分けます。")
                .font(.callout).foregroundStyle(p.subtle).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("設定を開く") { store.selection = .settings }.buttonStyle(PrimaryButtonStyle())
                Button("Gmailを開く") { if let u = SafeURL.https(store.config.mail.webURL) { NSWorkspace.shared.open(u) } }
                    .buttonStyle(SoftButtonStyle())
            }
        }
    }

    private func summary(_ snap: MailSnapshot) -> some View {
        let school = snap.messages.filter(\.isFromSchool)
        let counts = Dictionary(grouping: snap.messages, by: \.category).mapValues(\.count)
        return Card(title: "学校から届いていること", symbol: "sparkles", trailing: snap.email) {
            HStack(spacing: 16) {
                stat("\(school.count)", "大学から")
                stat("\(school.filter(\.unread).count)", "うち未読")
                stat("\(counts[.action] ?? 0)", "要対応", color: (counts[.action] ?? 0) > 0 ? p.alert : nil)
                stat("\(snap.messages.filter(\.looksOverdue).count)", "督促・未完了", color: snap.messages.contains(where: \.looksOverdue) ? p.alert : nil)
            }
            FlowChips(counts: counts, selected: $filter)
        }
    }

    private func stat(_ value: String, _ label: String, color: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color ?? p.accent)
            Text(label).font(.caption).foregroundStyle(p.subtle)
        }
        .frame(maxWidth: .infinity)
    }

    private func list(_ snap: MailSnapshot) -> some View {
        let items = snap.messages.filter { (filter == nil || $0.category == filter) && (!schoolOnly || $0.isFromSchool || $0.category == .moodle) }
        return Card(title: filter?.label ?? "メール一覧", symbol: filter?.symbol ?? "tray.full", trailing: "\(items.count)通") {
            Toggle("大学・Moodleからのメールだけ", isOn: $schoolOnly).toggleStyle(.switch).tint(p.accent).font(.callout)
            if items.isEmpty {
                StatusMessage(kind: .info, message: "該当するメールはありません。")
            } else {
                ForEach(items.prefix(80)) { MailRow(mail: $0) }
            }
            Text("検索条件：\(store.config.mail.searchQuery)").font(.caption2).foregroundStyle(p.subtle)
        }
    }
}

/// カテゴリの絞り込み
private struct FlowChips: View {
    @Environment(\.palette) private var p
    var counts: [MailCategory: Int]
    @Binding var selected: MailCategory?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, "すべて", counts.values.reduce(0, +))
                ForEach(MailCategory.allCases, id: \.self) { c in
                    if let n = counts[c], n > 0 { chip(c, c.label, n) }
                }
            }
        }
    }
    private func chip(_ c: MailCategory?, _ label: String, _ n: Int) -> some View {
        Button { selected = c } label: {
            Text("\(label) \(n)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(selected == c ? .white : (c == .action ? p.alert : p.accent))
                .background(selected == c ? (c == .action ? p.alert : p.accent) : p.tint, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct MailRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var mail: MailMessage
    @State private var expanded = false

    var body: some View {
        let color: Color = switch mail.category {
        case .action: p.alert
        case .classChange: p.warn
        default: p.accent2
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mail.category.symbol).foregroundStyle(color).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(mail.subject).font(.system(.callout, design: .rounded).weight(mail.unread ? .bold : .regular))
                            .foregroundStyle(p.ink).lineLimit(expanded ? nil : 1)
                        Spacer()
                        Text(mail.date.formatted(.dateTime.month().day().locale(jaLocale))).font(.caption).foregroundStyle(p.subtle)
                    }
                    HStack(spacing: 6) {
                        Text(mail.from).font(.caption).foregroundStyle(p.subtle).lineLimit(1)
                        if mail.unread { Chip(text: "未読", color: p.blush) }
                        if mail.looksOverdue { Chip(text: "督促・未完了？", color: p.alert) }
                        if let due = mail.dueDate { Chip(text: "期限 " + due.formatted(.dateTime.month().day().locale(jaLocale)), color: p.alert) }
                    }
                    Text(mail.snippet).font(.caption).foregroundStyle(p.subtle).lineLimit(expanded ? 6 : 1)
                    if expanded && !mail.reasons.isEmpty {
                        Text("仕分けの理由：" + mail.reasons.joined(separator: " / ")).font(.caption2).foregroundStyle(p.accent)
                    }
                }
            }
            if expanded {
                HStack {
                    Button("Gmailで開く") { if let u = store.gmailURL(for: mail) { NSWorkspace.shared.open(u) } }.buttonStyle(SoftButtonStyle())
                }.padding(.leading, 28)
            }
        }
        .padding(8)
        .background(mail.category == .action ? p.alert.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
    }
}

/// やること（Moodleの未完了＋メールの要対応）
struct TodoCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var onlySource: TodoItem.Source?
    var limit = 30
    /// ホーム：今週の分だけ（受付開始前・あと8日以上先は出さない）
    var thisWeek = false
    @State private var showDone = false

    var body: some View {
        let all = store.todos(includeDone: showDone, thisWeek: thisWeek).filter { onlySource == nil || $0.source == onlySource }
        let later = thisWeek ? store.todos(includeDone: showDone).filter { onlySource == nil || $0.source == onlySource }.count - all.count : 0
        let hot = all.filter { !store.doneIDs.contains($0.id) && ($0.overdueHint || ($0.due.map { $0 < .now.addingTimeInterval(86400) } ?? false)) }.count
        Card(title: onlySource == .mail ? "メールで見つけたやること" : "やること（まだできていないこと）", symbol: "checklist",
             tint: hot > 0 ? p.alert : nil, trailing: "\(all.count)件") {
            if hot > 0 {
                Label("期限切れ・督促・24時間以内が \(hot) 件", systemImage: "exclamationmark.circle.fill")
                    .font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(p.alert)
            }
            if all.isEmpty {
                StatusMessage(kind: .info, message: "今のところ、やることは見つかっていません。")
            }
            ForEach(all.prefix(limit)) { TodoRow(item: $0) }
            if later > 0 {
                Button { store.selection = .moodle; store.moodleMode = .summary } label: {
                    Label("あと8日以上先・受付開始前の課題 \(later)件は、Moodle の「課題・締切」で見られます", systemImage: "clock")
                        .font(.caption).foregroundStyle(p.subtle)
                }.buttonStyle(.plain)
            }
            Toggle("完了にしたものも表示", isOn: $showDone).toggleStyle(.switch).tint(p.accent).font(.caption)
        }
    }
}

struct TodoRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var item: TodoItem

    var body: some View {
        let done = store.doneIDs.contains(item.id)
        let overdue = item.overdueHint || (item.due.map { $0 < .now } ?? false)
        let soon = item.due.map { $0 < .now.addingTimeInterval(86400) } ?? false
        let color: Color = done ? p.subtle : overdue || soon ? p.alert : p.accent
        HStack(alignment: .top, spacing: 10) {
            Button { withAnimation { store.toggleDone(item.id) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(done ? .green : color)
            }
            .buttonStyle(.plain).help(done ? "未完了に戻す" : "完了にする")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: item.source == .moodle ? "book.closed" : "envelope").font(.caption).foregroundStyle(p.subtle)
                        Text(item.title).font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(done ? p.subtle : p.ink).strikethrough(done).multilineTextAlignment(.leading)
                    }
                    if let d = item.detail { Text(d).font(.caption).foregroundStyle(p.subtle).lineLimit(1) }
                    Text(item.reason).font(.caption2).foregroundStyle(overdue && !done ? p.alert : p.subtle)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer()
            if let due = item.due {
                VStack(alignment: .trailing, spacing: 2) {
                    Chip(text: remainingText(due), color: color)
                    Text(due.formatted(.dateTime.month().day().hour().minute().locale(jaLocale))).font(.caption2).foregroundStyle(p.subtle)
                }
            } else if item.overdueHint {
                Chip(text: "督促", color: p.alert)
            }
        }
        .opacity(done ? 0.6 : 1)
    }

    private func open() {
        switch item.source {
        case .moodle: store.openInApp(item.url, service: .moodle)
        case .mail: if let u = item.url { NSWorkspace.shared.open(u) }
        }
    }
}

extension LoadState {
    var notConfiguredMessage: String? { if case .notConfigured(let m) = self { m } else { nil } }
}
