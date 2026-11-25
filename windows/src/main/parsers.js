'use strict';
// Moodle の応答・メールの仕分け・日付の読み取り（Mac版の MoodleParser / MailClassifier / DateExtractor / GmailClient と同じ規則）。
// 日時はすべて「1970年からのミリ秒」で扱う。

const { SafeURL, Urls } = require('./config');

/** Moodle の文字列に残る HTML 実体参照・タグを取り除く */
function plainText(s) {
  let t = String(s ?? '').replace(/<[^>]+>/g, '');
  for (const [k, v] of [['&lt;', '<'], ['&gt;', '>'], ['&quot;', '"'], ['&#39;', "'"], ['&#039;', "'"], ['&nbsp;', ' ']]) t = t.split(k).join(v);
  t = t.replace(/&#(x[0-9A-Fa-f]+|[0-9]+);/g, (_, body) => {
    const code = body[0] === 'x' ? parseInt(body.slice(1), 16) : parseInt(body, 10);
    try { return String.fromCodePoint(code); } catch { return ''; }
  });
  return t.split('&amp;').join('&').trim();
}

class ParseError extends Error {}

const isDue = e => ['due', 'close', 'gradingdue', 'expectcompletionon'].includes(e.eventtype ?? '') || e.action != null;
const secToMs = s => (Number(s) || 0) * 1000;

function linker(config) {
  return s => {
    const u = s ? SafeURL.https(s) : null;
    return u && SafeURL.isTrusted(u, config.trustedDomain) ? u : null;
  };
}

function eventItem(e, link) {
  const start = secToMs(e.timestart ?? e.timesort ?? 0);
  const dur = secToMs(e.timeduration ?? 0);
  return {
    id: `c-${e.id}`, title: plainText(e.name), start, end: dur > 0 ? start + dur : null, allDay: false,
    kind: isDue(e) ? 'deadline' : 'moodleEvent', course: e.course ? plainText(e.course.fullname) : null,
    location: e.location ? plainText(e.location) || null : null, url: link(e.url), periodLabel: null,
  };
}

/** moodleFetch の結果（JSON文字列）を画面用のまとめに変える */
function parseMoodle(json, config, log = () => {}, now = Date.now()) {
  let b;
  try { b = JSON.parse(json); } catch (e) { log(`応答の形式が想定と違います: ${e.message}`, false); throw new ParseError('Moodleの応答を読み取れませんでした。'); }
  if (!b || typeof b !== 'object') throw new ParseError('Moodleの応答を読み取れませんでした。');
  if (b.fatal) throw new ParseError(`Moodleにログインできていません（開いていたページ: ${b.page ?? '不明'}）。`);
  const link = linker(config);

  const warnings = [];
  const note = (name, r, count) => {
    if (r?.error) { warnings.push(`${name}を取得できませんでした（${r.error}）`); log(`${name}: エラー ${r.error}`, false); }
    else log(`${name}: ${count}件`, true);
  };
  const rawCourses = b.courses?.data?.courses ?? [];
  const rawEvents = b.events?.data?.events ?? [];
  const rawUpcoming = b.upcoming?.data?.events ?? [];
  const n = b.notices?.data;
  note('コース', b.courses, rawCourses.length);
  note('未完了の課題', b.events, rawEvents.length);
  note('今後の予定', b.upcoming, rawUpcoming.length);
  note('通知', b.notices, n?.notifications?.length ?? 0);

  const courses = rawCourses.filter(c => c.hidden !== true).map(c => ({
    id: c.id, fullName: plainText(c.fullname), shortName: plainText(c.shortname),
    category: c.coursecategory != null ? plainText(c.coursecategory) : null, progress: c.progress ?? null,
    url: link(c.viewurl) ?? Urls.moodleCourse(config, c.id), endDate: c.enddate ? secToMs(c.enddate) : null,
  }));

  // 「開始」の予定は締切ではない。過ぎた予定は、まだ操作できる（遅れて提出できる）ものだけ残す
  let skipped = 0;
  let deadlines = [];
  for (const e of rawEvents) {
    const due = secToMs(e.timesort ?? e.timestart ?? 0);
    if (e.eventtype === 'open') { skipped++; continue; }
    // 期限後も出せるのは課題（assign）だけ。アンケート・小テストなどは終了したら回答できない
    if (due < now && (e.action?.actionable === false || (e.modulename ?? 'assign') !== 'assign')) { skipped++; continue; }
    deadlines.push(makeDeadline(e, due, link, true));
  }
  if (skipped > 0) log(`開始の予定・受付終了のもの ${skipped}件を除外`, true);
  // 未完了一覧が取れなかったときは「今後の予定」の締切で補う（提出済みかは分からない）
  if (b.events?.data == null) {
    const ids = new Set(deadlines.map(d => d.id));
    for (const e of rawUpcoming.filter(isDue)) {
      const d = makeDeadline(e, secToMs(e.timesort ?? e.timestart ?? 0), link, false);
      if (!ids.has(d.id)) deadlines.push(d);
    }
  }
  const notices = (n?.notifications ?? []).map(x => ({
    id: x.id, subject: plainText(x.subject), time: secToMs(x.timecreated), read: !!x.read, url: link(x.contexturl),
    // 課題・小テストなどの通知は、リンク先のページで提出済みか確かめる（store.checkSubmissions）
    status: 'unknown',
  }));
  deadlines = deadlines.sort((a, c) => a.due - c.due);
  // 月のカレンダーにだけある締切（提出ボタンのない課題など）。ページに外部フォームがあれば締切に加える（store.checkSubmissions）
  const known = new Set(rawEvents.map(e => e.id));
  const calendarDue = [];
  for (const m of b.calendar ?? []) {
    for (const w of m?.data?.weeks ?? []) for (const d of w.days ?? []) for (const e of d.events ?? []) {
      if (known.has(e.id) || !isDue(e) || !e.modulename) continue;
      known.add(e.id);
      const due = secToMs(e.timesort ?? e.timestart ?? 0);
      if (due >= now) calendarDue.push(makeDeadline(e, due, link, true));
    }
  }
  return {
    courses, deadlines, calendarDue,
    upcoming: rawUpcoming.map(e => eventItem(e, link)).sort((a, c) => a.start - c.start),
    notices, unreadCount: n?.unreadcount ?? notices.filter(x => !x.read).length, warnings,
  };
}

