'use strict';
// 画面側の計算（やること・カレンダー・時間割・日付の書き方）。Mac版 AppStore / Domain.swift と同じ規則。

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'];
const DAY = 86400e3;

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// MARK: - 日付の書き方（日本語）

const pad2 = n => String(n).padStart(2, '0');
const Fmt = {
  md: t => { const d = new Date(t); return `${d.getMonth() + 1}月${d.getDate()}日`; },
  hm: t => { const d = new Date(t); return `${d.getHours()}:${pad2(d.getMinutes())}`; },
  hms: t => { const d = new Date(t); return `${d.getHours()}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`; },
  mdw: t => { const d = new Date(t); return `${Fmt.md(t)}(${WEEKDAYS[d.getDay()]})`; },
  mdwLong: t => { const d = new Date(t); return `${Fmt.md(t)} ${WEEKDAYS[d.getDay()]}曜日`; },
  mdwhm: t => `${Fmt.mdw(t)} ${Fmt.hm(t)}`,
  mdhm: t => `${Fmt.md(t)} ${Fmt.hm(t)}`,
  ym: d => `${d.getFullYear()}年${d.getMonth() + 1}月`,
};

function remainingText(t, now = Date.now()) {
  const s = (t - now) / 1000;
  if (s < 0) return '期限切れ';
  if (s < 3600) return `あと${Math.max(1, Math.floor(s / 60))}分`;
  if (s < 86400) return `あと${Math.floor(s / 3600)}時間`;
  return `あと${Math.floor(s / 86400)}日`;
}

function urgency(due, now = Date.now()) {
  const r = due - now;
  if (r < 0) return 'overdue';
  if (r < DAY) return 'urgent';
  if (r < 3 * DAY) return 'soon';
  return 'normal';
}

const startOfDay = t => { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); };
const sameDay = (a, b) => startOfDay(a) === startOfDay(b);
const monthKey = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;

// MARK: - 時間割・お知らせ

const Importance = {
  keywords: ['休講', '教室変更', '補講', '締切', '期限', '重要', '緊急', '至急', '変更'],
  is: t => Importance.keywords.some(k => String(t).includes(k)),
};

