import Foundation
import Testing
@testable import CampusHub

@Suite struct SafeURLTests {
    @Test func acceptsOnlyHTTPS() {
        #expect(SafeURL.https("https://moodle2026.shonan-it.ac.jp") != nil)
        #expect(SafeURL.https("http://moodle2026.shonan-it.ac.jp") == nil)
        #expect(SafeURL.https("javascript:alert(1)") == nil)
        #expect(SafeURL.https("https://user:pass@host.example") == nil)
    }

    @Test func trustedDomainMatchesOnlySubdomains() {
        let d = "shonan-it.ac.jp"
        #expect(SafeURL.isTrusted(URL(string: "https://moodle2026.shonan-it.ac.jp/my/"), domain: d))
        #expect(SafeURL.isTrusted(URL(string: "https://shonan-it.ac.jp/"), domain: d))
        #expect(!SafeURL.isTrusted(URL(string: "https://evilshonan-it.ac.jp/"), domain: d))
        #expect(!SafeURL.isTrusted(URL(string: "https://shonan-it.ac.jp.evil.example/"), domain: d))
        #expect(!SafeURL.isTrusted(URL(string: "http://moodle2026.shonan-it.ac.jp/"), domain: d))
    }

    @Test func stableCampusURLDropsSessionKeys() {
        let u = URL(string: "https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowExecutionKey=_c1_k2&_flowId=RSW0001000-flow&x=1#top")!
        #expect(SafeURL.stableCampusURL(u) == "https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=RSW0001000-flow")
        let v = URL(string: "https://portal.shonan-it.ac.jp/campusweb/portal.do?page=main&_flowExecutionKey=abc")!
        #expect(SafeURL.stableCampusURL(v) == "https://portal.shonan-it.ac.jp/campusweb/portal.do?page=main")
    }

    @Test func defaultConfigPointsToLoginHosts() {
        let c = DefaultConfig.university
        #expect(c.loginHost(for: .moodle) == "moodle2026.shonan-it.ac.jp")
        #expect(c.loginHost(for: .campus) == "portal.shonan-it.ac.jp")
        #expect(c.moodleLoginURL?.absoluteString == "https://moodle2026.shonan-it.ac.jp/login/index.php")
    }
}

@Suite struct MoodleParserTests {
    @Test func parsesAjaxBundle() throws {
        let json = """
        {"courses":{"data":{"courses":[{"id":5,"fullname":"情報&amp;数理","shortname":"IM","coursecategory":"工学部","progress":40,"viewurl":"https://moodle2026.shonan-it.ac.jp/course/view.php?id=5"}],"nextoffset":1}},
         "events":{"data":{"events":[{"id":9,"name":"レポート1 の提出期限","timesort":1796050740,"url":"https://evil.example/x","course":{"fullname":"情報&amp;数理"}}]}},
         "notices":{"error":"accessexception"}}
        """
        let snap = try MoodleParser.parse(json, config: DefaultConfig.university)
        #expect(snap.courses.first?.fullName == "情報&数理")
        #expect(snap.courses.first?.progress == 40)
        #expect(snap.deadlines.first?.due == Date(timeIntervalSince1970: 1796050740))
        #expect(snap.deadlines.first?.url == nil) // 大学外のURLはリンクにしない
        #expect(snap.notices.isEmpty)
        #expect(snap.warnings.count == 1)
    }

    @Test func notLoggedInIsReported() {
        #expect(throws: MoodleParser.ParseError.self) { try MoodleParser.parse(#"{"fatal":"nosesskey"}"#, config: DefaultConfig.university) }
    }
}

@Suite struct TimetableTests {
    @Test func classesForDaySkipEmptySlots() {
        let tt = Timetable(days: ["月", "火"], periods: [
            .init(label: "1限", byDay: ["月": "講義A\n1号館", "火": ""]),
            .init(label: "2限", byDay: ["月": "-", "火": "演習B"]),
        ])
        #expect(tt.classes(on: "月").map(\.period) == ["1限"])
        #expect(tt.classes(on: "火").map(\.text) == ["演習B"])
        #expect(tt.classes(on: "水").isEmpty)
    }