function makeDeadline(e, due, link, needsAction) {
  return {
    id: `m-${e.id}`, title: plainText(e.name), course: e.course ? plainText(e.course.fullname) : null,
    due, url: link(e.url), needsAction, module: needsAction ? (e.modulename ?? null) : null, status: 'unknown', formURL: null,
  };
}

function parseMonth(json, config) {
  let b;
  try { b = JSON.parse(json); } catch { throw new ParseError('Moodleの応答を読み取れませんでした。'); }
  if (!b || typeof b !== 'object') throw new ParseError('Moodleの応答を読み取れませんでした。');
  if (b.fatal) throw new ParseError('Moodleにログインできていません（開いていたページ: 不明）。');
  if (b.month?.error) throw new Error(`ページの読み取りに失敗しました：カレンダー: ${b.month.error}`);
  const link = linker(config);
  const seen = new Set();
  const out = [];
  for (const w of b.month?.data?.weeks ?? []) {
    for (const d of w.days ?? []) {
      for (const e of d.events ?? []) {
        if (seen.has(e.id)) continue;
        seen.add(e.id);
        out.push(eventItem(e, link));
      }
    }
  }
  return out.sort((a, c) => a.start - c.start);
}

const doneStatus = s => s === 'submitted' || s === 'formReceipt';

/** /mod/xxx/view.php?id=123 → "123"（同じ活動かどうかの照合用） */
function cmID(u) {
  try { const x = new URL(u); return /\/mod\/[a-z]+\/view\.php$/.test(x.pathname) ? x.searchParams.get('id') : null; } catch { return null; }
}

/** 活動の日付欄（「開始: … 期限: 2026年 12月 2日(水曜日) 23:59」）から締切を読む */
function activityDue(dates, now) {
  const t = String(dates ?? '').replace(/\s+/g, '');
  const all = DateExtractor.findAll(t, now);
  if (!all.length) return null;
  const hit = all.find(f => /(期限|終了|締切|締め切り|Due|Closes?)[:：]?$/i.test(t.slice(Math.max(0, f.start - 8), f.start)));
  return hit ? hit.date : all.length > 1 ? all[all.length - 1].date : /(開始|Opens?)[:：]?$/i.test(t.slice(0, all[0].start)) ? null : all[0].date;
}