const Timetable = {
  dayChar: t => WEEKDAYS[new Date(t).getDay()],
  /** セルの文字を「科目名・その他の行」に分ける。1行目が科目コード（英数字だけ）なら2行目を科目名にする */
  split(text) {
    const lines = String(text).split('\n').map(s => s.trim()).filter(Boolean);
    let code = null;
    if (lines.length > 1 && /^[A-Za-z0-9_\-]{4,}$/.test(lines[0])) code = lines.shift();
    return { title: lines[0] ?? text, code, rest: lines.slice(1) };
  },
  /** 指定曜日の授業（空きコマは除く） */
  classes(tt, day) {
    return tt.periods.map(p => ({ period: p.label, text: String(p.byDay[day] ?? '').trim() }))
      .filter(c => c.text && c.text !== '-' && c.text !== '－');
  },
  /** 科目名を比べやすくする：全角→半角、カタカナ→ひらがな、【担当】・[曜限]・「後学期_」などの前置き・空白を除く */
  courseKey(s) {
    return String(s ?? '').normalize('NFKC')
      .replace(/【[^】]*】/g, '').replace(/\[[^\]]*\]/g, '')
      .replace(/^\s*(前学期|後学期|通年活動|通年)_/, '')
      .replace(/[\s_]/g, '').toLowerCase()
      .replace(/[\u30a1-\u30f6]/g, ch => String.fromCharCode(ch.charCodeAt(0) - 0x60));
  },
  /** 2つの科目名の似ている度合い（0〜1、2文字ずつの組の重なり）。「心理をよむ」と「心理を読む」のような表記ゆれ用 */
  similarity(a, b) {
    const grams = s => { const g = []; for (let i = 0; i < s.length - 1; i++) g.push(s.slice(i, i + 2)); return g; };
    const ga = grams(a), gb = grams(b);
    if (!ga.length || !gb.length) return 0;
    const rest = [...gb];
    let hit = 0;
    for (const g of ga) { const i = rest.indexOf(g); if (i >= 0) { hit++; rest.splice(i, 1); } }
    return (2 * hit) / (ga.length + gb.length);
  },
  /** 対応するコースが見つからないときに開く、Moodle のコース検索（科目名で探す） */
  searchURL(base, text) {
    const b = String(base ?? '').replace(/\/+$/, '');
    const q = String(Timetable.split(text).title).normalize('NFKC').replace(/【[^】]*】/g, '').replace(/\s+/g, ' ').trim();
    return /^https:\/\//i.test(b) && q ? `${b}/course/search.php?search=${encodeURIComponent(q)}` : null;
  },
  /** 時間割のコマに対応する Moodle のコース。見つからなければ null。
   *  ① 科目コード（時間割の B31L07K1 → Moodle の短縮名 …-B31L07K101）② 科目名 の順に強く見て、
   *  同じ名前が複数あるときは曜限（[火1]）と今の学期（4〜9月は前学期）が合うものを選ぶ */
  moodleCourse(courses, text, day, periodLabel, now = Date.now()) {
    const { title, code } = Timetable.split(text);
    const key = Timetable.courseKey(title);
    const per = (String(periodLabel ?? '').normalize('NFKC').match(/\d+/) || [])[0];
    const mon = new Date(now).getMonth() + 1;
    const term = mon >= 4 && mon <= 9 ? '前学期' : '後学期';
    let best = null, bestScore = 0;
    for (const c of courses ?? []) {
      if (!c?.url) continue;
      const full = String(c.fullName ?? '').normalize('NFKC');
      const short = String(c.shortName ?? '').normalize('NFKC');
      let s = 0;
      if (code && code.length >= 6 && (short.includes(code) || full.includes(code))) s += 10;
      const ck = Timetable.courseKey(c.fullName);
      const dp = full.match(/\[(.)(\d+)/);
      const samePeriod = !!dp && dp[1] === day && dp[2] === per;
      if (key.length >= 2 && ck === key) s += 6;
      else if (Math.min(key.length, ck.length) >= 3 && (ck.includes(key) || key.includes(ck))) s += 3;
      else if (alnum(key) === alnum(ck)) {
        // 表記ゆれ（ひらがな／漢字、副題の有無など）。「基礎1」と「基礎2」、「実習A」と「実習B」のように英数字が違うものは別の科目とみなす
        const sim = Timetable.similarity(key, ck);
        if (sim >= 0.75) s += 4;
        else if (sim >= 0.5) s += 3;
        else if (sim >= 0.3 && samePeriod) s += 2;
      }
      if (s === 0) continue;
      if (samePeriod) s += 2;
      if (full.includes(term)) s += 1;
      else if (/前学期|後学期/.test(full)) s -= 3;
      if (s >= 3 && s > bestScore) { best = c; bestScore = s; }
    }
    return best;
  },
};

/** 英数字の部分（「基礎1」の 1、「実習B」の b、「I」など）。ここが違えば別の科目とみなす */
const alnum = s => (String(s).match(/[a-z0-9]+/g) || []).join(',');

const SubmissionStatus = {
  label: s => ({ submitted: '提出済み', notOpenYet: '受付開始前', form: 'フォーム（提出は要確認）', formReceipt: 'フォーム回答済み（控えメールあり）' }[s] ?? null),
  isDone: s => s === 'submitted' || s === 'formReceipt',
};

const MailCategory = {
  all: ['action', 'classChange', 'exam', 'moodle', 'event', 'info', 'other'],
  label: c => ({ action: '要対応・締切', classChange: '休講・授業変更', exam: '試験・レポート', moodle: 'Moodle通知', event: '行事・説明会', info: '大学からのお知らせ', other: 'その他' }[c]),
  icon: c => ({ action: 'alertCircle', classChange: 'calAlert', exam: 'pencil', moodle: 'book', event: 'people', info: 'building', other: 'mail' }[c]),
};

