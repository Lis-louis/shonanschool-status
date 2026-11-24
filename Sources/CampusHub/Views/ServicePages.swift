import SwiftUI

struct MoodlePage: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            ModeSwitch(mode: $store.moodleMode)
            if store.moodleMode == .summary { MoodleSummary() } else { BrowserPane(controller: store.moodleBrowser) }
        }
    }
}

struct MoodleSummary: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p

    var body: some View {
        let c = store.config
        Page(title: "Moodle", subtitle: "コース・課題・教材") {
            SampleBanner()
            Card(title: "課題・締切", symbol: "flag", trailing: "過去7日〜\(store.prefs.deadlineWindowDays)日後") {
                StateContent(state: store.moodle, service: .moodle) { snap in
                    let open = snap.deadlines.filter { !$0.status.isDone }
                    let done = snap.deadlines.filter(\.status.isDone)
                    if open.isEmpty {
                        StatusMessage(kind: .info, message: "提出が必要な課題はありません。")
                    } else {
                        ForEach(open) { d in
                            DeadlineRow(deadline: d) { store.openInApp(d.url ?? c.moodleUpcoming, service: .moodle) }
                        }
                    }
                    if !done.isEmpty {
                        DisclosureGroup("提出済み・回答済み（\(done.count)件）") {
                            ForEach(done) { d in
                                DeadlineRow(deadline: d) { store.openInApp(d.url ?? c.moodleUpcoming, service: .moodle) }
                            }
                        }
                        .font(.system(.callout, design: .rounded)).foregroundStyle(p.subtle)
                    }
                    Warnings(items: snap.warnings)
                }
            }

            if let snap = store.moodle.value, !snap.notices.isEmpty {
                // 提出済み・回答済みの課題についての通知（「提出期限 …」など）は、一覧から外して下にまとめる
                let active = snap.notices.filter { !$0.status.isDone }
                let done = snap.notices.filter(\.status.isDone)
                Card(title: "通知", symbol: "bell", trailing: snap.unreadCount > 0 ? "未読 \(snap.unreadCount)" : nil) {
                    if active.isEmpty {
                        StatusMessage(kind: .info, message: "提出が必要な課題の通知はありません。")
                    }
                    ForEach(active.prefix(10)) { n in noticeRow(n) }
                    if !done.isEmpty {
                        DisclosureGroup("提出済み・回答済みの課題の通知（\(done.count)件）") {
                            ForEach(done) { n in noticeRow(n) }
                        }
                        .font(.system(.callout, design: .rounded)).foregroundStyle(p.subtle)
                    }
                }
            }

            Card(title: "コース（教材）", symbol: "books.vertical") {
                StateContent(state: store.moodle, service: .moodle) { snap in
                    // もう受けていないコースは「非表示」で一覧から外せる（下の「非表示にしたコース」から戻せる）
                    let shown = snap.courses.filter { !store.hiddenCourseIDs.contains($0.id) }
                    let hidden = snap.courses.filter { store.hiddenCourseIDs.contains($0.id) }
                    if snap.courses.isEmpty {
                        StatusMessage(kind: .info, message: "受講中のコースはありません。")
                    } else if shown.isEmpty {
                        StatusMessage(kind: .info, message: "すべてのコースを非表示にしています。下の「非表示にしたコース」から戻せます。")
                    } else {
                        ForEach(shown) { course in courseRow(course, hidden: false) }
                    }
                    if !hidden.isEmpty {
                        DisclosureGroup("非表示にしたコース（\(hidden.count)件）") {
                            ForEach(hidden) { course in courseRow(course, hidden: true) }
                        }
                        .font(.system(.callout, design: .rounded)).foregroundStyle(p.subtle)
                    } else if !snap.courses.isEmpty {
                        Text("もう受けていないコースは、右の「非表示」で一覧から外せます（あとで戻せます）。")
                            .font(.caption).foregroundStyle(p.subtle)
                    }
                }
            }

            Card(title: "Moodleのページ", symbol: "safari") {
                LinkRow(title: "ダッシュボード", symbol: "rectangle.grid.2x2") { store.openInApp(c.moodleDashboard, service: .moodle) }
                LinkRow(title: "マイコース", symbol: "books.vertical") { store.openInApp(c.moodleCourses, service: .moodle) }
                LinkRow(title: "今後の予定（カレンダー）", symbol: "calendar.badge.clock") { store.openInApp(c.moodleUpcoming, service: .moodle) }
                LinkRow(title: "通知一覧", symbol: "bell") { store.openInApp(c.moodleNotifications, service: .moodle) }
            }
        }
    }

    private func courseRow(_ course: Course, hidden: Bool) -> some View {
        HStack(spacing: 8) {
            Button { store.openInApp(course.url, service: .moodle) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(course.fullName).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(p.ink)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(p.subtle)
                    }
                    if let cat = course.category, !cat.isEmpty { Text(cat).font(.caption).foregroundStyle(p.subtle) }
                    if !hidden, let prog = course.progress {
                        HStack { SoftBar(value: prog / 100); Text("\(Int(prog))%").font(.caption2).foregroundStyle(p.subtle) }
                    }
                }
                .padding(10)
                .background(p.tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .opacity(hidden ? 0.65 : 1)
            }.buttonStyle(.plain)
            Button { store.setCourseHidden(course.id, !hidden) } label: {
                VStack(spacing: 2) {
                    Image(systemName: hidden ? "eye" : "eye.slash").font(.body)
                    Text(hidden ? "戻す" : "非表示").font(.caption2)
                }
                .foregroundStyle(hidden ? p.accent : p.subtle)
                .frame(minWidth: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hidden ? "このコースを一覧に戻す" : "このコースを一覧から外す（あとで戻せます）")
        }
    }

    private func noticeRow(_ n: MoodleNotice) -> some View {
        Button { store.openInApp(n.url ?? store.config.moodleNotifications, service: .moodle) } label: {
            HStack(alignment: .top) {
                NoticeLine(text: n.subject).opacity(n.read ? 0.6 : 1)
                Spacer()
                Text(n.time.formatted(.dateTime.month().day().locale(jaLocale))).font(.caption).foregroundStyle(p.subtle)
            }
        }.buttonStyle(.plain)
    }
}

