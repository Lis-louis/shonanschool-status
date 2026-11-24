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
  /** 科目名を比べやすくする：全角→半角、【担当】・[曜限]・「後学期_」などの前置き・空白を除く */
  courseKey(s) {
    return String(s ?? '').normalize('NFKC')
      .replace(/【[^】]*】/g, '').replace(/\[[^\]]*\]/g, '')
      .replace(/^\s*(前学期|後学期|通年活動|通年)_/, '')
      .replace(/[\s_]/g, '').toLowerCase();
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
      if (key.length >= 2 && ck === key) s += 6;
      else if (Math.min(key.length, ck.length) >= 3 && (ck.includes(key) || key.includes(ck))) s += 3;
      if (s === 0) continue;
      const dp = full.match(/\[(.)(\d+)/);
      if (dp && dp[1] === day && dp[2] === per) s += 2;
      if (full.includes(term)) s += 1;
      else if (/前学期|後学期/.test(full)) s -= 3;
      if (s >= 3 && s > bestScore) { best = c; bestScore = s; }
    }
    return best;
  },
};

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

/** Moodle の未完了課題 ＋ メールで見つけた要対応 */
function todos(S, includeDone = false, now = Date.now()) {
  const done = new Set(S.doneIDs);
  const items = [];
  for (const d of S.moodle.value?.deadlines ?? []) {
    if (SubmissionStatus.isDone(d.status)) continue;
    const overdue = d.due < now;
    let reason;
    if (d.status === 'form') reason = '外部フォームです。提出したかはアプリから分からないので、済んだらチェックしてください';
    else if (d.status === 'notSubmitted') reason = overdue ? '期限を過ぎていて、まだ提出していません（ページで確認）' : 'まだ提出していません（ページで確認）';
    else if (d.status === 'notOpenYet') reason = 'まだ受付が始まっていません（開始されたら取り組む）';
    else if (!d.needsAction) reason = 'Moodleの予定にある締切（提出済みかは未確認）';
    else reason = overdue ? '期限を過ぎていますが、Moodle上でまだ完了していません' : 'Moodleで未提出・未完了';
    items.push({
      id: d.id, title: d.title, detail: d.course, due: d.due, source: 'moodle',
      url: d.formURL ?? d.url ?? moodleURL(S, '/calendar/view.php?view=upcoming'), reason,
      overdueHint: overdue && d.needsAction && d.status !== 'form' && d.status !== 'notOpenYet',
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
  module.exports = { esc, Fmt, remainingText, urgency, startOfDay, sameDay, monthKey, Importance, Timetable, SubmissionStatus, MailCategory, todos, calendarItems, validURL, isPlaceholder, gmailURL };
}