// MARK: - 状態から求めるもの

function gmailURL(S, m) {
  const user = S.mail.value?.email ?? S.config.mail.address;
  return `https://mail.google.com/mail/u/?authuser=${encodeURIComponent(user)}#all/${encodeURIComponent(m.threadId)}`;
}

function moodleURL(S, p) {
  const b = String(S.config.moodleBaseURL || '').replace(/\/+$/, '');
  return /^https:\/\//i.test(b) ? b + p : null;
}

// MARK: - 休講・補講・教室変更の一覧（休講補講参照の一覧形式）

/** どれも「書かれている日の1回だけ」の変更。教室も、その日の授業の教室であって、ほかの週はいつもの教室 */
const ChangeList = {
  note: '今日から5週間のあいだに予定されている変更です。どれも書かれている日の1回だけで、ほかの週はいつもどおりです。',
  /** 休講補講参照の一覧形式で読んだ表か（列：日付・時限・時間割コード・科目・区分・この日の教室） */
  is: t => !!t && t.header?.[0] === '日付' && t.header?.[4] === '区分',
  /** 科目名から【担当】を除く */
  course: s => String(s ?? '').replace(/【[^】]*】/g, '').trim(),
  /** 区分ごとの、その日についての説明 */
  detail(kind, room) {
    if (kind === '休講') return 'この日の授業はありません';
    if (kind === '補講') return room ? `この日だけの授業（教室：${room}）` : 'この日だけの授業';
    if (kind === '教室変更') return room ? `この日だけ ${room} で授業（ほかの週はいつもの教室）` : 'この日だけ教室が変わります';
    return room ? `この日の教室：${room}` : '';
  },
  /** 1行にまとめた文（ホームのお知らせ用）：「12月19日(土) 1限 社会連携講座 → 補講（この日だけの授業・4312講義室）」 */
  line(r) {
    const [date, period, , course, kind, room] = r;
    const tail = kind === '休講' ? '' : room ? `（この日だけ・${room}）` : '（この日だけ）';
    return `${date} ${period} ${ChangeList.course(course)} → ${kind}${tail}`;
  },
};

// MARK: - 今週の分だけにする（ホームの「やること」）

/** 授業は週1回なので、ホームの「やること」に出す Moodle の締切は「あと7日」まで */
const WEEK_DAYS = 7;

/** 文の中の日付（「12/2(水)」「12月2日」「2026/12/2」）。年が無ければ now に近い年にする。見つからなければ null */
function guessDate(text, now = Date.now()) {
  const m = String(text ?? '').normalize('NFKC').match(/(?:(\d{4})\s*[\/年.-]\s*)?(\d{1,2})\s*[\/月]\s*(\d{1,2})\s*日?/);
  if (!m) return null;
  const mon = Number(m[2]) - 1, day = Number(m[3]);
  if (mon < 0 || mon > 11 || day < 1 || day > 31) return null;
  if (m[1]) return new Date(Number(m[1]), mon, day).getTime();
  const y = new Date(now).getFullYear();
  const cands = [y - 1, y, y + 1].map(yy => new Date(yy, mon, day).getTime());
  return cands.reduce((a, b) => (Math.abs(b - now) < Math.abs(a - now) ? b : a));
}

/** Campus Square で見つけた休講（休講ページの表の行と、ポータルのお知らせのうち「休講」を含む行）。[{ text, date }] */
function cancellations(S, now = Date.now()) {
  const c = S.campus.value;
  if (!c) return [];
  const lines = [
    ...(c.cancellations?.rows ?? []).map(r => r.filter(Boolean).join(' ')),
    ...(c.portlets ?? []).flatMap(p => p.lines ?? []),
  ];
  return lines.filter(l => /休講/.test(l)).map(text => ({ text, date: guessDate(text, now) })).filter(x => x.date != null);
}

