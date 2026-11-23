import Foundation

/// 画面確認用の架空データ。実在の授業とは無関係。
enum SampleData {
    static func moodle(now: Date = .now) -> MoodleSnapshot {
        MoodleSnapshot(
            courses: [
                Course(id: 1, fullName: "サンプル講義A", shortName: "SAMPLE-A", category: "サンプル学科", progress: 62, url: nil),
                Course(id: 2, fullName: "サンプル演習B", shortName: "SAMPLE-B", category: "サンプル学科", progress: 35, url: nil),
                Course(id: 3, fullName: "サンプル実験C", shortName: "SAMPLE-C", category: "共通科目", progress: nil, url: nil),
            ],
            deadlines: [
                Deadline(id: "d0", title: "小レポート（未提出）", course: "サンプル演習B", due: now.addingTimeInterval(-20 * 3600), url: nil),
                Deadline(id: "d1", title: "レポート1 の提出期限", course: "サンプル講義A", due: now.addingTimeInterval(5 * 3600), url: nil),
                Deadline(id: "d2", title: "小テスト 第3回 終了", course: "サンプル演習B", due: now.addingTimeInterval(50 * 3600), url: nil),
                Deadline(id: "d3", title: "実験ノート提出", course: "サンプル実験C", due: now.addingTimeInterval(6 * 86400), url: nil),
            ],
            notices: [
                MoodleNotice(id: 1, subject: "サンプル講義A: 課題が評価されました", time: now.addingTimeInterval(-3600), read: false, url: nil),
                MoodleNotice(id: 2, subject: "サンプル演習B: 新しいフォーラム投稿", time: now.addingTimeInterval(-86400), read: true, url: nil),
            ],
            unreadCount: 1,
            warnings: []
        )
    }

    static func campus() -> CampusSnapshot {
        let days = ["月", "火", "水", "木", "金"]
        func row(_ label: String, _ v: [String]) -> Timetable.Period {
            .init(label: label, byDay: Dictionary(uniqueKeysWithValues: zip(days, v)))
        }
        return CampusSnapshot(
            timetable: Timetable(days: days, periods: [
                row("1限", ["サンプル講義A\n担当 未定\n1号館101", "", "サンプル講義A\n担当 未定\n1号館101", "", "サンプル演習B\n担当 未定\n2号館203"]),
                row("2限", ["サンプル演習B\n担当 未定\n2号館203", "サンプル実験C\n担当 未定\n実験棟", "", "サンプル講義D\n担当 未定\n3号館301", ""]),
                row("3限", ["", "サンプル実験C\n担当 未定\n実験棟", "サンプル講義E\n担当 未定\n1号館102", "", "サンプル講義A\n担当 未定\n1号館101"]),
                row("4限", ["サンプル講義E\n担当 未定\n1号館102", "", "", "サンプル演習B\n担当 未定\n2号館203", ""]),
            ]),
            portlets: [
                Portlet(title: "大学からのお知らせ（サンプル）", lines: ["【重要】サンプル: 後期試験の時間割を公開しました", "サンプル: 図書館の開館時間について", "サンプル: 学生証の更新手続き"]),
                Portlet(title: "休講・補講（サンプル）", lines: ["サンプル講義E 休講（12/2 3限）", "サンプル演習B 教室変更 2号館203→2号館301"]),
            ],
            cancellations: ExtractedTable(title: "休講・補講（サンプル）", header: ["日付", "時限", "科目", "区分"], rows: [
                ["12/2(水)", "3限", "サンプル講義E", "休講"],
                ["12/9(水)", "5限", "サンプル講義E", "補講"],
            ]),
            warnings: []
        )
    }

    static func mail(trustedDomain: String, now: Date = .now) -> MailSnapshot {
        let cal = Calendar.current
        let due = cal.date(byAdding: .day, value: 4, to: now)!
        let md = "\(cal.component(.month, from: due))月\(cal.component(.day, from: due))日"
        let raw: [(String, String, String, String, Double, Bool)] = [
            ("学生課", "gakusei@\(trustedDomain)", "【重要】奨学金継続手続きのお願い（サンプル）", "継続願の提出期限は\(md)17時までです。必ず手続きしてください。", -3, true),
            ("教務課", "kyomu@\(trustedDomain)", "【督促】履修登録が未完了の方へ（サンプル）", "履修登録がまだ完了していません。至急登録してください。", -20, true),
            ("教務課", "kyomu@\(trustedDomain)", "休講のお知らせ：サンプル講義E（サンプル）", "12月2日3限のサンプル講義Eは休講です。補講日は後日連絡します。", -30, false),
            ("Moodle", "noreply@moodle2026.\(trustedDomain)", "サンプル講義A: 新しいフォーラム投稿（サンプル）", "第5回の資料をアップロードしました。", -50, false),
            ("キャリアセンター", "career@\(trustedDomain)", "就職ガイダンス開催のご案内（サンプル）", "来週水曜日に就職ガイダンスを開催します。", -70, false),
            ("Example Shop", "news@shop.example", "セールのお知らせ（サンプル）", "今だけ20%オフ", -90, false),
        ]
        let messages = raw.enumerated().map { i, r in
            var m = MailMessage(id: "s\(i)", threadId: "s\(i)", subject: r.2, from: r.0, fromAddress: r.1,
                                date: now.addingTimeInterval(r.4 * 3600), snippet: r.3, unread: r.5)
            MailClassifier.classify(&m, trustedDomain: trustedDomain, now: now)
            return m
        }
        return MailSnapshot(email: "student@\(trustedDomain)", messages: messages, unreadCount: 2)
    }
}