    @Test func dayChar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let monday = DateComponents(calendar: cal, year: 2026, month: 11, day: 23, hour: 12).date!
        #expect(Timetable.dayChar(for: monday, calendar: cal) == "月")
    }
}

@Suite struct MiscTests {
    @Test func urgency() {
        let now = Date(timeIntervalSince1970: 0)
        func d(_ h: Double) -> Deadline { Deadline(id: "x", title: "t", course: nil, due: now.addingTimeInterval(h * 3600), url: nil) }
        #expect(d(-1).urgency(now: now) == .overdue)
        #expect(d(5).urgency(now: now) == .urgent)
        #expect(d(48).urgency(now: now) == .soon)
        #expect(d(100).urgency(now: now) == .normal)
    }

    @Test func importance() {
        #expect(Importance.isImportant("【休講】情報数理"))
        #expect(!Importance.isImportant("図書館のお知らせ"))
    }

    @Test func plainText() {
        #expect("<b>A&amp;B</b>&nbsp;".plainText == "A&B")
    }
}

@Suite struct MailClassifierTests {
    let domain = "shonan-it.ac.jp"
    func mail(_ subject: String, _ snippet: String, from: String = "kyomu@sit.shonan-it.ac.jp", date: Date) -> MailMessage {
        var m = MailMessage(id: "1", threadId: "1", subject: subject, from: "教務課", fromAddress: from, date: date, snippet: snippet, unread: true)
        MailClassifier.classify(&m, trustedDomain: domain, now: date)
        return m
    }
    var ref: Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return DateComponents(calendar: c, year: 2026, month: 11, day: 23, hour: 10).date!
    }

    @Test func actionWithDeadline() {
        let m = mail("【重要】奨学金継続手続き", "提出期限は12月5日17時までです。", date: ref)
        #expect(m.category == .action)
        #expect(m.isFromSchool)
        let c = Calendar.current.dateComponents([.month, .day, .hour], from: m.dueDate!)
        #expect(c.month == 12 && c.day == 5 && c.hour == 17)
    }

    @Test func overdueReminder() {
        let m = mail("【督促】履修登録が未完了の方へ", "まだ完了していません", date: ref)
        #expect(m.category == .action)
        #expect(m.looksOverdue)
    }

    @Test func cancellationWins() {
        #expect(mail("休講のお知らせ", "12/2 3限は休講です。", date: ref).category == .classChange)
    }

    @Test func externalAdIsOther() {
        let m = mail("セール", "今だけ", from: "news@shop.example", date: ref)
        #expect(m.category == .other)
        #expect(!m.isFromSchool)
    }

    @Test func lookalikeDomainIsNotSchool() {
        #expect(!mail("お知らせ", "", from: "x@evil-shonan-it.ac.jp", date: ref).isFromSchool)
    }

    @Test func yearRollsOverForJanuary() {
        let d = DateExtractor.findDeadline(in: "1月10日までに提出", reference: ref)!
        #expect(Calendar.current.component(.year, from: d) == 2027)
    }

    @Test func noDeadlineWithoutMarker() {
        #expect(DateExtractor.findDeadline(in: "12月5日に説明会を開催します", reference: ref) == nil)
    }

    @Test func parseFromHeader() {
        #expect(GmailClient.parseFrom("\"教務課\" <kyomu@sit.shonan-it.ac.jp>") == ("教務課", "kyomu@sit.shonan-it.ac.jp"))
        #expect(GmailClient.parseFrom("a@b.jp") == ("a@b.jp", "a@b.jp"))
    }
}

@Suite struct MoodleCalendarTests {
    @Test func upcomingFillsInWhenActionEventsFail() throws {
        let json = """
        {"events":{"error":"servicenotavailable"},
         "upcoming":{"data":{"events":[
           {"id":3,"name":"課題2 期限","timestart":1796050740,"timesort":1796050740,"eventtype":"due","modulename":"assign","course":{"fullname":"情報数理"}},
           {"id":4,"name":"オフィスアワー","timestart":1796000000,"timeduration":3600,"eventtype":"course"}]}}}
        """
        let s = try MoodleParser.parse(json, config: DefaultConfig.university)
        #expect(s.deadlines.count == 1)
        #expect(s.deadlines[0].needsAction == false)
        #expect(s.upcoming.count == 2)
        #expect(s.upcoming.first { $0.id == "c-4" }?.kind == .moodleEvent)
        #expect(s.upcoming.first { $0.id == "c-4" }?.end != nil)
    }

