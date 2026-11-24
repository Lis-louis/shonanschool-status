import Foundation

/// ページ内で実行する JavaScript と、その結果の読み取り。
enum Scripts {
    /// 公式ログインページの入力欄にID・パスワードを入れる（.defaultClient の分離環境で実行）。
    /// 引数: userSel, passSel, submitSel, errSel, username, password, submit(Bool), checkOnly(Bool)
    /// 戻り値: "none"（ログイン欄なし）/ "login"（ログイン欄あり・checkOnly）/ "error"（エラー表示中）/ "filled" / "submitted"
    static let autoLogin = """
    const q = s => { try { return s ? document.querySelector(s) : null; } catch (e) { return null; } };
    const u = q(userSel), p = q(passSel);
    if (!u || !p) return "none";
    if (checkOnly) return "login";
    if (errSel) { const e = q(errSel); if (e && e.offsetParent !== null && e.innerText.trim()) return "error"; }
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    const put = (el, v) => {
      setter.call(el, v);
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    };
    put(u, username);
    put(p, password);
    if (!submit) return "filled";
    const b = q(submitSel);
    if (b) { b.click(); }
    else if (p.form) { if (p.form.requestSubmit) p.form.requestSubmit(); else p.form.submit(); }
    return "submitted";
    """

    /// Moodle 自身の画面が使っている AJAX 呼び出しの共通部分（.page で実行）
    private static let moodleAjaxPrelude = """
    for (let i = 0; i < 60 && !(window.M && M.cfg && M.cfg.sesskey); i++) await new Promise(r => setTimeout(r, 100));
    if (!window.M || !M.cfg || !M.cfg.sesskey) return JSON.stringify({ fatal: "nosesskey", page: location.host + location.pathname });
    const call = async (methodname, args) => {
      try {
        const r = await fetch(M.cfg.wwwroot + "/lib/ajax/service.php?sesskey=" + encodeURIComponent(M.cfg.sesskey) + "&info=" + methodname, {
          method: "POST", credentials: "same-origin",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify([{ index: 0, methodname, args }])
        });
        const text = await r.text();
        let j;
        try { j = JSON.parse(text); } catch (e) { return { error: "HTTP " + r.status + "（JSONではない応答）" }; }
        const first = Array.isArray(j) ? j[0] : j;
        if (!first || first.error) {
          const ex = (first && (first.exception || first)) || {};
          return { error: String(ex.errorcode || ex.message || "error") };
        }
        return { data: first.data };
      } catch (e) { return { error: String(e) }; }
    };
    """

    /// 引数: from, to（UNIX秒）
    static let moodleFetch = moodleAjaxPrelude + """
    const [courses, events, upcoming, notices] = await Promise.all([
      call("core_course_get_enrolled_courses_by_timeline_classification",
           { offset: 0, limit: 0, classification: "all", sort: "fullname" }),
      call("core_calendar_get_action_events_by_timesort",
           { timesortfrom: from, timesortto: to, limitnum: 50, limittononsuspendedevents: true }),
      call("core_calendar_get_calendar_upcoming_view", { courseid: 1, categoryid: 0 }),
      call("message_popup_get_popup_notifications",
           { useridto: 0, newestfirst: 1, limit: 20, offset: 0 })
    ]);
    return JSON.stringify({ courses, events, upcoming, notices, page: location.host + location.pathname });
    """

    /// 月のカレンダー。引数: year, month
    static let moodleMonth = moodleAjaxPrelude + """
    const month = await call("core_calendar_get_calendar_monthly_view",
      { year, month: mon, courseid: 1, categoryid: 0, includenavigation: false, mini: false, day: 1 });
    return JSON.stringify({ month });
    """

    /// Campus Square ポータルの各枠（お知らせ等）の文字を読み取る
    static let campusPortlets = textHelper + """
    const out = [];
    const seen = new Set();
    document.querySelectorAll(".portlet").forEach(p => {
      const t = (p.querySelector("input[name='wfNm']") || {}).value || txt(p.querySelector("h1,h2,h3,h4,.portlet-title,.title"));
      const title = (t || "").split("\\n")[0].trim();
      if (!title || /ログイン|Login/i.test(title) || seen.has(title)) return;
      if (p.querySelector("input[type=password]")) return;
      seen.add(title);
      const lines = [];
      txt(p).split("\\n").forEach(l => {
        const s = l.trim();
        if (s && s !== title && !lines.includes(s) && s.length < 300) lines.push(s);
      });
      if (lines.length) out.push({ title, lines: lines.slice(0, 40) });
    });
    return JSON.stringify(out);
    """

