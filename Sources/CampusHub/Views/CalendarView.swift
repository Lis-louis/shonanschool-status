import SwiftUI

/// 月のカレンダー：授業（毎週の時間割）・Moodleの予定・締切・メールの期限をまとめて表示
struct CalendarPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!
    @State private var selected = Calendar.current.startOfDay(for: .now)

    private var cal: Calendar { Calendar.current }

    var body: some View {
        @Bindable var store = store
        Page(title: "カレンダー", subtitle: "授業・課題・予定") {
            Card {
                header
                weekdayHeader
                grid
                legend
                if let err = store.monthErrors[AppStore.monthKey(month)] {
                    StatusMessage(kind: .error, message: "Moodleの予定を読み込めませんでした：\(err)", retry: true)
                }
            }
            dayDetail
            Toggle("毎週の時間割をカレンダーに表示する（祝日・休暇は反映されません）", isOn: $store.prefs.showTimetableInCalendar)
                .toggleStyle(.switch).font(.system(.caption, design: .rounded)).foregroundStyle(p.subtle).tint(p.accent)
        }
        .task(id: AppStore.monthKey(month)) { await store.loadMonth(month) }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SoftButtonStyle())
            Spacer()
            VStack(spacing: 0) {
                Text(month.formatted(.dateTime.year().month(.wide).locale(jaLocale)))
                    .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(p.ink)
                if store.monthLoading.contains(AppStore.monthKey(month)) {
                    Text("Moodleの予定を読み込み中…").font(.caption2).foregroundStyle(p.subtle)
                }
            }
            Spacer()
            Button("今日") {
                month = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
                selected = cal.startOfDay(for: .now)
            }.buttonStyle(SoftButtonStyle())
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SoftButtonStyle())
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(Timetable.weekdayChars.enumerated()), id: \.offset) { i, d in
                Text(d).font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(i == 0 ? p.alert : i == 6 ? p.accent : p.subtle)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var days: [Date?] {
        let first = month
        let offset = cal.component(.weekday, from: first) - 1
        let count = cal.range(of: .day, in: .month, for: first)!.count
        var out: [Date?] = Array(repeating: nil, count: offset)
        for d in 0..<count { out.append(cal.date(byAdding: .day, value: d, to: first)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    private var grid: some View {
        let cells = days
        return VStack(spacing: 4) {
            ForEach(0..<(cells.count / 7), id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        if let day = cells[row * 7 + col] { DayCell(day: day, selected: cal.isDate(day, inSameDayAs: selected)) { selected = day } }
                        else { Color.clear.frame(maxWidth: .infinity).frame(height: 52) }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendDot(color: p.accent2, text: "授業")
            LegendDot(color: p.mint, text: "予定")
            LegendDot(color: p.alert, text: "締切")
            LegendDot(color: p.blush, text: "メール")
        }
        .font(.caption2)
        .frame(maxWidth: .infinity)
    }

    private var dayDetail: some View {
        let items = store.calendarItems(on: selected)
        return Card(title: selected.formatted(.dateTime.month().day().weekday(.wide).locale(jaLocale)), symbol: "calendar.day.timeline.left",
                    trailing: items.isEmpty ? nil : "\(items.count)件") {
            if items.isEmpty {
                StatusMessage(kind: .info, message: "予定はありません。")
            } else {
                ForEach(items) { CalendarRow(item: $0) }
            }
        }
    }

    private func shift(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month)!
        selected = month
    }
}

private struct LegendDot: View {
    @Environment(\.palette) private var p
    var color: Color
    var text: String
    var body: some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(text).foregroundStyle(p.subtle) }
    }
}

private struct DayCell: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var day: Date
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let items = store.calendarItems(on: day)
        let today = Calendar.current.isDateInToday(day)
        let kinds = Set(items.map(\.kind))
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(.callout, design: .rounded).weight(today ? .bold : .regular))
                    .foregroundStyle(selected ? .white : today ? p.accent : p.ink)
                    .frame(width: 28, height: 28)
                    .background(selected ? p.accent : today ? p.tint : .clear, in: Circle())
                HStack(spacing: 3) {
                    if kinds.contains(.classSession) { Circle().fill(p.accent2).frame(width: 5, height: 5) }
                    if kinds.contains(.moodleEvent) { Circle().fill(p.mint).frame(width: 5, height: 5) }
                    if kinds.contains(.deadline) { Circle().fill(p.alert).frame(width: 5, height: 5) }
                    if kinds.contains(.mail) { Circle().fill(p.blush).frame(width: 5, height: 5) }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(selected ? p.tint.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CalendarRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.palette) private var p
    var item: CalendarItem

    var body: some View {
        let color: Color = switch item.kind {
        case .classSession: p.accent2
        case .moodleEvent: p.mint
        case .deadline: p.alert
        case .mail: p.blush
        }
        let label: String = switch item.kind {
        case .classSession: item.periodLabel ?? "授業"
        case .moodleEvent, .deadline, .mail: item.allDay ? "終日" : item.start.formatted(.dateTime.hour().minute().locale(jaLocale))
        }
        Button(action: open) {
            HStack(alignment: .top, spacing: 10) {
                Text(label).font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(color)
                    .frame(width: 46, alignment: .leading)
                Capsule().fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.title).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(p.ink)
                            .multilineTextAlignment(.leading)
                        if item.kind == .deadline { Chip(text: "締切", color: p.alert) }
                        if item.kind == .mail { Chip(text: "メールの期限", color: p.blush) }
                        if item.title.contains("休講") { Chip(text: "休講", color: p.alert) }
                    }
                    if let c = item.course { Text(c).font(.caption).foregroundStyle(p.subtle).lineLimit(1) }
                    if let l = item.location { Label(l, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(p.subtle) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open() {
        switch item.kind {
        case .mail: if let u = item.url { NSWorkspace.shared.open(u) }
        case .classSession: store.openInApp(SafeURL.https(store.config.campusSquare.timetable), service: .campus)
        default: store.openInApp(item.url ?? store.config.moodleUpcoming, service: .moodle)
        }
    }
}