struct CampusPage: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            ModeSwitch(mode: $store.campusMode)
            if store.campusMode == .summary { CampusSummary() } else { BrowserPane(controller: store.campusBrowser) }
        }
    }
}

struct CampusSummary: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var day = Timetable.dayChar(for: .now)

    var body: some View {
        let cs = store.config.campusSquare
        Page(title: "Campus Square", subtitle: "時間割・休講・お知らせ") {
            SampleBanner()
            Card(title: "時間割", symbol: "tablecells") {
                StateContent(state: store.campus, service: .campus) { snap in
                    if let tt = snap.timetable {
                        Picker("曜日", selection: $day) {
                            ForEach(tt.days, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        let list = tt.classes(on: day)
                        if list.isEmpty {
                            StatusMessage(kind: .info, message: "\(day)曜日の授業はありません。")
                        } else {
                            ForEach(Array(list.enumerated()), id: \.offset) { _, c in ClassCell(period: c.period, text: c.text) }
                        }
                    } else {
                        StatusMessage(kind: .info, message: "時間割の表を見つけられませんでした。「ブラウザ」で時間割のページを開き、右上の「…」から「このページを時間割に設定」を選んでください。")
                    }
                    Warnings(items: snap.warnings)
                }
            }

            if let table = store.campus.value?.cancellations, !table.rows.isEmpty {
                Card(title: table.title?.isEmpty == false ? table.title! : "休講・補講", symbol: "exclamationmark.bubble", tint: p.alert) {
                    ForEach(Array(table.rows.prefix(30).enumerated()), id: \.offset) { _, row in
                        TableRowCard(header: table.header, row: row)
                    }
                }
            }

            if let portlets = store.campus.value?.portlets {
                ForEach(portlets) { PortletCard(portlet: $0) }
            }

            Card(title: "Campus Squareのページ", symbol: "safari") {
                LinkRow(title: "ポータル（トップ）", symbol: "house") { store.openInApp(SafeURL.https(cs.portal), service: .campus) }
                LinkRow(title: "時間割・履修", symbol: "tablecells") { store.openInApp(SafeURL.https(cs.timetable), service: .campus) }
                LinkRow(title: "休講・補講・教室変更", symbol: "exclamationmark.bubble") { store.openInApp(SafeURL.https(cs.cancellations), service: .campus) }
                LinkRow(title: "成績", symbol: "chart.bar") { store.openInApp(SafeURL.https(cs.grades), service: .campus) }
                LinkRow(title: "シラバス", symbol: "text.book.closed") { store.openInApp(SafeURL.https(cs.syllabus), service: .campus) }
                LinkRow(title: "出席管理", subtitle: SafeURL.https(cs.attendance)?.host(), symbol: "checkmark.circle", external: true) {
                    if let u = SafeURL.https(cs.attendance) { NSWorkspace.shared.open(u) }
                }
            }
        }
    }
}

struct PortletCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var portlet: Portlet
    @State private var expanded = false

    var body: some View {
        let hasImportant = portlet.lines.contains(where: Importance.isImportant)
        Card(title: portlet.title, symbol: "megaphone", tint: hasImportant ? p.alert : nil) {
            ForEach(Array(portlet.lines.prefix(expanded ? 40 : 6).enumerated()), id: \.offset) { _, l in NoticeLine(text: l) }
            HStack {
                if portlet.lines.count > 6 {
                    Button(expanded ? "閉じる" : "もっと見る（\(portlet.lines.count)行）") { withAnimation { expanded.toggle() } }
                        .buttonStyle(SoftButtonStyle())
                }
                Button("ポータルで開く") { store.openInApp(SafeURL.https(store.config.campusSquare.portal), service: .campus) }
                    .buttonStyle(SoftButtonStyle())
            }
        }
    }
}

struct TableRowCard: View {
    @Environment(\.palette) private var p
    var header: [String]
    var row: [String]
    var body: some View {
        let text = row.joined(separator: " ")
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(row.enumerated()), id: \.offset) { i, v in
                if !v.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(i < header.count ? header[i] : "").font(.caption).foregroundStyle(p.subtle).frame(width: 64, alignment: .leading)
                        Text(v).font(.system(.callout, design: .rounded)).foregroundStyle(p.ink)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Importance.isImportant(text) ? p.alert.opacity(0.08) : p.tint.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