    /// ポータルのメニュー（ページ名と _flowId）の一覧。診断と時間割ページ探しに使う
    static let campusMenu = """
    const out = [];
    const seen = new Set();
    document.querySelectorAll("a, button, [onclick]").forEach(el => {
      const src = (el.getAttribute("href") || "") + " " + (el.getAttribute("onclick") || "");
      const m = src.match(/_flowId=([A-Za-z0-9]+-flow)/);
      if (!m || seen.has(m[1])) return;
      seen.add(m[1]);
      out.push({ flow: m[1], text: (el.innerText || el.title || "").replace(/\\s+/g, " ").trim().slice(0, 40) });
    });
    return JSON.stringify(out);
    """

    /// ページの見出し（診断用）
    static let pageHeading = """
    const h = document.querySelector("h1,h2,h3,.title,.page-title,.portlet-title");
    return ((h && h.innerText) || document.title || "").replace(/\\s+/g, " ").trim().slice(0, 60)
      + "｜表 " + document.querySelectorAll("table").length + "個";
    """

    /// 表示されていない（画面外の）ページでも文字を取れるよう、textContent から改行を保って文字を組み立てる
    static let textHelper = """
    const BLOCK = /^(DIV|P|TR|LI|UL|OL|TABLE|TBODY|THEAD|H[1-6]|DL|DT|DD|FORM)$/;
    const txt = el => {
      if (!el) return "";
      let out = "";
      const walk = n => {
        if (n.nodeType === 3) { out += n.nodeValue; return; }
        if (n.nodeType !== 1) return;
        const tag = n.tagName;
        if (tag === "SCRIPT" || tag === "STYLE" || tag === "NOSCRIPT") return;
        if (tag === "BR") { out += "\\n"; return; }
        if (tag === "TD" || tag === "TH") out += " ";
        n.childNodes.forEach(walk);
        if (BLOCK.test(tag)) out += "\\n";
      };
      walk(el);
      return out.split("\\n").map(s => s.replace(/[\\s\\u00a0]+/g, " ").trim()).filter(Boolean).join("\\n");
    };

    """

    /// 表の構造（診断用）。セルの文字そのものは出さず、曜日・時限の形かどうかと文字数だけを記号で出す
    static let tableShapes = textHelper + """
    const kind = c => {
      const t = txt(c).replace(/\\s+/g, " ").trim();
      if (!t) return "_";
      const m = t.match(/^([月火水木金土日])(曜|\\(|（|\\s|$)/);
      if (m) return "D" + m[1];
      const p = t.match(/^(\\d{1,2})\\s*(限|時限)?$/) || t.match(/^(\\d{1,2})\\s*(限|時限)/);
      if (p) return "P" + p[1];
      return "x" + Math.min(t.length, 99);
    };
    const out = [];
    document.querySelectorAll("table").forEach((t, i) => {
      if (t.rows.length < 2) return;
      const rows = Array.from(t.rows).slice(0, 4).map(r => Array.from(r.cells).map(kind).join(","));
      out.push("#" + i + "(" + t.rows.length + "行" + (t.querySelector("table") ? ",入れ子" : "") + ",文字" + (t.textContent || "").trim().length
               + ",画像" + t.querySelectorAll("img").length + ") " + rows.join(" | "));
    });
    const ctl = [];
    document.querySelectorAll("input[type=button],input[type=submit],button,select,a[onclick]").forEach(el => {
      const label = (el.tagName === "SELECT" ? "選択:" + Array.from(el.options).map(o => o.text.trim()).slice(0, 6).join("/") : (el.value || el.innerText || "")).replace(/\\s+/g, " ").trim();
      if (label && label.length <= 30) ctl.push(label);
    });
    const alts = Array.from(document.querySelectorAll("img[alt]")).map(i => i.alt).filter(a => a && a.length <= 10).slice(0, 15);
    const forms = Array.from(document.forms).map(f => (f.getAttribute("name") || f.id || "?") + "(" + f.elements.length + ")");
    return out.slice(0, 20).join(" ／ ") + " ／ 操作: " + ctl.slice(0, 25).join(", ") + " ／ 画像alt: " + alts.join(",") + " ／ form: " + forms.join(",");
    """