    @Test func monthViewIsFlattenedAndDeduped() throws {
        let json = """
        {"month":{"data":{"weeks":[{"days":[{"events":[{"id":1,"name":"A","timestart":1796000000,"eventtype":"due"}]},{"events":[]}]},
                                    {"days":[{"events":[{"id":1,"name":"A","timestart":1796000000,"eventtype":"due"},{"id":2,"name":"B","timestart":1796100000}]}]}]}}}
        """
        let items = try MoodleParser.parseMonth(json, config: DefaultConfig.university)
        #expect(items.map(\.id) == ["c-1", "c-2"])
        #expect(items[0].kind == .deadline)
    }

    @Test func oldPreferencesStillDecode() throws {
        let old = #"{"showTodayClasses":false,"autoLogin":false}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(AppPreferences.self, from: old)
        #expect(p.showTodayClasses == false)
        #expect(p.autoLogin == false)
        #expect(p.showTimetableInCalendar == true)
    }

    @Test func numericEntities() {
        #expect("It&#39;s &#x30A2;&amp;B".plainText == "It's ア&B")
    }
}

@Suite struct LoopbackTests {
    @Test func receivesAuthorizationCode() async throws {
        let server = try LoopbackServer()
        let port = try await server.start()
        #expect(port > 0)
        async let result = server.waitForCallback(timeout: 10)
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/?code=abc123&state=xyz")!)
        #expect(String(data: data, encoding: .utf8)?.contains("連携ができました") == true)
        let params = try await result
        #expect(params["code"] == "abc123")
        #expect(params["state"] == "xyz")
        server.stop()
    }
}

@Suite struct TimetableSplitTests {
    @Test func codeLineMovesAside() {
        let r = Timetable.split("B30A02K1\n共通基盤ワークショップ1B\n担当 A\n2.0単位")
        #expect(r.code == "B30A02K1")
        #expect(r.title == "共通基盤ワークショップ1B")
        #expect(r.rest == ["担当 A", "2.0単位"])
    }
    @Test func plainTitleKept() {
        let r = Timetable.split("情報数理\n1号館101")
        #expect(r.code == nil)
        #expect(r.title == "情報数理")
    }
}

@Suite struct TimetableCourseTests {
    let courses: [Course] = [
        (1404, "【情】後学期_プログラミング実習[火1]（全体）", "後学期_プログラミング実習-B31L07K101"),
        (1476, "【情】後学期_プログラミング実習[火1]（クラスA）", "【情】後学期_プログラミング実習[火1]（クラスA）"),
        (173, "【工】前学期_（教）教育原理[火5]", "前学期_（教）教育原理-70W021A101"),
        (1033, "【工】後学期_（教）教職入門[火5]", "後学期_（教）教職入門-70W012K101"),
        (910, "【工】後学期_文章作成法[木4]-自己表現の技法-", "後学期_文章作成法-70D052L101"),
        (1357, "【情】後学期_英語総合発展木３－３[木3]", "後学期_英語総合発展-B30G02C101"),
    ].map { Course(id: $0.0, fullName: $0.1, shortName: $0.2, category: nil, progress: nil,
                   url: URL(string: "https://m.example/course/view.php?id=\($0.0)")) }
    let now = ISO8601DateFormatter().date(from: "2026-11-24T01:00:00Z")!