/** moodleCourseForms の結果を、締切のあるフォーム（deadlines）と、締切の書かれていないフォーム（forms）に分ける。
 *  - 締切：活動の日付欄 →「12/2まで」などの文（名前・説明）の順に探す。過ぎたもの・表示期間より先のものは出さない
 *  - 締切なし：今のセクション（Moodle の強調表示）か、セクション名の日付が前後7日以内か、
 *    セクションに日付がないコースでは一番新しいセクションのものを recent にする（ホームの「やること」に出す） */
function parseCourseForms(json, config, courses, known, now = Date.now(), windowDays = 30) {
  let b;
  try { b = JSON.parse(json); } catch { return { deadlines: [], forms: [], stats: null, skipped: 0, checked: {} }; }
  const link = linker(config);
  const byID = new Map(courses.map(c => [String(c.id), c]));
  const seen = new Set(known);
  const deadlines = [], forms = [];
  let skipped = 0;
  const raw = (b?.forms ?? []).filter(f => f && f.form && f.cm);
  // セクション名の日付は授業の日（過ぎた日のことが多い）。2か月より先になるなら前の年とみなす（「6月2日」→ 今年の6月）
  const sectionDate = f => {
    const all = DateExtractor.findAll(String(f.section ?? '').normalize('NFKC').replace(/\s+/g, ''), now);
    if (!all.length) return null;
    const d = new Date(all[0].date);
    if (d.getTime() > now + 60 * 86400e3) d.setFullYear(d.getFullYear() - 1);
    return d.getTime();
  };
  const startToday = new Date(now).setHours(0, 0, 0, 0);
  const undated = [];
  for (const f of raw) {
    const formURL = SafeURL.https(f.form);
    const sdate = sectionDate(f);
    const url = link(f.url);
    const key = cmID(url) ?? `form:${formURL}`;
    if (!formURL || seen.has(key)) continue;
    seen.add(key);
    const course = byID.get(String(f.course));
    const title = plainText(f.name) || 'フォーム';
    // 締切：日付欄 → 名前の「締切：12月2日」→ 説明文の「〜まで」のすぐ近くの日付（説明文の関係ない日付は使わない）
    const nt = title.normalize('NFKC');
    let due = activityDue(f.dates, now) ?? DateExtractor.findDeadline(nt, now) ?? DateExtractor.findMarked(plainText(f.text ?? '').normalize('NFKC'), now);
    if (due == null && sdate != null) {
      const day = new Date(sdate);
      // 「次回授業前日夜23:59まで」「次回授業開始前まで」：授業は毎週なので、セクションの日の6日後 23:59
      if (/次回(の)?授業(の)?(前日|開始前|前|まで)/.test(nt)) { day.setDate(day.getDate() + 6); day.setHours(23, 59, 0, 0); due = day.getTime(); }
      // 「出席確認（15:30まで）」のように時刻だけのものは、セクションの日（授業の日）のその時刻
      const tm = due == null ? nt.match(/(\d{1,2}):(\d{2})\s*(まで|締切|〆切)/) : null;
      if (tm) { day.setHours(Number(tm[1]), Number(tm[2]), 0, 0); due = day.getTime(); }
    }
    const item = {
      id: `f-${f.cm}`, title, course: course?.fullName ?? null, url: url ?? course?.url ?? null,
      needsAction: true, module: f.mod ?? null, status: f.done ? 'submitted' : 'form', formURL,
    };
    if (due != null) {
      if (due < now || due > now + windowDays * 86400e3) { skipped++; continue; }
      deadlines.push({ ...item, due });
    } else if (sdate != null && sdate < now - 30 * 86400e3) {
      // 1か月以上前の回のフォーム（前学期など）は、もう受け付けていないとみなす
      skipped++;
    } else {
      undated.push({ f, item, sdate });
    }
  }
  // セクション名に日付のないコースは、フォームのある一番新しい（下の）セクションを今の回とみなす
  const latest = new Map();
  for (const u of undated) {
    const c = String(u.f.course);
    if (undated.some(x => String(x.f.course) === c && x.sdate != null)) continue;
    latest.set(c, Math.max(latest.get(c) ?? -1, Number(u.f.position) || 0));
  }
  for (const u of undated) {
    // 授業の日が今日を含む前6日〜7日後なら今の回（先週の同じ曜日の回は含めない）
    const near = u.sdate != null && u.sdate >= startToday - 6 * 86400e3 && u.sdate <= now + 7 * 86400e3;
    const last = latest.get(String(u.f.course)) === (Number(u.f.position) || 0);
    forms.push({ ...u.item, due: null, recent: !!u.f.current || near || last, section: plainText(u.f.section ?? '') || null });
  }
  deadlines.sort((a, c) => a.due - c.due);
  forms.sort((a, c) => (a.recent === c.recent ? 0 : a.recent ? -1 : 1));
  return { deadlines, forms, stats: b?.stats ?? null, skipped, checked: b?.checked ?? {} };
}