    /// 曜日（月〜金）が見出しに並ぶ表を時間割として読み取る
    static let campusTimetable = textHelper + """
    const days = ["月", "火", "水", "木", "金", "土"];
    const dayOf = t => { const m = t.replace(/\\s+/g, "").match(/^([月火水木金土])(曜|\\(|（|$)/); return m ? m[1] : null; };
    for (const t of document.querySelectorAll("table")) {
      const rows = Array.from(t.rows);
      for (let h = 0; h < Math.min(rows.length, 4); h++) {
        const head = Array.from(rows[h].cells).map(c => dayOf(txt(c)));
        const idx = days.map(d => head.indexOf(d));
        if (idx.filter(i => i >= 0).length < 5) continue;
        const grid = rows.slice(h + 1).map(r => {
          const cells = Array.from(r.cells);
          const byDay = {};
          days.forEach((d, k) => { if (idx[k] >= 0 && cells[idx[k]]) byDay[d] = txt(cells[idx[k]]); });
          return { label: txt(cells[0]).split("\\n")[0] || "", byDay };
        }).filter(p => p.label);
        // 何度も同じ短い文字が入るセル（「未登録」など）は空きコマとみなす
        const freq = {};
        grid.forEach(p => Object.values(p.byDay).forEach(v => { if (v && v.length <= 6) freq[v] = (freq[v] || 0) + 1; }));
        const filler = new Set(Object.keys(freq).filter(k => freq[k] >= 4));
        grid.forEach(p => Object.keys(p.byDay).forEach(d => { if (filler.has(p.byDay[d])) p.byDay[d] = ""; }));
        const label = l => /^\\d+$/.test(l) ? l + "限" : l;
        return JSON.stringify({ days: days.filter((d, k) => idx[k] >= 0), periods: grid.map(p => ({ label: label(p.label), byDay: p.byDay })) });
      }
    }
    return null;
    """