    func find(_ text: String, _ day: String, _ period: String) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return Timetable.moodleCourse(in: courses, text: text, day: day, period: period, now: now, calendar: cal)?.id
    }

    @Test func codeMatchWins() {
        #expect(find("B31L07K1\nプログラミング実習【担当A・担当B】\n担当 A\n2.0単位", "火", "1限") == 1404)
    }
    @Test func nameMatchIgnoresTeacherTermAndWidth() {
        #expect(find("Z30W01K1\n（教）教職入門【担当C】", "火", "5限") == 1033)
        #expect(find("B30D05L1\n文章作成法【担当D】", "木", "4限") == 910)
        #expect(find("B30G02C1\n英語総合発展【担当E】 木３－３", "木", "3限") == 1357)
    }
    @Test func noMatchIsNil() {
        #expect(find("X99Z99K1\n存在しない科目【担当G】", "水", "1限") == nil)
    }
    @Test func spellingVariantsMatchButDifferentNumbersDoNot() {
        let more: [Course] = [
            (2001, "【工・情】後学期_心理を読む[水2]"),
            (2002, "【情】後学期_ＩＴ演習基礎２（メ）[木4]"),
            (2004, "【情】後学期_情報学実習Ａ[金3]"),
        ].map { Course(id: $0.0, fullName: $0.1, shortName: "x", category: nil, progress: nil,
                       url: URL(string: "https://m.example/course/view.php?id=\($0.0)")) }
        func f(_ t: String, _ d: String, _ p: String) -> Int? {
            Timetable.moodleCourse(in: more, text: t, day: d, period: p, now: now)?.id
        }
        #expect(f("B30X01K1\n心理をよむ【担当H】", "水", "2限") == 2001)
        #expect(f("B31R01K1\nＩＴ演習基礎１（メ）【担当J】", "火", "4限") == nil)
        #expect(f("B31M02K1\n情報学実習Ｂ【担当K】", "金", "3限") == nil)
    }
    @Test func searchURLWhenNotFound() {
        #expect(Timetable.searchURL(base: "https://m.example/", text: "B30X01K1\n心理をよむ【担当H】")?.absoluteString
                == "https://m.example/course/search.php?search=%E5%BF%83%E7%90%86%E3%82%92%E3%82%88%E3%82%80")
        #expect(Timetable.searchURL(base: "", text: "心理をよむ") == nil)
    }
}

@Suite struct ThisWeekTests {
    @Test func earlyAssignmentWhenClassIsCancelledBeforeDue() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-11-24T04:49:00Z")!
        let snap = CampusSnapshot(timetable: nil, portlets: [Portlet(title: "お知らせ", lines: ["英語総合発展 12月17日 休講"])],
                                  cancellations: ExtractedTable(title: nil, header: [], rows: [["12/2(水)", "3限", "データサイエンス入門２（メ）", "休講"]]),
                                  warnings: [])
        let list = ThisWeek.cancellations(snap, now: now, calendar: cal)
        #expect(list.count == 2)
        #expect(ThisWeek.cancelledBefore(course: "【情】後学期_データサイエンス入門２（メ）[水3]", due: iso.date(from: "2026-12-09T14:59:00Z")!,
                                         in: list, now: now, calendar: cal) != nil)
        // 休講が締切より後なら早めの課題ではない
        #expect(ThisWeek.cancelledBefore(course: "【情】後学期_英語総合発展木３－３[木3]", due: iso.date(from: "2026-12-10T14:59:00Z")!,
                                         in: list, now: now, calendar: cal) == nil)
        #expect(!ThisWeek.isLater(iso.date(from: "2026-12-01T08:00:00Z")!, now: now))  // あと7日は出す
        #expect(ThisWeek.isLater(iso.date(from: "2026-12-04T14:59:00Z")!, now: now))   // あと10日は出さない
    }
}

@Suite struct ClosedEventTests {
    @Test func closedQuestionnaireIsDroppedButLateAssignmentKept() throws {
        let past = Int(Date.now.timeIntervalSince1970) - 86400
        let json = """
        {"events":{"data":{"events":[
          {"id":1,"name":"出席アンケート（アンケート終了）","timesort":\(past),"eventtype":"close","modulename":"questionnaire","action":{"actionable":true}},
          {"id":2,"name":"レポート1 期限","timesort":\(past),"eventtype":"due","modulename":"assign","action":{"actionable":true}},
          {"id":3,"name":"アンケート開始","timesort":\(past + 200000),"eventtype":"open","modulename":"questionnaire"}]}}}
        """
        let s = try MoodleParser.parse(json, config: DefaultConfig.university)
        #expect(s.deadlines.map(\.id) == ["m-2"])
    }
}