/** Moodle の活動（課題・小テスト・アンケートなど）のページか。通知のリンク先の提出状況を確かめる対象 */
function isActivityURL(u) {
  try { return /\/mod\/[a-z]+\/view\.php$/.test(new URL(u).pathname) && new URL(u).searchParams.has('id'); } catch { return false; }
}

// MARK: - 日付の読み取り

/** 日本語の文章から日付を見つける（「12月5日まで」「12/5(金)17:00締切」「2026年1月10日」など） */
const DateExtractor = {
  patterns: [
    /(20\d{2})[年/\-.](\d{1,2})[月/\-.](\d{1,2})日?/g,
    /(\d{1,2})月(\d{1,2})日/g,
    /(?<![\d/])(\d{1,2})\/(\d{1,2})(?![\d/])/g,
  ],
  markers: ['まで', '締切', '締め切り', '〆切', '期限', '必着'],

  findAll(text, reference) {
    const out = [];
    const ref = new Date(reference);
    for (const p of this.patterns) {
      for (const m of text.matchAll(p)) {
        const start = m.index, end = m.index + m[0].length;
        if (out.some(f => f.start < end && start < f.end)) continue;
        const g = m.slice(1).map(Number);
        let year, month, day;
        if (g.length === 3) [year, month, day] = g;
        else if (g.length === 2) [month, day] = g;
        else continue;
        if (!(month >= 1 && month <= 12 && day >= 1 && day <= 31)) continue;
        if (year == null) {
          // 年が書かれていない場合：基準日より大きく前なら翌年とみなす
          const refMonth = ref.getMonth() + 1;
          year = month + 3 < refMonth ? ref.getFullYear() + 1 : ref.getFullYear();
        }
        // 時刻（17:00 / 17時）
        let hour = 23, minute = 59;
        const tm = text.slice(end, end + 16).match(/(\d{1,2})[:：時](\d{2})?/);
        if (tm) {
          const hh = Number(tm[1]);
          if (hh < 24) { hour = hh; minute = tm[2] ? Number(tm[2]) : 0; }
        }
        out.push({ date: new Date(year, month - 1, day, hour, minute).getTime(), start, end });
      }
    }
    return out.sort((a, b) => a.start - b.start);
  },

  /** 「まで」「締切」などのすぐ近くにある日付だけを返す（長い文の中の関係ない日付を拾わない） */
  findMarked(text, reference) {
    for (const f of this.findAll(text, reference)) {
      const around = text.slice(f.start, f.start + 24);
      const before = text.slice(Math.max(0, f.start - 10), f.start);
      if (this.markers.some(k => around.includes(k) || before.includes(k))) return f.date;
    }
    return null;
  },

  /** 「まで」「締切」などの近くにある日付を優先して1つ返す */
  findDeadline(text, reference) {
    const all = this.findAll(text, reference);
    if (!all.length) return null;
    for (const f of all) {
      const around = text.slice(f.start, f.start + 24);
      const before = text.slice(Math.max(0, f.start - 10), f.start);
      if (this.markers.some(k => around.includes(k) || before.includes(k))) return f.date;
    }
    return this.markers.some(k => text.includes(k)) ? all[0].date : null;
  },
};

// MARK: - メールの仕分け