/** Moodle の短縮名に入っている時間割コード（「後学期_微分積分学（メ）-B31N04K101」→ B31N04K1）。無ければ null */
function courseCode(shortName) {
  const m = String(shortName ?? '').normalize('NFKC').match(/-([A-Z0-9]{6,})\d{2}$/);
  return m ? m[1] : null;
}

/** 締切の科目に、今日から締切までの間の休講があるか（「来週は休講なので2週間前から出ている課題」）。あればその休講。
 *  code（時間割コード）があれば休講の行のコードでも照合する */
function cancelledBefore(course, due, list, now = Date.now(), code = null) {
  // 科目名から【】・[曜限]・学期・（メ）などのかっこを除いた中心の名前で、休講の行に含まれるかを見る
  const core = Timetable.courseKey(course).replace(/\([^)]*\)/g, '');
  const start = startOfDay(now);
  return list.find(x => x.date >= start && x.date <= due
    && ((code && x.text.normalize('NFKC').includes(code))
      || (core.length >= 3 && Timetable.courseKey(x.text).replace(/\([^)]*\)/g, '').includes(core)))) ?? null;
}

/** Moodle の未完了課題 ＋ メールで見つけた要対応。
 *  thisWeek: true（ホーム）のときは、受付開始前のものと、あと8日以上先のものを出さない。
 *  ただし先の締切でも、もう提出できるもの・締切までに休講があるもの（早めに出ている課題）は出す */
function todos(S, includeDone = false, now = Date.now(), { thisWeek = false } = {}) {
  const done = new Set(S.doneIDs);
  const items = [];
  const cancels = thisWeek ? cancellations(S, now) : [];
  const courses = S.moodle.value?.courses ?? [];
  const codeOf = name => courseCode(courses.find(c => c.fullName === name)?.shortName);
  for (const d of S.moodle.value?.deadlines ?? []) {
    if (SubmissionStatus.isDone(d.status)) continue;
    let early = null;
    if (thisWeek) {
      if (d.status === 'notOpenYet') continue;
      if (Math.floor((d.due - now) / DAY) > WEEK_DAYS) {
        const c = d.course ? cancelledBefore(d.course, d.due, cancels, now, codeOf(d.course)) : null;
        if (c) early = `締切は先ですが、${Fmt.md(c.date)}が休講なので早めに出ている課題です`;
        else if (d.status === 'notSubmitted' || d.status === 'form') early = '締切は先ですが、もう提出できます（早めに出ている課題）';
        else continue;
      }
    }
    const overdue = d.due < now;
    let reason;
    if (d.status === 'form') reason = '外部フォームです。提出したかはアプリから分からないので、済んだらチェックしてください';
    else if (d.status === 'notSubmitted') reason = overdue ? '期限を過ぎていて、まだ提出していません（ページで確認）' : 'まだ提出していません（ページで確認）';
    else if (d.status === 'notOpenYet') reason = 'まだ受付が始まっていません（開始されたら取り組む）';
    else if (!d.needsAction) reason = 'Moodleの予定にある締切（提出済みかは未確認）';
    else reason = overdue ? '期限を過ぎていますが、Moodle上でまだ完了していません' : 'Moodleで未提出・未完了';
    if (early) reason = early + (d.status === 'form' ? '（外部フォーム。済んだらチェック）' : '');
    items.push({
      id: d.id, title: d.title, detail: d.course, due: d.due, source: 'moodle',
      url: d.formURL ?? d.url ?? moodleURL(S, '/calendar/view.php?view=upcoming'), reason,
      overdueHint: overdue && d.needsAction && d.status !== 'form' && d.status !== 'notOpenYet',
    });
  }
  // コースのページにある、締切の書かれていないフォーム（今の回のものだけ。前の回のものは Moodle 画面にまとめる）
  for (const f of S.moodle.value?.forms ?? []) {
    if (!f.recent || SubmissionStatus.isDone(f.status)) continue;
    items.push({
      id: f.id, title: f.title, detail: f.course, due: null, source: 'moodle', url: f.formURL ?? f.url,
      reason: '外部フォームです（締切の記載なし）。提出したかはアプリから分からないので、済んだらチェックしてください',
      overdueHint: false,
    });
  }
  for (const m of S.mail.value?.messages ?? []) {
    if (m.category !== 'action') continue;
    if (m.dueDate != null && m.dueDate < now - 14 * DAY) continue;
    if (m.dueDate == null && m.date < now - 21 * DAY) continue;
    items.push({
      id: 'mail-' + m.id, title: m.subject, detail: m.from, due: m.dueDate, source: 'mail',
      url: gmailURL(S, m), reason: m.reasons.join(' / '), overdueHint: m.looksOverdue,
    });
  }
  const out = includeDone ? items : items.filter(i => !done.has(i.id));
  return out.sort((a, b) => {
    if (a.overdueHint !== b.overdueHint) return a.overdueHint ? -1 : 1;
    if (a.due != null && b.due != null) return a.due - b.due;
    if (a.due == null && b.due != null) return 1;
    if (a.due != null && b.due == null) return -1;
    return a.title < b.title ? -1 : a.title > b.title ? 1 : 0;
  });
}