@Suite struct FormReceiptTests {
    @Test func coreTitleStripsDecorations() {
        #expect(GmailClient.coreTitle("(出席課題) 出席アンケート (締切：11月9日23:59)") == "出席アンケート")
        #expect(GmailClient.coreTitle("【情】第8回 出席確認") == "第8回出席確認")
    }
    @Test func receiptMatchesTitleNearDueDate() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let d = Deadline(id: "m-1", title: "(出席課題) 第8回 出席確認 (締切)", course: nil, due: due, url: nil)
        #expect(GmailClient.hasReceipt(for: d, in: [("「第8回 出席確認」の回答のコピー", due.addingTimeInterval(-3600))]))
        #expect(!GmailClient.hasReceipt(for: d, in: [("「第8回 出席確認」の回答のコピー", due.addingTimeInterval(-40 * 86400))]))
        #expect(!GmailClient.hasReceipt(for: d, in: [("「第9回 出席確認」の回答のコピー", due)]))
    }
}

@Suite struct UpdateCheckTests {
    private let hash = String(repeating: "ab", count: 32)

    private func release(_ tag: String, pkg: Bool = true, digest: String? = nil, draft: Bool = false, pre: Bool = false) -> UpdateCheck.Release {
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        var assets = [UpdateCheck.Asset(name: "CampusHub-Setup-\(v).exe", size: 100, digest: "sha256:" + hash,
                                        browser_download_url: URL(string: "https://github.com/x/y/releases/download/\(tag)/CampusHub-Setup-\(v).exe")!)]
        if pkg {
            assets.append(UpdateCheck.Asset(name: "CampusHub-\(v).pkg", size: 100, digest: digest ?? "sha256:" + hash,
                                            browser_download_url: URL(string: "https://github.com/x/y/releases/download/\(tag)/CampusHub-\(v).pkg")!))
        }
        return UpdateCheck.Release(tag_name: tag, draft: draft, prerelease: pre, assets: assets)
    }

    @Test func comparesVersionsNumerically() {
        #expect(UpdateCheck.isNewer("0.3.10", than: "0.3.9"))
        #expect(UpdateCheck.isNewer("1.0", than: "0.9.9"))
        #expect(!UpdateCheck.isNewer("0.3.6", than: "0.3.6"))
        #expect(!UpdateCheck.isNewer("0.3.6.0", than: "0.3.6"))
        #expect(!UpdateCheck.isNewer("0.3.5", than: "0.3.6"))
        #expect(!UpdateCheck.isNewer("0.4.0-beta", than: "0.3.6"))
        #expect(!UpdateCheck.isNewer("0.4.0", than: "開発版"))
    }

    @Test func picksNewestReleaseThatHasAMacInstaller() {
        let rs = [release("v0.3.8", pkg: false), release("v0.3.7"), release("v0.3.6")]
        let c = UpdateCheck.pick(rs, current: "0.3.6")
        #expect(c?.version == "0.3.7")
        #expect(c?.url.lastPathComponent == "CampusHub-0.3.7.pkg")
        #expect(c?.sha256 == hash)
        #expect(UpdateCheck.pick(rs, current: "0.3.7") == nil)
    }

    @Test func skipsDraftsPrereleasesAndAssetsWithoutDigest() {
        #expect(UpdateCheck.pick([release("v0.4.0", draft: true)], current: "0.3.6") == nil)
        #expect(UpdateCheck.pick([release("v0.4.0", pre: true)], current: "0.3.6") == nil)
        #expect(UpdateCheck.pick([release("v0.4.0", digest: "md5:abc")], current: "0.3.6") == nil)
        #expect(UpdateCheck.pick([release("v0.4.0", digest: "sha256:xyz")], current: "0.3.6") == nil)
    }
}