const MailClassifier = {
  actionWords: ['提出', '締切', '締め切り', '〆切', '期限', 'までに', '回答', '申請', '手続', '登録', '支払', '納付',
    '必ず', '至急', '要確認', '確認してください', '受付', '予約', '履修'],
  overdueWords: ['未提出', '未登録', '未納', '未回答', '未完了', '督促', '再提出', 'まだ提出', '提出されていません',
    '期限を過ぎ', '期限切れ', '最終案内', 'リマインド', '再送'],
  classChangeWords: ['休講', '補講', '教室変更', '授業変更', '遠隔授業', 'オンライン授業', '時間割変更'],
  examWords: ['試験', 'テスト', 'レポート', '追試', '再試'],
  eventWords: ['説明会', 'ガイダンス', 'セミナー', 'イベント', '就職', 'インターンシップ', '健康診断', 'オリエンテーション'],

  classify(m, trustedDomain) {
    const text = m.subject + ' ' + m.snippet;
    const domain = String(trustedDomain || '').toLowerCase();
    const addr = m.fromAddress.toLowerCase();
    const senderDomain = addr.split('@').pop() ?? '';
    m.isFromSchool = !!domain && (senderDomain === domain || senderDomain.endsWith('.' + domain));

    const hits = words => words.filter(w => text.includes(w));
    const reasons = [];
    const overdue = hits(this.overdueWords);
    const action = hits(this.actionWords);
    const change = hits(this.classChangeWords);
    const exam = hits(this.examWords);
    const event = hits(this.eventWords);
    const isMoodle = addr.includes('moodle') || m.from.toLowerCase().includes('moodle');

    m.dueDate = DateExtractor.findDeadline(text, m.date);
    m.looksOverdue = overdue.length > 0;

    if (change.length) {
      m.category = 'classChange'; reasons.push(`「${change.join('・')}」を含む`);
    } else if (overdue.length || (action.length && (m.dueDate != null || m.isFromSchool))) {
      m.category = 'action';
      if (overdue.length) reasons.push(`「${overdue.join('・')}」＝まだできていない可能性`);
      if (action.length) reasons.push(`「${action.slice(0, 3).join('・')}」を含む`);
    } else if (isMoodle) {
      m.category = 'moodle'; reasons.push('Moodleからの通知');
    } else if (exam.length) {
      m.category = 'exam'; reasons.push(`「${exam.join('・')}」を含む`);
    } else if (event.length) {
      m.category = 'event'; reasons.push(`「${event.join('・')}」を含む`);
    } else {
      m.category = m.isFromSchool ? 'info' : 'other';
    }
    if (m.dueDate != null) {
      const d = new Date(m.dueDate);
      reasons.push(`期限らしき日付: ${d.getMonth() + 1}月${d.getDate()}日`);
    }
    if (m.isFromSchool) reasons.push('大学のアドレスから');
    m.reasons = reasons;
    return m;
  },
};

// MARK: - Gmail

/** "山田 太郎 <taro@example.jp>" → ["山田 太郎", "taro@example.jp"] */
function parseFrom(raw) {
  const lt = raw.lastIndexOf('<'), gt = raw.lastIndexOf('>');
  if (lt >= 0 && gt > lt) {
    const addr = raw.slice(lt + 1, gt);
    const name = raw.slice(0, lt).trim().replace(/^"+|"+$/g, '');
    return [name || addr, addr];
  }
  const t = raw.trim();
  return [t, t];
}

/** API の応答を画面用のメールに変換し、分類する */
function convertGmail(m, trustedDomain) {
  const headers = m.payload?.headers ?? [];
  const h = n => headers.find(x => x.name.toLowerCase() === n.toLowerCase())?.value ?? '';
  const [name, address] = parseFrom(h('From'));
  const mail = {
    id: m.id, threadId: m.threadId, subject: h('Subject') || '（件名なし）', from: name, fromAddress: address,
    date: Number(m.internalDate ?? 0), snippet: plainText(m.snippet ?? ''), unread: (m.labelIds ?? []).includes('UNREAD'),
    category: 'other', isFromSchool: false, dueDate: null, looksOverdue: false, reasons: [],
  };
  return MailClassifier.classify(mail, trustedDomain);
}

/** 課題名から「(出席課題)」「（締切:…）」などを除いた、照合用の名前 */
function coreTitle(title) {
  let t = title;
  for (const p of [/[（(][^）)]*[）)]/g, /【[^】]*】/g, /\[[^\]]*\]/g]) t = t.replace(p, ' ');
  return t.replace(/\s+/g, '');
}

/** 控えメールの中に課題名があり、日付が締切の前後なら「回答済み」とみなす */
function hasReceipt(d, receipts) {
  const core = coreTitle(d.title);
  if ([...core].length < 3) return false;
  // 締切の書かれていないフォームは、控えメールの日付を問わない（控えメールは180日分）
  return receipts.some(r => r.text.replace(/\s+/g, '').includes(core)
    && (d.due == null || (r.date > d.due - 21 * 86400e3 && r.date < d.due + 86400e3)));
}

module.exports = {
  plainText, parseMoodle, parseMonth, ParseError, doneStatus, isActivityURL, cmID, activityDue, parseCourseForms,
  DateExtractor, MailClassifier,
  parseFrom, convertGmail, coreTitle, hasReceipt,
};