/** その日の予定（授業・Moodleの予定・締切・メールの期限） */
function calendarItems(S, day) {
  const items = [];
  const tt = S.campus.value?.timetable;
  if (S.prefs.showTimetableInCalendar && tt) {
    const dc = Timetable.dayChar(day);
    Timetable.classes(tt, dc).forEach((c, i) => {
      const parts = Timetable.split(c.text);
      items.push({ id: `tt-${dc}-${i}`, title: parts.title, start: startOfDay(day) + i, kind: 'classSession', course: parts.rest[0] ?? null, periodLabel: c.period });
    });
  }
  const seen = new Set();
  const month = S.monthItems[monthKey(new Date(day))] ?? [];
  for (const e of [...month, ...(S.moodle.value?.upcoming ?? [])]) {
    if (sameDay(e.start, day) && !seen.has(e.id)) { seen.add(e.id); items.push(e); }
  }
  for (const d of S.moodle.value?.deadlines ?? []) {
    if (!sameDay(d.due, day)) continue;
    const id = 'c-' + d.id.slice(2);
    if (!seen.has(id)) { seen.add(id); items.push({ id, title: d.title, start: d.due, kind: 'deadline', course: d.course, url: d.url }); }
  }
  for (const m of S.mail.value?.messages ?? []) {
    if ((m.category === 'action' || m.category === 'classChange') && m.dueDate != null && sameDay(m.dueDate, day)) {
      items.push({ id: 'mail-' + m.id, title: m.subject, start: m.dueDate, kind: 'mail', course: m.from, url: gmailURL(S, m) });
    }
  }
  return items.sort((a, b) => {
    const ac = a.kind === 'classSession', bc = b.kind === 'classSession';
    if (ac !== bc) return ac ? -1 : 1;
    return a.start - b.start;
  });
}

function validURL(s) {
  try {
    const u = new URL(String(s).trim());
    return u.protocol === 'https:' && !!u.hostname && !u.username && !u.password ? u : null;
  } catch { return null; }
}

function isPlaceholder(u) {
  const h = u?.hostname?.toLowerCase();
  if (!h) return true;
  return h === 'example' || h.endsWith('.example') || h.endsWith('.invalid') || /example\.(com|org|net)$/.test(h);
}

if (typeof module !== 'undefined') {
  module.exports = { esc, Fmt, remainingText, urgency, startOfDay, sameDay, monthKey, Importance, Timetable, SubmissionStatus, MailCategory, todos, calendarItems, validURL, isPlaceholder, gmailURL, ChangeList, guessDate, cancellations, cancelledBefore, courseCode, WEEK_DAYS };
}