    /// 休講補講参照のページで「一覧形式・変更情報のみ・履修中の科目のみ・今日から5週間」を表示させて読み取る。
    /// コマ形式（初期表示）は1週間分のマス目で、表が入れ子のため largestTable では読めない。
    /// 行の class が kyuko-kyuko（休講）/ kyuko-hoko（補講）/ kyuko-kyoshitsu（教室変更）。
    /// 休講補講参照のページでなければ null（呼ぶ側で largestTable に切り替える）
    static let campusCancellations = #"""
    const clean = s => String(s || "").replace(/\s+/g, " ").trim();
    const f = Array.from(document.forms).find(f => f.querySelector("[name=dispType]"));
    if (!f) return null;
    const body = new URLSearchParams();
    const key = f.querySelector("[name=_flowExecutionKey]");
    if (key) body.set("_flowExecutionKey", key.value);
    body.set("_eventId", "search");
    body.set("_eventId_search", " 表 示 す る");
    body.set("dispType", "list");
    body.set("dispData", "chg");
    const ymd = d => [d.getFullYear(), d.getMonth() + 1, d.getDate()];
    const put = (name, d) => {
      const [y, m, day] = ymd(d);
      body.set(name, y + "/" + m + "/" + day);
      body.set(name + "_year", y); body.set(name + "_month", m); body.set(name + "_day", day);
    };
    put("startDay", new Date());
    put("endDay", new Date(Date.now() + 35 * 86400000));
    body.set("rishuchuFlg", "true");
    body.set("_rishuchuFlg", "1");
    body.set("kyokanCode", ""); body.set("campusCode", ""); body.set("shozokuCode", "");
    const r = await fetch(f.action, { method: "POST", body, credentials: "same-origin" });
    const doc = new DOMParser().parseFromString(await r.text(), "text/html");
    const tb = doc.querySelector("table.normal");
    if (!tb) return null;
    const KIND = { "kyuko-kyuko": "休講", "kyuko-hoko": "補講", "kyuko-kyoshitsu": "教室変更" };
    const rows = [];
    for (const tr of Array.from(tb.rows).slice(1)) {
      const c = Array.from(tr.cells).map(td => clean(td.textContent));
      if (c.length < 4) continue;
      const k = Object.keys(KIND).find(k => tr.classList.contains(k) || tr.querySelector("." + k));
      rows.push([c[0], c[1], c[2], c[3], k ? KIND[k] : "変更", c.length > 6 ? c[c.length - 1] : ""]);
    }
    return JSON.stringify({ title: "休講・補講・教室変更", header: ["日付", "時限", "時間割コード", "科目", "区分", "この日の教室"], rows });
    """#

    /// ページ内でいちばん大きい表を読み取る（休講一覧など）
    static let largestTable = textHelper + """
    const clean = el => txt(el).replace(/\\s+/g, " ").trim();
    let best = null;
    document.querySelectorAll("table").forEach(t => {
      if (t.querySelector("table")) return;
      const n = t.rows.length * (t.rows[0] ? t.rows[0].cells.length : 0);
      if (t.rows.length >= 2 && (!best || n > best.n)) best = { t, n };
    });
    if (!best) return null;
    const rows = Array.from(best.t.rows).map(r => Array.from(r.cells).map(clean));
    const title = clean(document.querySelector("h1,h2,h3,.title,.page-title")) || document.title;
    return JSON.stringify({ title, header: rows[0], rows: rows.slice(1, 200).filter(r => r.some(Boolean)) });
    """

    /// 課題・アンケートのページを開いて提出状況を確かめる（.page で実行）。引数: urls
    /// 戻り値には、当てはまった判定用の文言（下の一覧のどれか）だけを入れる。ページの内容は返さない
    static let moodleSubmissionStatus = """
    const SUB = ["あなたの回答を表示", "あなたの回答", "回答済み", "すでに回答", "既に回答", "回答を送信しました", "送信済み",
                 "評定のために提出済み", "提出済み", "提出を編集する", "前回の受験の概要", "受験済み",
                 "あなたの選択", "回答を削除する", "もう一度受験する",
                 "View your response", "Your response", "You've completed", "Submitted for grading", "Edit submission",
                 "Summary of your previous attempts", "Your selection", "Remove my choice", "Re-attempt quiz"];
    const OPEN = ["提出をアップロード・入力する", "提出を追加する", "未提出", "まだ回答していません", "回答していません", "提出なし",
                  "質問に回答する", "今すぐ受験する", "受験を開始する", "問題を受験する", "受験を続ける", "回答を保存する",
                  "Add submission", "No submission", "Not submitted", "Answer the questions", "Attempt quiz", "Continue your attempt",
                  "Save my choice"];
    const NOT_YET = ["開始予定:", "開始予定：", "Opens:"];
    const FORM = /https?:\\/\\/(docs\\.google\\.com\\/forms\\/[^"'\\s<>]+|forms\\.gle\\/[^"'\\s<>]+|forms\\.office\\.com\\/[^"'\\s<>]+|forms\\.microsoft\\.com\\/[^"'\\s<>]+)/;
    const check = async u => {
      try {
        const r = await fetch(u, { credentials: "same-origin" });
        const html = await r.text();
        const doc = new DOMParser().parseFromString(html, "text/html");
        const main = doc.querySelector("#region-main") || doc.querySelector("[role=main]") || doc.body;
        const text = (main ? main.textContent : "").replace(/\\s+/g, " ");
        const sub = SUB.find(k => text.includes(k));
        const open = OPEN.find(k => text.includes(k));
        const fm = (main ? main.innerHTML : html).match(FORM) || html.match(FORM);
        if (sub) return { url: u, status: "submitted", hit: sub };
        if (fm) return { url: u, status: "form", hit: "外部フォーム", form: fm[0] };
        if (open) return { url: u, status: "notSubmitted", hit: open };
        const notYet = NOT_YET.find(k => text.includes(k));
        if (notYet) return { url: u, status: "notOpenYet", hit: notYet };
        // 診断用：活動の種類と、ボタン・状態表示の短いラベルだけ
        const mod = (new URL(u).pathname.match(/\\/mod\\/([a-z]+)\\//) || [])[1] || "?";
        const labels = Array.from((main || doc).querySelectorAll(".btn, button, input[type=submit], .badge, [data-region=activity-information] *, .completion-info, .activity-dates, .alert"))
          .map(e => (e.value || e.textContent || "").replace(/\\s+/g, " ").trim()).filter(t => t && t.length <= 20);
        return { url: u, status: "unknown", hit: mod + "{" + Array.from(new Set(labels)).slice(0, 8).join("|") + "}" };
      } catch (e) { return { url: u, status: "unknown", hit: "error" }; }
    };
    const out = [];
    for (let i = 0; i < urls.length; i += 4) {
      out.push(...await Promise.all(urls.slice(i, i + 4).map(check)));
    }
    return JSON.stringify(out);
    """

    // MARK: - 鈴テーマ（大学ページに重ねる最小限の配色。レイアウトは変えない）

    static func themeCSS(trustedDomain: String) -> String {
        let css = """
        body { font-family: -apple-system, "Hiragino Sans", "Hiragino Kaku Gothic ProN", sans-serif !important; }
        a { color: #5B7FE0; }
        .btn-primary, #loginbtn, #login-form button[type=submit] {
          background: linear-gradient(135deg, #8FA8F0, #5B7FE0) !important; border: none !important;
          border-radius: 999px !important; color: #fff !important; box-shadow: 0 4px 14px rgba(91,127,224,.25) !important;
        }
        .card, .portlet, .block { border-radius: 18px !important; border-color: #DCE4FA !important; }
        table th { background: #E8EEFF !important; color: #2B3A6E !important; }
        input[type=text], input[type=password] { border-radius: 12px !important; }
        """
        let escaped = css.replacingOccurrences(of: "`", with: "")
        let domain = trustedDomain.replacingOccurrences(of: "\"", with: "")
        return """
        (() => {
          const h = location.hostname, d = "\(domain)";
          if (!(h === d || h.endsWith("." + d))) return;
          const s = document.createElement("style");
          s.textContent = `\(escaped)`;
          document.head && document.head.appendChild(s);
        })();
        """
    }
}

// MARK: - Moodle の応答を読む

enum MoodleParser {
    struct Result<T: Decodable>: Decodable { let data: T?; let error: String? }
    struct Bundle: Decodable {
        let fatal: String?
        let page: String?
        let courses: Result<CoursesData>?
        let events: Result<EventsData>?
        let upcoming: Result<EventsData>?
        let notices: Result<NoticesData>?
    }
    struct MonthBundle: Decodable {
        let fatal: String?
        let month: Result<MonthData>?
    }
    struct CoursesData: Decodable { let courses: [C] }
    struct C: Decodable {
        let id: Int; let fullname: String; let shortname: String
        let coursecategory: String?; let progress: Double?; let viewurl: String?; let hidden: Bool?
    }
    struct EventsData: Decodable { let events: [E] }
    /// action / upcoming / monthly で共通の予定（無い項目もあるので省略可能にする）
    struct E: Decodable {
        let id: Int; let name: String
        let timestart: Int?; let timesort: Int?; let timeduration: Int?
        let url: String?; let location: String?
        let eventtype: String?; let modulename: String?
        let course: CR?
        let action: Action?
        struct CR: Decodable { let fullname: String }
        struct Action: Decodable { let actionable: Bool?; let name: String? }
    }
    struct MonthData: Decodable { let weeks: [Week] }
    struct Week: Decodable { let days: [Day] }
    struct Day: Decodable { let events: [E]? }
    struct NoticesData: Decodable { let notifications: [N]; let unreadcount: Int? }
    struct N: Decodable { let id: Int; let subject: String; let timecreated: Int; let read: Bool; let contexturl: String? }

    enum ParseError: LocalizedError {
        case notLoggedIn(String?), invalid
        var errorDescription: String? {
            switch self {
            case .notLoggedIn(let page): "Moodleにログインできていません（開いていたページ: \(page ?? "不明")）。"
            case .invalid: "Moodleの応答を読み取れませんでした。"
            }
        }
    }

    /// 締切とみなす予定の種類（課題の提出期限・小テストの終了など）
    static func isDue(_ e: E) -> Bool {
        let t = e.eventtype ?? ""
        return ["due", "close", "gradingdue", "expectcompletionon"].contains(t) || e.action != nil
    }

    static func item(_ e: E, link: (String?) -> URL?) -> CalendarItem {
        let start = Date(timeIntervalSince1970: TimeInterval(e.timestart ?? e.timesort ?? 0))
        let dur = TimeInterval(e.timeduration ?? 0)
        return CalendarItem(id: "c-\(e.id)", title: e.name.plainText, start: start,
                            end: dur > 0 ? start.addingTimeInterval(dur) : nil,
                            kind: isDue(e) ? .deadline : .moodleEvent,
                            course: e.course?.fullname.plainText, location: e.location?.plainText.nilIfEmpty, url: link(e.url))
    }

    static func linker(_ config: UniversityConfig) -> (String?) -> URL? {
        { s in s.flatMap(SafeURL.https).flatMap { SafeURL.isTrusted($0, domain: config.trustedDomain) ? $0 : nil } }
    }

    static func parse(_ json: String, config: UniversityConfig, log: (String, Bool) -> Void = { _, _ in }) throws -> MoodleSnapshot {
        guard let data = json.data(using: .utf8) else { throw ParseError.invalid }
        let b: Bundle
        do { b = try JSONDecoder().decode(Bundle.self, from: data) }
        catch { log("応答の形式が想定と違います: \(error)", false); throw ParseError.invalid }
        if b.fatal != nil { throw ParseError.notLoggedIn(b.page) }
        let link = linker(config)

        var warnings: [String] = []
        func note(_ name: String, _ r: (some Any)?, _ e: String?, count: Int) {
            if let e { warnings.append("\(name)を取得できませんでした（\(e)）"); log("\(name): エラー \(e)", false) }
            else { log("\(name): \(count)件", true) }
        }
        let rawCourses = b.courses?.data?.courses ?? []
        let rawEvents = b.events?.data?.events ?? []
        let rawUpcoming = b.upcoming?.data?.events ?? []
        let n = b.notices?.data
        note("コース", b.courses?.data, b.courses?.error, count: rawCourses.count)
        note("未完了の課題", b.events?.data, b.events?.error, count: rawEvents.count)
        note("今後の予定", b.upcoming?.data, b.upcoming?.error, count: rawUpcoming.count)
        note("通知", n, b.notices?.error, count: n?.notifications.count ?? 0)

        let courses = rawCourses.filter { $0.hidden != true }.map {
            Course(id: $0.id, fullName: $0.fullname.plainText, shortName: $0.shortname.plainText,
                   category: $0.coursecategory?.plainText, progress: $0.progress,
                   url: link($0.viewurl) ?? config.moodleCourse(id: $0.id))
        }
        // 「開始」の予定は締切ではない。過ぎた予定は、まだ操作できる（遅れて提出できる）ものだけ残す
        let now = Date.now
        var skipped = 0
        var deadlines: [Deadline] = rawEvents.compactMap { e in
            let due = Date(timeIntervalSince1970: TimeInterval(e.timesort ?? e.timestart ?? 0))
            if e.eventtype == "open" { skipped += 1; return nil }
            // 期限後も出せるのは課題（assign）だけ。アンケート・小テストなどは終了したら回答できない
            if due < now && (e.action?.actionable == false || (e.modulename ?? "assign") != "assign") { skipped += 1; return nil }
            return Deadline(id: "m-\(e.id)", title: e.name.plainText, course: e.course?.fullname.plainText,
                            due: due, url: link(e.url), needsAction: true, module: e.modulename)
        }
        if skipped > 0 { log("開始の予定・受付終了のもの \(skipped)件を除外", true) }
        // 未完了一覧が取れなかったときは「今後の予定」の締切で補う（提出済みかは分からない）
        if b.events?.data == nil {
            let ids = Set(deadlines.map(\.id))
            deadlines += rawUpcoming.filter(isDue).compactMap { e in
                let d = Deadline(id: "m-\(e.id)", title: e.name.plainText, course: e.course?.fullname.plainText,
                                 due: Date(timeIntervalSince1970: TimeInterval(e.timesort ?? e.timestart ?? 0)),
                                 url: link(e.url), needsAction: false)
                return ids.contains(d.id) ? nil : d
            }
        }
        let notices = (n?.notifications ?? []).map {
            MoodleNotice(id: $0.id, subject: $0.subject.plainText, time: Date(timeIntervalSince1970: TimeInterval($0.timecreated)),
                         read: $0.read, url: link($0.contexturl))
        }
        return MoodleSnapshot(courses: courses, deadlines: deadlines.sorted { $0.due < $1.due },
                              upcoming: rawUpcoming.map { item($0, link: link) }.sorted { $0.start < $1.start },
                              notices: notices,
                              unreadCount: n?.unreadcount ?? notices.filter { !$0.read }.count, warnings: warnings)
    }

    static func parseMonth(_ json: String, config: UniversityConfig) throws -> [CalendarItem] {
        guard let data = json.data(using: .utf8), let b = try? JSONDecoder().decode(MonthBundle.self, from: data) else { throw ParseError.invalid }
        if b.fatal != nil { throw ParseError.notLoggedIn(nil) }
        if let e = b.month?.error { throw WebError.script("カレンダー: \(e)") }
        let link = linker(config)
        var seen = Set<Int>()
        var out: [CalendarItem] = []
        for w in b.month?.data?.weeks ?? [] {
            for d in w.days { for e in d.events ?? [] where seen.insert(e.id).inserted { out.append(item(e, link: link)) } }
        }
        return out.sorted { $0.start < $1.start }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
