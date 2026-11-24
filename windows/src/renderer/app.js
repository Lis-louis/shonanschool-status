'use strict';
/* global hub, icon, esc, Fmt, remainingText, urgency, startOfDay, sameDay, monthKey, Importance, Timetable, SubmissionStatus,
   MailCategory, todos, calendarItems, validURL, isPlaceholder, gmailURL */
// 画面（Mac版の SwiftUI の各 View と同じ構成）。状態はメインプロセスから受け取り、操作は hub.act() で送る。

// hub は preload.js の contextBridge が window.hub として渡す（書き換え不可のプロパティ）。
// ここで `const hub` と宣言し直すと SyntaxError になり画面が真っ白になるので、宣言せずにそのまま使う。
let S = null; // メインプロセスの状態
let ART = {};
const V = { // 画面だけの状態
  selection: 'home', moodleMode: 'summary', campusMode: 'summary',
  calMonth: (() => { const d = new Date(); return new Date(d.getFullYear(), d.getMonth(), 1); })(),
  calSelected: startOfDay(Date.now()),
  mailFilter: null, schoolOnly: true, showDone: {}, mailOpen: new Set(), portletOpen: new Set(),
  campusDay: Timetable.dayChar(Date.now()), diagAll: false, googleGuide: false,
  inputs: {}, errors: {},
};

const SECTIONS = [
  ['home', 'ホーム', 'home'], ['calendar', 'カレンダー', 'calendar'], ['moodle', 'Moodle', 'book'],
  ['campusSquare', 'Campus Square', 'building'], ['mail', 'メール', 'mail'], ['settings', '設定', 'sliders'],
];
const label = s => (s === 'moodle' ? 'Moodle' : 'Campus Square');
const attr = (k, v) => (v == null ? '' : ` data-${k}="${esc(v)}"`);
const DOT = c => `<span class="dot5" style="--c:var(--${c})"></span>`;

// MARK: - 部品

function card({ title, ic, trail, tinted, body }) {
  const head = title == null ? '' : `<div class="head">${ic ? `<span class="ic">${icon(ic)}</span>` : ''}<span class="title">${esc(title)}</span>`
    + `${trail ? `<span class="trail">${esc(trail)}</span>` : ''}<span class="spark">${icon('sparkle')}</span></div>`;
  return `<section class="card${tinted ? ' tinted' : ''}">${head}${body}</section>`;
}

const chip = (text, color = 'accent', ic) => `<span class="chip" style="--c:var(--${color})">${ic ? icon(ic) : ''}${esc(text)}</span>`;
const btn = (text, act, data = {}, kind = 'soft', extra = '') =>
  `<button class="btn ${kind}" data-act="${act}"${Object.entries(data).map(([k, v]) => attr(k, v)).join('')}${extra}>${text}</button>`;

function face(name, size) {
  const src = ART[name];
  return `<div class="face" style="width:${size}px;height:${size}px">${src ? `<img src="${src}" alt="">` : `<span style="font-size:${size * 0.4}px">鈴</span>`}</div>`;
}

function pageTitle(title, sub) {
  return `<div class="pagetitle"><div class="t"><h1>${icon('flower')}${esc(title)}</h1>${sub ? `<p>${esc(sub)}</p>` : ''}</div>${refreshButton()}</div>`;
}

function refreshButton(onHero) {
  const busy = S.isRefreshing;
  return `<button class="btn soft" data-act="refresh" ${busy ? 'disabled' : ''} title="最新の情報に更新（Ctrl+R）"${onHero ? '' : ''}>`
    + `${busy ? '<span class="spin"></span>' : icon('refresh')}${busy ? '更新中' : '更新'}</button>`;
}

function statusMsg(kind, message, opt = {}) {
  const ic = { loading: '<span class="spin"></span>', notConfigured: icon('userKey'), error: icon('triangle'), info: icon('leaf') }[kind];
  const buttons = [];
  if (opt.retry) buttons.push(btn('再試行', 'refresh'));
  if (opt.settings) buttons.push(btn('設定を開く', 'go', { s: 'settings' }));
  if (opt.loginService) buttons.push(btn('ブラウザでログイン', 'browserLogin', { s: opt.loginService }));
  return `<div class="status ${kind}"><span class="ic">${ic}</span><div><div class="msg">${esc(message)}</div>`
    + `${buttons.length ? `<div class="row">${buttons.join('')}</div>` : ''}</div></div>`;
}

/** 読み込み中・未連携・エラーをまとめて表示 */
function stateContent(state, service, fn, notConfiguredHTML) {
  switch (state.state) {
    case 'loading': return statusMsg('loading', `${service ? label(service) : 'メール'}から読み込み中…`);
    case 'notConfigured': return notConfiguredHTML ?? statusMsg('notConfigured', state.message, { settings: true, loginService: service });
    case 'failed': return statusMsg('error', state.message, { retry: true, loginService: notConfiguredHTML ? null : service });
    default: return fn(state.value);
  }
}

function sampleBanner() {
  return S.prefs.useSampleData ? `<div class="banner">${icon('masks')}サンプルデータを表示中です（実際の情報ではありません）</div>` : '';
}

const warnings = items => (items ?? []).map(w => statusMsg('error', w)).join('');

function noticeLine(text, read) {
  const imp = Importance.is(text);
  return `<div class="notice${imp ? ' important' : ''}${read ? ' read' : ''}"><span class="dot"></span><span>${esc(text)}</span></div>`;
}

function classCell(period, text) {
  const p = Timetable.split(text);
  const tag = text.includes('休講') ? chip('休講', 'alert') : text.includes('教室変更') ? chip('教室変更', 'warn') : '';
  return `<div class="classcell${Importance.is(text) ? ' important' : ''}"><div class="p">${esc(period)}</div><div>`
    + `<div class="name">${esc(p.title)}${tag}</div>${p.rest.slice(0, 3).map(l => `<div class="small">${esc(l)}</div>`).join('')}`
    + `${p.code ? `<div class="code">${esc(p.code)}</div>` : ''}</div></div>`;
}

function deadlineRow(d) {
  const done = SubmissionStatus.isDone(d.status);
  const u = done ? 'normal' : urgency(d.due);
  const color = done ? 'ok' : u === 'overdue' || u === 'urgent' ? 'alert' : u === 'soon' ? 'warn' : 'accent2';
  const lbl = SubmissionStatus.label(d.status);
  const right = lbl
    ? chip(lbl, done ? 'ok' : d.status === 'notOpenYet' ? 'subtle' : 'warn', done ? 'checkCircle' : d.status === 'notOpenYet' ? 'clock' : 'question')
    : chip(remainingText(d.due), u === 'normal' ? 'accent' : color);
  return `<button class="plain" data-act="openMoodle" data-url="${esc(d.url ?? '')}"><div class="deadline${u !== 'normal' ? ' hot' : ''}" style="--c:var(--${color})">`
    + `<span class="bar"></span><div class="body"><div class="ttl">${esc(d.title)}</div>`
    + `${d.course ? `<div class="small">${esc(d.course)}</div>` : ''}`
    + `<div class="small">${Fmt.mdwhm(d.due)}${d.needsAction ? '' : '（提出済みかは未確認）'}</div></div>${right}</div></button>`;
}

function linkRow(title, ic, act, data, sub, external) {
  return `<button class="plain" data-act="${act}"${Object.entries(data).map(([k, v]) => attr(k, v)).join('')}><div class="linkrow">`
    + `<span class="ic">${icon(ic)}</span><span class="t">${esc(title)}${sub ? `<small>${esc(sub)}</small>` : ''}</span>`
    + `<span class="go">${icon(external ? 'external' : 'right')}</span></div></button>`;
}

function toggle(text, key, { disabled = false, small = false, view = false } = {}) {
  const on = view ? !!V[key] : !!S.prefs[key];
  return `<label class="switch${small ? ' small' : ''}"><input type="checkbox" ${view ? `data-view="${key}"` : `data-pref="${key}"`} ${on ? 'checked' : ''} ${disabled ? 'disabled' : ''}>`
    + `<span${small ? ' class="small"' : ''}>${esc(text)}</span></label>`;
}

// MARK: - やること・メール

function todoCard(onlySource, limit = 30) {
  const key = onlySource ?? 'all';
  const showDone = !!V.showDone[key];
  const done = new Set(S.doneIDs);
  const all = todos(S, showDone).filter(t => !onlySource || t.source === onlySource);
  const hot = all.filter(t => !done.has(t.id) && (t.overdueHint || (t.due != null && t.due < Date.now() + 86400e3))).length;
  let body = '';
  if (hot > 0) body += `<div class="hot-label">${icon('alertCircle')}期限切れ・督促・24時間以内が ${hot} 件</div>`;
  if (!all.length) body += statusMsg('info', '今のところ、やることは見つかっていません。');
  body += all.slice(0, limit).map(todoRow).join('');
  body += `<label class="switch"><input type="checkbox" data-showdone="${key}" ${showDone ? 'checked' : ''}><span class="small">完了にしたものも表示</span></label>`;
  return card({ title: onlySource === 'mail' ? 'メールで見つけたやること' : 'やること（まだできていないこと）', ic: 'checklist', tinted: hot > 0, trail: `${all.length}件`, body });
}

function todoRow(t) {
  const done = S.doneIDs.includes(t.id);
  const overdue = t.overdueHint || (t.due != null && t.due < Date.now());
  const soon = t.due != null && t.due < Date.now() + 86400e3;
  const color = done ? 'subtle' : overdue || soon ? 'alert' : 'accent';
  const right = t.due != null
    ? `<div class="due">${chip(remainingText(t.due), color)}<span class="tiny">${Fmt.mdhm(t.due)}</span></div>`
    : t.overdueHint ? chip('督促', 'alert') : '';
  return `<div class="todo${done ? ' done' : ''}" style="--c:var(--${done ? 'ok' : color})">`
    + `<button class="check" data-act="toggleDone" data-id="${esc(t.id)}" title="${done ? '未完了に戻す' : '完了にする'}">${icon(done ? 'checkCircle' : 'circle')}</button>`
    + `<button class="plain body" data-act="${t.source === 'moodle' ? 'openMoodle' : 'openExternal'}" data-url="${esc(t.url ?? '')}">`
    + `<div class="ttl"><span class="tiny">${icon(t.source === 'moodle' ? 'book' : 'mail')}</span>${esc(t.title)}</div>`
    + `${t.detail ? `<div class="small">${esc(t.detail)}</div>` : ''}<div class="tiny" style="${overdue && !done ? 'color:var(--alert)' : ''}">${esc(t.reason)}</div></button>`
    + `${right}</div>`;
}

function mailRow(m) {
  const open = V.mailOpen.has(m.id);
  const color = m.category === 'action' ? 'alert' : m.category === 'classChange' ? 'warn' : 'accent2';
  const chips = [m.unread ? chip('未読', 'blush') : '', m.looksOverdue ? chip('督促・未完了？', 'alert') : '', m.dueDate != null ? chip('期限 ' + Fmt.md(m.dueDate), 'alert') : ''].join('');
  return `<div class="mailrow${m.category === 'action' ? ' action' : ''}${open ? ' open' : ''}" data-act="toggleMail" data-id="${esc(m.id)}" style="--c:var(--${color})">`
    + `<div class="top"><span class="ic">${icon(MailCategory.icon(m.category))}</span><div class="body">`
    + `<div class="subj">${m.unread ? `<b>${esc(m.subject)}</b>` : `<span class="s">${esc(m.subject)}</span>`}<span class="small">${Fmt.md(m.date)}</span></div>`
    + `<div class="row" style="gap:6px"><span class="small">${esc(m.from)}</span>${chips}</div>`
    + `<div class="snip">${esc(m.snippet)}</div>`
    + `${open && m.reasons.length ? `<div class="why">仕分けの理由：${esc(m.reasons.join(' / '))}</div>` : ''}`
    + `${open ? `<div class="row" style="margin-top:6px">${btn('Gmailで開く', 'openExternal', { url: gmailURL(S, m) })}</div>` : ''}`
    + '</div></div></div>';
}

// MARK: - ホーム

function greeting() {
  const h = new Date().getHours();
  return h >= 4 && h < 11 ? 'おはようございます' : h >= 11 && h < 17 ? 'こんにちは' : 'こんばんは';
}

function homeView() {
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  const hero = ART[dark ? 'hero_night' : 'hero_day'];
  const now = Date.now();
  let html = `<div class="hero">${hero ? `<img src="${hero}" alt="">` : ''}<div class="over"><div class="t">`
    + `<div class="greet">${greeting()}</div><div class="date">${Fmt.mdwLong(now)}</div><div class="uni">${esc(S.config.universityName)}</div></div>`
    + `${refreshButton(true)}</div></div>`;
  html += sampleBanner();

  if (S.prefs.showTodayClasses) {
    const day = Timetable.dayChar(now);
    html += card({
      title: '今日の授業', ic: 'clock', trail: `${day}曜日`,
      body: stateContent(S.campus, 'campus', snap => {
        if (!snap.timetable) return statusMsg('info', '時間割を読み取れていません。Campus Squareのページで確認してください。');
        const today = Timetable.classes(snap.timetable, day);
        return today.length ? today.map(c => classCell(c.period, c.text)).join('') : statusMsg('info', '今日の授業はありません。ゆっくり休んでね。');
      }) + `<div class="row">${btn('Campus Squareの時間割へ', 'openCampus', { url: S.config.campusSquare.timetable })}</div>`,
    });
  }

  if (S.prefs.showDeadlines) {
    if ((S.moodle.state === 'loading' || S.mail.state === 'loading') && todos(S).length === 0) {
      html += card({ title: 'やること（まだできていないこと）', ic: 'checklist', body: statusMsg('loading', 'Moodleとメールから読み込み中…') });
    } else {
      html += todoCard(null, 6);
      if (S.moodle.state === 'failed') html += statusMsg('error', 'Moodle：' + S.moodle.message, { retry: true, loginService: 'moodle' });
      if (S.moodle.state === 'notConfigured') html += statusMsg('notConfigured', 'Moodle：' + S.moodle.message, { settings: true, loginService: 'moodle' });
    }
  }

  if (S.prefs.showNotices) {
    let body = '';
    const m = S.moodle.value;
    if (m && m.notices.length) {
      body += `<div class="sub">Moodleの通知${m.unreadCount > 0 ? chip(`未読 ${m.unreadCount}`, 'blush') : ''}</div>`;
      body += m.notices.slice(0, 3).map(n => `<button class="plain" data-act="openMoodle" data-url="${esc(n.url ?? '')}" data-fallback="notifications">${noticeLine(n.subject, n.read)}</button>`).join('');
    }
    body += stateContent(S.campus, 'campus', snap => {
      const lines = snap.portlets.flatMap(p => p.lines);
      const important = lines.filter(Importance.is);
      const cancelRows = (snap.cancellations?.rows ?? []).map(r => r.filter(Boolean).join(' '));
      if (!important.length && !cancelRows.length && !snap.portlets.length) return statusMsg('info', '新しいお知らせは見つかりませんでした。');
      let h = '<div class="sub">Campus Square</div>';
      h += [...cancelRows.slice(0, 3), ...important.slice(0, 5)].map(l => noticeLine(l)).join('');
      if (!important.length && !cancelRows.length) h += lines.slice(0, 4).map(l => noticeLine(l)).join('');
      return h + `<div class="row">${btn('Campus Squareのお知らせを見る', 'go', { s: 'campusSquare', mode: 'summary' })}</div>`;
    });
    html += card({ title: '大学からのお知らせ', ic: 'megaphone', body });
  }

  if (S.prefs.showMail) {
    html += card({
      title: '大学メール', ic: 'mail', trail: S.mail.value ? `未読 ${S.mail.value.unreadCount}` : null,
      body: stateContent(S.mail, null, snap => {
        const school = snap.messages.filter(x => x.isFromSchool && (x.unread || x.category === 'action' || x.category === 'classChange'));
        const h = school.length ? '<div class="sub">学校から届いていること</div>' + school.slice(0, 4).map(mailRow).join('')
          : statusMsg('info', '大学からの未読・要対応メールはありません。');
        return h + `<div class="row">${btn('メールをすべて見る', 'go', { s: 'mail' })}</div>`;
      }, statusMsg('notConfigured', S.mail.message ?? '', { settings: true })),
    });
  }
  if (S.lastUpdated) html += `<div class="small center">最終更新 ${Fmt.hm(S.lastUpdated)}</div>`;
  return html;
}

// MARK: - カレンダー

function calendarView() {
  const m = V.calMonth;
  const key = monthKey(m);
  const first = new Date(m.getFullYear(), m.getMonth(), 1);
  const count = new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate();
  const cells = Array(first.getDay()).fill(null);
  for (let d = 1; d <= count; d++) cells.push(new Date(m.getFullYear(), m.getMonth(), d).getTime());
  while (cells.length % 7) cells.push(null);

  let grid = ['日', '月', '火', '水', '木', '金', '土'].map((d, i) => `<div class="wd${i === 0 ? ' sun' : i === 6 ? ' sat' : ''}">${d}</div>`).join('');
  for (const day of cells) {
    if (day == null) { grid += '<div></div>'; continue; }
    const kinds = new Set(calendarItems(S, day).map(i => i.kind));
    const today = sameDay(day, Date.now()), sel = sameDay(day, V.calSelected);
    grid += `<button class="day${today ? ' today' : ''}${sel ? ' sel' : ''}" data-act="calSelect" data-t="${day}"><span class="n">${new Date(day).getDate()}</span><span class="dots">`
      + (kinds.has('classSession') ? DOT('accent2') : '') + (kinds.has('moodleEvent') ? DOT('mint') : '')
      + (kinds.has('deadline') ? DOT('alert') : '') + (kinds.has('mail') ? DOT('blush') : '') + '</span></button>';
  }
  const loadingMonth = S.monthLoading.includes(key);
  const err = S.monthErrors[key];
  let html = pageTitle('カレンダー', '授業・課題・予定');
  html += card({
    body: `<div class="cal-head">${btn(icon('left'), 'calShift', { n: -1 })}<div class="m"><b>${Fmt.ym(m)}</b>`
      + `${loadingMonth ? '<span class="tiny">Moodleの予定を読み込み中…</span>' : ''}</div>${btn('今日', 'calToday')}${btn(icon('right'), 'calShift', { n: 1 })}</div>`
      + `<div class="cal-grid">${grid}</div>`
      + `<div class="legend"><span>${DOT('accent2')}授業</span><span>${DOT('mint')}予定</span><span>${DOT('alert')}締切</span><span>${DOT('blush')}メール</span></div>`
      + (err ? statusMsg('error', `Moodleの予定を読み込めませんでした：${err}`, { retry: true }) : ''),
  });
  const items = calendarItems(S, V.calSelected);
  html += card({
    title: Fmt.mdwLong(V.calSelected), ic: 'timeline', trail: items.length ? `${items.length}件` : null,
    body: items.length ? items.map(calRow).join('') : statusMsg('info', '予定はありません。'),
  });
  html += toggle('毎週の時間割をカレンダーに表示する（祝日・休暇は反映されません）', 'showTimetableInCalendar', { small: true });
  return html;
}

function calRow(item) {
  const color = { classSession: 'accent2', moodleEvent: 'mint', deadline: 'alert', mail: 'blush' }[item.kind];
  const lbl = item.kind === 'classSession' ? (item.periodLabel ?? '授業') : item.allDay ? '終日' : Fmt.hm(item.start);
  const tags = (item.kind === 'deadline' ? chip('締切', 'alert') : '') + (item.kind === 'mail' ? chip('メールの期限', 'blush') : '')
    + (item.title.includes('休講') ? chip('休講', 'alert') : '');
  const act = item.kind === 'mail' ? `data-act="openExternal" data-url="${esc(item.url ?? '')}"`
    : item.kind === 'classSession' ? `data-act="openCampus" data-url="${esc(S.config.campusSquare.timetable)}"`
      : `data-act="openMoodle" data-url="${esc(item.url ?? '')}"`;
  return `<button class="plain" ${act}><div class="calrow" style="--c:var(--${color})"><span class="lbl">${esc(lbl)}</span><span class="bar"></span>`
    + `<div class="body"><div class="ttl">${esc(item.title)}${tags}</div>${item.course ? `<div class="small">${esc(item.course)}</div>` : ''}`
    + `${item.location ? `<div class="small">${icon('pin')} ${esc(item.location)}</div>` : ''}</div></div></button>`;
}

// MARK: - Moodle

function moodleView() {
  const c = S.config;
  let html = pageTitle('Moodle', 'コース・課題・教材') + sampleBanner();
  html += card({
    title: '課題・締切', ic: 'flag', trail: `過去7日〜${S.prefs.deadlineWindowDays}日後`,
    body: stateContent(S.moodle, 'moodle', snap => {
      const open = snap.deadlines.filter(d => !SubmissionStatus.isDone(d.status));
      const done = snap.deadlines.filter(d => SubmissionStatus.isDone(d.status));
      let h = open.length ? open.map(deadlineRow).join('') : statusMsg('info', '提出が必要な課題はありません。');
      if (done.length) h += `<details><summary>提出済み・回答済み（${done.length}件）</summary><div class="stack">${done.map(deadlineRow).join('')}</div></details>`;
      return h + warnings(snap.warnings);
    }),
  });
  const snap = S.moodle.value;
  if (snap && snap.notices.length) {
    html += card({
      title: '通知', ic: 'bell', trail: snap.unreadCount > 0 ? `未読 ${snap.unreadCount}` : null,
      body: snap.notices.slice(0, 10).map(n => `<button class="plain" data-act="openMoodle" data-url="${esc(n.url ?? '')}" data-fallback="notifications">`
        + `<div class="row" style="flex-wrap:nowrap;align-items:flex-start"><div style="flex:1">${noticeLine(n.subject, n.read)}</div><span class="small">${Fmt.md(n.time)}</span></div></button>`).join(''),
    });
  }
  html += card({
    title: 'コース（教材）', ic: 'books',
    body: stateContent(S.moodle, 'moodle', s => (s.courses.length ? s.courses.map(co => `<button class="plain" data-act="openMoodle" data-url="${esc(co.url ?? '')}">`
      + `<div class="course"><div class="n"><span style="flex:1">${esc(co.fullName)}</span><span class="small">${icon('right')}</span></div>`
      + `${co.category ? `<div class="small">${esc(co.category)}</div>` : ''}`
      + `${co.progress != null ? `<div class="row" style="flex-wrap:nowrap"><div class="softbar"><i style="width:${Math.min(100, Math.max(0, co.progress))}%"></i></div><span class="tiny">${Math.floor(co.progress)}%</span></div>` : ''}`
      + '</div></button>').join('') : statusMsg('info', '受講中のコースはありません。'))),
  });
  const base = String(c.moodleBaseURL).replace(/\/+$/, '');
  html += card({
    title: 'Moodleのページ', ic: 'compass',
    body: linkRow('ダッシュボード', 'grid', 'openMoodle', { url: base + '/my/' })
      + linkRow('マイコース', 'books', 'openMoodle', { url: base + '/my/courses.php' })
      + linkRow('今後の予定（カレンダー）', 'calendar', 'openMoodle', { url: base + '/calendar/view.php?view=upcoming' })
      + linkRow('通知一覧', 'bell', 'openMoodle', { url: base + '/message/output/popup/notifications.php' }),
  });
  return html;
}

// MARK: - Campus Square

function campusView() {
  const cs = S.config.campusSquare;
  let html = pageTitle('Campus Square', '時間割・休講・お知らせ') + sampleBanner();
  html += card({
    title: '時間割', ic: 'table',
    body: stateContent(S.campus, 'campus', snap => {
      let h;
      if (snap.timetable) {
        const tt = snap.timetable;
        if (!tt.days.includes(V.campusDay)) V.campusDay = tt.days[0];
        h = `<div class="seg full">${tt.days.map(d => `<button class="${d === V.campusDay ? 'on' : ''}" data-act="campusDay" data-d="${esc(d)}">${esc(d)}</button>`).join('')}</div>`;
        const list = Timetable.classes(tt, V.campusDay);
        h += list.length ? list.map(x => classCell(x.period, x.text)).join('') : statusMsg('info', `${V.campusDay}曜日の授業はありません。`);
      } else {
        h = statusMsg('info', '時間割の表を見つけられませんでした。「ブラウザ」で時間割のページを開き、右上の「…」から「このページを時間割に設定」を選んでください。');
      }
      return h + warnings(snap.warnings);
    }),
  });
  const t = S.campus.value?.cancellations;
  if (t && t.rows.length) {
    html += card({
      title: t.title || '休講・補講', ic: 'bubble', tinted: true,
      body: t.rows.slice(0, 30).map(row => `<div class="tablerow${Importance.is(row.join(' ')) ? ' important' : ''}">`
        + row.map((v, i) => (v ? `<div><span class="k">${esc(t.header[i] ?? '')}</span><span>${esc(v)}</span></div>` : '')).join('') + '</div>').join(''),
    });
  }
  for (const p of S.campus.value?.portlets ?? []) {
    const open = V.portletOpen.has(p.title);
    html += card({
      title: p.title, ic: 'megaphone', tinted: p.lines.some(Importance.is),
      body: p.lines.slice(0, open ? 40 : 6).map(l => noticeLine(l)).join('')
        + `<div class="row">${p.lines.length > 6 ? btn(open ? '閉じる' : `もっと見る（${p.lines.length}行）`, 'portlet', { t: p.title }) : ''}`
        + `${btn('ポータルで開く', 'openCampus', { url: cs.portal })}</div>`,
    });
  }
  const att = validURL(cs.attendance);
  html += card({
    title: 'Campus Squareのページ', ic: 'compass',
    body: linkRow('ポータル（トップ）', 'home', 'openCampus', { url: cs.portal })
      + linkRow('時間割・履修', 'table', 'openCampus', { url: cs.timetable })
      + linkRow('休講・補講・教室変更', 'bubble', 'openCampus', { url: cs.cancellations })
      + linkRow('成績', 'chart', 'openCampus', { url: cs.grades })
      + linkRow('シラバス', 'textbook', 'openCampus', { url: cs.syllabus })
      + linkRow('出席管理', 'check', 'openExternal', { url: cs.attendance }, att?.hostname, true),
  });
  return html;
}

// MARK: - メール

function mailView() {
  let html = pageTitle('メール', '大学のGmailを自動で仕分け') + sampleBanner();
  const guide = card({
    title: 'Gmailとの連携', ic: 'envBadge',
    body: statusMsg('notConfigured', S.mail.message ?? '')
      + '<div class="small">大学メールは Google Workspace（Gmail）です。Google公式のログイン（ブラウザ）で読み取り専用の許可を出すと、メールを取得して自動で仕分けます。</div>'
      + `<div class="row">${btn('設定を開く', 'go', { s: 'settings' }, 'primary')}${btn('Gmailを開く', 'openExternal', { url: S.config.mail.webURL })}</div>`,
  });
  html += stateContent(S.mail, 'moodle', snap => {
    const school = snap.messages.filter(m => m.isFromSchool);
    const counts = {};
    for (const m of snap.messages) counts[m.category] = (counts[m.category] ?? 0) + 1;
    const overdueN = snap.messages.filter(m => m.looksOverdue).length;
    const stat = (v, l, c) => `<div style="--c:var(--${c ?? 'accent'})"><b>${v}</b><span class="small">${l}</span></div>`;
    const chipBtn = (c, l, n) => `<button class="${V.mailFilter === c ? 'on' : ''}" data-act="mailFilter" data-c="${c ?? ''}" style="--c:var(--${c === 'action' ? 'alert' : 'accent'})">${esc(l)} ${n}</button>`;
    let h = card({
      title: '学校から届いていること', ic: 'sparkles', trail: snap.email,
      body: `<div class="stats">${stat(school.length, '大学から')}${stat(school.filter(m => m.unread).length, 'うち未読')}`
        + `${stat(counts.action ?? 0, '要対応', counts.action ? 'alert' : null)}${stat(overdueN, '督促・未完了', overdueN ? 'alert' : null)}</div>`
        + `<div class="chips">${chipBtn(null, 'すべて', snap.messages.length)}${MailCategory.all.filter(c => counts[c]).map(c => chipBtn(c, MailCategory.label(c), counts[c])).join('')}</div>`,
    });
    h += todoCard('mail');
    const items = snap.messages.filter(m => (!V.mailFilter || m.category === V.mailFilter) && (!V.schoolOnly || m.isFromSchool || m.category === 'moodle'));
    h += card({
      title: V.mailFilter ? MailCategory.label(V.mailFilter) : 'メール一覧', ic: V.mailFilter ? MailCategory.icon(V.mailFilter) : 'tray', trail: `${items.length}通`,
      body: toggle('大学・Moodleからのメールだけ', 'schoolOnly', { view: true })
        + (items.length ? items.slice(0, 80).map(mailRow).join('') : statusMsg('info', '該当するメールはありません。'))
        + `<div class="tiny">検索条件：${esc(S.config.mail.searchQuery)}</div>`,
    });
    return h;
  }, guide);
  return html;
}

// MARK: - 設定

function field(title, cfgKey, { isURL = true, placeholder } = {}) {
  const k = 'cfg:' + cfgKey;
  const value = k in V.inputs ? V.inputs[k] : cfgKey.split('.').reduce((o, x) => o?.[x], S.config) ?? '';
  let note = '';
  if (isURL) {
    const u = validURL(value);
    if (!u) note = '<div class="err">https:// で始まる正しいURLを入力してください</div>';
    else if (isPlaceholder(u)) note = '<div class="warnmsg">仮の値です。大学の公式URLに置き換えてください。</div>';
  }
  return `<div class="field"><label>${esc(title)}</label><input class="input" data-keep="${k}" data-config="${esc(cfgKey)}" value="${esc(value)}" `
    + `placeholder="${esc(placeholder ?? (isURL ? 'https://…' : ''))}" spellcheck="false" autocomplete="off">${note}</div>`;
}

function credentialEditor(service, title) {
  const saved = S.savedUsername[service];
  const u = `cred:${service}:u`, p = `cred:${service}:p`;
  return `<div style="display:flex;flex-direction:column;gap:8px"><div class="row"><span class="sub" style="flex:1">${esc(title)}</span>`
    + (saved ? chip(`保存済み：${saved}`, 'ok', 'checkSeal') + btn('削除', 'delCred', { s: service }) : chip('未保存', 'subtle')) + '</div>'
    + `<input class="input" data-keep="${u}" value="${esc(V.inputs[u] ?? '')}" placeholder="学籍番号（ユーザー名）" autocomplete="off" spellcheck="false">`
    + `<input class="input" type="password" data-keep="${p}" data-enter="saveCred" data-s="${service}" value="${esc(V.inputs[p] ?? '')}" placeholder="パスワード" autocomplete="off">`
    + `<div class="row">${btn('暗号化して保存', 'saveCred', { s: service }, 'primary', !(V.inputs[u] && V.inputs[p]) ? ' disabled' : '')}`
    + `${V.errors[service] ? `<span class="err">${esc(V.errors[service])}</span>` : ''}</div></div>`;
}

function settingsView() {
  const pr = S.prefs;
  let html = pageTitle('設定', 'ログイン情報・URL・表示');
  html += card({
    title: 'ログイン情報', ic: 'userKey',
    body: credentialEditor('moodle', pr.sameCredentials ? 'Moodle / Campus Square 共通' : 'Moodle')
      + toggle('Campus Squareも同じID・パスワードを使う', 'sameCredentials')
      + (pr.sameCredentials ? '' : '<hr>' + credentialEditor('campus', 'Campus Square'))
      + `<div class="small">ID・パスワードはこのPCにだけ、Windowsのユーザーアカウントに結びついた暗号化（DPAPI）で保存されます。`
      + `使うのは、設定した大学の公式ログインページ（${esc(S.config.trustedDomain)}）の入力欄に入れるときだけです。</div>`
      + (S.encryptionAvailable ? '' : statusMsg('error', 'このPCでは暗号化した保存が使えないため、ID・パスワードを保存できません。')),
  });
  html += gmailSettings();
  html += card({
    title: 'ログインの動き', ic: 'wand',
    body: toggle('自動でログインする', 'autoLogin') + toggle('大学のページに鈴テーマの配色を重ねる', 'themeOfficialPages')
      + `<div class="row">${btn('ログイン状態を消去（ログアウト）', 'clearSessions', {}, 'danger')}</div>`,
  });
  html += card({
    title: '大学・URL', ic: 'building',
    body: field('大学名', 'universityName', { isURL: false }) + field('大学のドメイン（自動入力・アプリ内表示を許可）', 'trustedDomain', { isURL: false })
      + field('Moodle', 'moodleBaseURL') + field('Campus Square ログイン', 'campusSquare.login') + field('Campus Square ポータル', 'campusSquare.portal')
      + field('時間割', 'campusSquare.timetable') + field('休講・補講（推定）', 'campusSquare.cancellations') + field('成績（推定）', 'campusSquare.grades')
      + field('シラバス（推定）', 'campusSquare.syllabus') + field('出席管理', 'campusSquare.attendance')
      + '<div class="small">「推定」のページが違う場合は、Campus Squareの「ブラウザ」で正しいページを開き、右上の「…」から設定できます。</div>'
      + `<div class="row">${btn('URLを初期値に戻す', 'resetConfig')}</div>`,
  });
  const sel = (key, opts) => `<select class="input" data-pref-num="${key}">${opts.map(([v, l]) => `<option value="${v}" ${pr[key] === v ? 'selected' : ''}>${l}</option>`).join('')}</select>`;
  html += card({
    title: 'ホームに表示するもの', ic: 'grid',
    body: toggle('今日の授業', 'showTodayClasses') + toggle('課題・締切', 'showDeadlines') + toggle('お知らせ', 'showNotices') + toggle('メール', 'showMail')
      + `<div class="row"><span style="flex:1">締切の表示期間</span>${sel('deadlineWindowDays', [[7, '7日'], [14, '14日'], [30, '30日']])}</div>`,
  });
  html += card({
    title: '通知', ic: 'bell',
    body: toggle('締切の通知', 'notificationsEnabled')
      + `<div class="row"><span style="flex:1">通知のタイミング</span>${sel('notifyHoursBefore', [[1, '1時間前'], [3, '3時間前'], [12, '12時間前'], [24, '24時間前'], [48, '48時間前']])}</div>`
      + `<div class="small">通知はキャンパスハブを起動している間だけ届きます（Windowsの通知センターに出ます）。</div><div class="row">${btn('通知を試す', 'testNotification')}</div>`,
  });
  html += card({ title: 'その他', ic: 'masks', body: toggle('サンプルデータで表示を確認する', 'useSampleData') });
  html += diagnosticsCard();
  return html;
}

function gmailSettings() {
  const st = S.googleSignedIn ? chip('連携中', 'ok', 'checkSeal') : S.googleClientReady ? chip('ログイン待ち', 'warn') : chip('未設定', 'subtle');
  let body = `<div class="row"><span class="small" style="flex:1">状態</span>${st}</div>`;
  body += field('大学のメールアドレス（ログイン時の候補）', 'mail.address', { isURL: false });
  if (!S.googleClientReady || V.googleGuide) {
    body += '<div class="small">① Google Cloud で OAuth クライアント（デスクトップアプリ）を作り、IDとシークレットを入れてください。</div>'
      + `<input class="input" data-keep="g:id" value="${esc(V.inputs['g:id'] ?? '')}" placeholder="クライアントID（….apps.googleusercontent.com）" spellcheck="false" autocomplete="off">`
      + `<input class="input" type="password" data-keep="g:secret" value="${esc(V.inputs['g:secret'] ?? '')}" placeholder="クライアントシークレット" autocomplete="off">`
      + `<div class="row">${btn('保存', 'saveGoogle', {}, 'primary', !(V.inputs['g:id'] && V.inputs['g:secret']) ? ' disabled' : '')}`
      + `${btn('作り方を見る', 'openExternal', { url: 'https://console.cloud.google.com/apis/credentials' })}</div>`
      + (V.errors.google ? `<div class="err">${esc(V.errors.google)}</div>` : '');
  } else {
    body += `<div class="row" style="flex-wrap:nowrap"><span class="small">クライアントID</span><span class="tiny" style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(S.config.mail.googleClientID)}</span>${btn('変更', 'googleGuide')}</div>`;
  }
  body += '<div class="row">' + (S.googleSignedIn ? btn('連携を解除', 'signOutGoogle', {}, 'danger')
    : S.googleBusy ? btn('<span class="spin"></span>ブラウザでログインしてください…', 'cancelGoogle', {}, 'primary') + btn('やめる', 'cancelGoogle')
      : btn('② Googleでログイン', 'signInGoogle', {}, 'primary', S.googleClientReady ? '' : ' disabled')) + '</div>';
  body += field('取得するメールの条件（Gmailの検索と同じ書き方）', 'mail.searchQuery', { isURL: false });
  body += '<div class="small">読み取り専用（gmail.readonly）で、件名・差出人・日時・冒頭の一部だけを取得します。取得した内容は保存しません。'
    + 'ログインはGoogleの公式ページ（既定のブラウザ）で行い、アプリはGoogleのパスワードを扱いません。</div>';
  return card({ title: 'メール（Gmail）', ic: 'envBadge', body });
}

function diagnosticsCard() {
  const list = S.diagnostics.slice(V.diagAll ? -200 : -25);
  return card({
    title: '接続の診断', ic: 'stethoscope', trail: `${S.diagnostics.length}件`,
    body: '<div class="small">うまく読み込めないときは、ここに「どこで止まったか」が出ます。ID・パスワード・メール本文は記録しません。</div>'
      + (list.length ? '' : statusMsg('info', 'まだ記録はありません。「更新」を押してください。'))
      + list.map(e => `<div class="diag${e.ok ? '' : ' bad'}"><span class="${e.ok ? 'ok' : 'ng'}">${icon(e.ok ? 'check' : 'xOctagon')}</span>`
        + `<span class="tm">${Fmt.hms(e.time)}</span><span class="sv">${esc(e.service)}</span><span class="m">${esc(e.message)}</span></div>`).join('')
      + `<div class="row">${btn(V.diagAll ? '最近のものだけ' : 'すべて表示', 'diagAll')}${btn(icon('copy') + 'コピー', 'copyDiag')}${btn(icon('folder') + 'ログのフォルダ', 'openDiagFolder')}</div>`
      + `<div class="tiny">${esc(S.diagPath)}</div>`,
  });
}

// MARK: - アプリ内ブラウザ

function browserPane(service) {
  const b = S.browsers[service] ?? {};
  return '<div class="bpane"><div class="btool">'
    + `<button data-act="bnav" data-cmd="back" ${b.canGoBack ? '' : 'disabled'} title="戻る">${icon('left')}</button>`
    + `<button data-act="bnav" data-cmd="forward" ${b.canGoForward ? '' : 'disabled'} title="進む">${icon('right')}</button>`
    + `<button data-act="bnav" data-cmd="reload" title="再読み込み">${icon('refresh')}</button>`
    + `<button data-act="bnav" data-cmd="home" title="トップへ">${icon('home')}</button>`
    + `<div class="where"><b>${esc(b.title || label(service))}</b><small>${esc(b.host ?? '')}</small></div>`
    + `${b.isLoading ? '<span class="spin"></span>' : ''}`
    + `<button data-act="bnav" data-cmd="fill" title="保存したID・パスワードでログイン">${icon('key')}</button>`
    + `<button data-act="bmenu" title="その他">${icon('more')}</button></div>`
    + (b.message ? `<div class="bmsg">${icon('sparkles')}<span>${esc(b.message)}</span><button data-act="bnav" data-cmd="dismiss">${icon('x')}</button></div>` : '')
    + '<div class="bview" id="bview"></div></div>';
}

// MARK: - 全体

function sidebar() {
  const badge = s => {
    if (s === 'moodle') { const n = (S.moodle.value?.deadlines ?? []).filter(d => ['overdue', 'urgent'].includes(urgency(d.due))).length; return n || null; }
    if (s === 'campusSquare') return S.campus.value?.cancellations?.rows?.length || null;
    if (s === 'mail') return todos(S).filter(t => t.source === 'mail').length || null;
    return null;
  };
  const compact = innerWidth < 720;
  return face(S.isRefreshing ? 'face_calm' : 'face_smile', compact ? 40 : 84)
    + `<div class="name"><b>キャンパスハブ</b><small>${esc(S.isRefreshing ? '読み込み中…' : S.config.universityName)}</small></div>`
    + '<div class="nav">' + SECTIONS.map(([s, t, ic]) => {
      const n = badge(s);
      return `<button class="${V.selection === s ? 'on' : ''}" data-act="go" data-s="${s}" title="${t}">${icon(ic)}<span class="label">${t}</span>${n ? `<span class="badge">${n}</span>` : ''}</button>`;
    }).join('') + '</div>';
}

function modeSwitch(mode) {
  return `<div class="seg"><button class="${mode === 'summary' ? 'on' : ''}" data-act="mode" data-m="summary">${icon('stack')}まとめ</button>`
    + `<button class="${mode === 'browser' ? 'on' : ''}" data-act="mode" data-m="browser">${icon('globe')}ブラウザ</button></div>`;
}

let renderQueued = false;
function render() {
  if (renderQueued) return;
  renderQueued = true;
  requestAnimationFrame(() => { renderQueued = false; renderNow(); });
}

function renderNow() {
  if (!S) return;
  // 入力中の欄を覚えておき、描き直したあとに戻す
  const active = document.activeElement;
  const keep = active?.dataset?.keep;
  const selStart = keep ? active.selectionStart : null, selEnd = keep ? active.selectionEnd : null;

  document.getElementById('sidebar').innerHTML = sidebar();
  const svc = V.selection === 'moodle' ? 'moodle' : V.selection === 'campusSquare' ? 'campus' : null;
  const mode = svc === 'moodle' ? V.moodleMode : svc === 'campus' ? V.campusMode : null;
  const browsing = !!svc && mode === 'browser';
  document.getElementById('top').innerHTML = svc ? modeSwitch(mode) : '';
  const main = document.getElementById('main');
  main.classList.toggle('browsing', browsing);
  const content = document.getElementById('content');
  const browser = document.getElementById('browser');
  if (browsing) {
    browser.innerHTML = browserPane(svc);
  } else {
    browser.innerHTML = '';
    const views = { home: homeView, calendar: calendarView, moodle: moodleView, campusSquare: campusView, mail: mailView, settings: settingsView };
    content.innerHTML = views[V.selection]();
  }
  const t = S.toast;
  document.getElementById('toast').innerHTML = t
    ? `<div class="t"><span class="ic">${icon('sparkles')}</span><span>${esc(t.text)}</span><button data-act="dismissToast">${icon('x')}</button></div>` : '';

  if (keep) {
    const el = document.querySelector(`[data-keep="${CSS.escape(keep)}"]`);
    if (el) { el.focus(); try { el.setSelectionRange(selStart, selEnd); } catch {} }
  }
  placeBrowser(browsing ? svc : null);
}

let lastPlacement = '';
function placeBrowser(svc) {
  const el = svc && document.getElementById('bview');
  let bounds = null;
  if (el) { const r = el.getBoundingClientRect(); bounds = { x: r.left, y: r.top, width: r.width, height: r.height }; }
  const key = JSON.stringify([svc, bounds]);
  if (key === lastPlacement) return;
  lastPlacement = key;
  hub.act('browserPlace', svc, bounds);
}

let toastTimer = null;
function scheduleToastClear() {
  clearTimeout(toastTimer);
  if (S?.toast) { const id = S.toast.id; toastTimer = setTimeout(() => { if (S.toast?.id === id) hub.act('dismissToast'); }, 5000); }
}

// MARK: - 操作

function navigate(s, mode) {
  V.selection = s;
  if (mode && s === 'moodle') V.moodleMode = mode;
  if (mode && s === 'campusSquare') V.campusMode = mode;
  document.getElementById('scroll').scrollTop = 0;
  if (s === 'calendar') loadCalMonth();
  render();
}

function openInApp(service, url) {
  if (!url) return;
  hub.act('openInApp', service, url);
  navigate(service === 'moodle' ? 'moodle' : 'campusSquare', 'browser');
}

function loadCalMonth() { hub.act('loadMonth', V.calMonth.getFullYear(), V.calMonth.getMonth() + 1); }

const actions = {
  refresh: () => hub.act('refresh'),
  go: d => navigate(d.s, d.mode),
  mode: d => { if (V.selection === 'moodle') V.moodleMode = d.m; else V.campusMode = d.m; render(); },
  browserLogin: d => openInApp(d.s, d.s === 'moodle' ? String(S.config.moodleBaseURL).replace(/\/+$/, '') + '/my/' : S.config.campusSquare.portal),
  openMoodle: d => {
    const base = String(S.config.moodleBaseURL).replace(/\/+$/, '');
    openInApp('moodle', d.url || base + (d.fallback === 'notifications' ? '/message/output/popup/notifications.php' : '/calendar/view.php?view=upcoming'));
  },
  openCampus: d => openInApp('campus', d.url),
  openExternal: d => { if (d.url) hub.act('openExternal', d.url); },
  toggleDone: d => hub.act('toggleDone', d.id),
  toggleMail: d => { if (V.mailOpen.has(d.id)) V.mailOpen.delete(d.id); else V.mailOpen.add(d.id); render(); },
  mailFilter: d => { V.mailFilter = d.c || null; render(); },
  portlet: d => { if (V.portletOpen.has(d.t)) V.portletOpen.delete(d.t); else V.portletOpen.add(d.t); render(); },
  campusDay: d => { V.campusDay = d.d; render(); },
  calSelect: d => { V.calSelected = Number(d.t); render(); },
  calShift: d => { V.calMonth = new Date(V.calMonth.getFullYear(), V.calMonth.getMonth() + Number(d.n), 1); V.calSelected = V.calMonth.getTime(); loadCalMonth(); render(); },
  calToday: () => { const n = new Date(); V.calMonth = new Date(n.getFullYear(), n.getMonth(), 1); V.calSelected = startOfDay(n); loadCalMonth(); render(); },
  saveCred: async d => {
    const u = V.inputs[`cred:${d.s}:u`], p = V.inputs[`cred:${d.s}:p`];
    if (!u || !p) return;
    const err = await hub.act('saveCredentials', d.s, u, p);
    V.errors[d.s] = err;
    if (!err) { delete V.inputs[`cred:${d.s}:u`]; delete V.inputs[`cred:${d.s}:p`]; }
    render();
  },
  delCred: d => hub.act('deleteCredentials', d.s),
  clearSessions: async () => {
    if (await hub.act('confirm', 'Moodle・Campus Squareのログイン状態を消去しますか？（保存したID・パスワードは残ります）', '消去する')) hub.act('clearSessions');
  },
  resetConfig: async () => {
    if (await hub.act('confirm', 'URLを初期値に戻しますか？', '初期値に戻す')) {
      for (const k of Object.keys(V.inputs)) if (k.startsWith('cfg:')) delete V.inputs[k];
      hub.act('resetConfig');
    }
  },
  saveGoogle: async () => {
    const err = await hub.act('saveGoogleClient', V.inputs['g:id'], V.inputs['g:secret']);
    V.errors.google = err;
    if (!err) { delete V.inputs['g:id']; delete V.inputs['g:secret']; V.googleGuide = false; }
    render();
  },
  googleGuide: () => { V.googleGuide = true; render(); },
  signInGoogle: () => hub.act('signInGoogle'),
  cancelGoogle: () => hub.act('cancelGoogle'),
  signOutGoogle: () => hub.act('signOutGoogle'),
  testNotification: () => hub.act('testNotification'),
  diagAll: () => { V.diagAll = !V.diagAll; render(); },
  copyDiag: () => {
    hub.act('copyText', S.diagnostics.map(e => `${Fmt.hms(e.time)} [${e.service}] ${e.ok ? 'OK' : 'NG'} ${e.message}`).join('\n'));
    hub.act('toast', '診断ログをコピーしました');
  },
  openDiagFolder: () => hub.act('openDiagFolder'),
  dismissToast: () => hub.act('dismissToast'),
  bnav: d => hub.act('browserNav', currentService(), d.cmd),
  bmenu: (_d, el) => { const r = el.getBoundingClientRect(); hub.act('browserMenu', currentService(), r.left, r.bottom); },
};

const currentService = () => (V.selection === 'moodle' ? 'moodle' : 'campus');

document.addEventListener('click', e => {
  const el = e.target.closest('[data-act]');
  if (!el || el.disabled) return;
  // メールの行の中のボタンは、行の開閉より優先する
  e.stopPropagation();
  const fn = actions[el.dataset.act];
  if (fn) fn(el.dataset, el);
});

const configTimers = {};
document.addEventListener('input', e => {
  const el = e.target;
  if (el.dataset.keep) V.inputs[el.dataset.keep] = el.value;
  if (el.dataset.config) {
    const k = el.dataset.config;
    clearTimeout(configTimers[k]);
    configTimers[k] = setTimeout(() => hub.act('setConfig', k, el.value), 300);
  }
  // 保存ボタンの押せる・押せないだけ更新する（描き直すと日本語入力が途切れるため）
  if (el.dataset.keep?.startsWith('cred:') || el.dataset.keep?.startsWith('g:')) {
    const svc = el.dataset.keep.split(':')[1];
    document.querySelectorAll('[data-act="saveCred"], [data-act="saveGoogle"]').forEach(b => {
      if (b.dataset.act === 'saveGoogle') b.disabled = !(V.inputs['g:id'] && V.inputs['g:secret']);
      else if (b.dataset.s === svc) b.disabled = !(V.inputs[`cred:${svc}:u`] && V.inputs[`cred:${svc}:p`]);
    });
  }
});

document.addEventListener('change', e => {
  const el = e.target;
  if (el.dataset.pref) hub.act('setPref', el.dataset.pref, el.checked);
  if (el.dataset.prefNum) hub.act('setPref', el.dataset.prefNum, Number(el.value));
  if (el.dataset.view) { V[el.dataset.view] = el.checked; render(); }
  if (el.dataset.showdone) { V.showDone[el.dataset.showdone] = el.checked; render(); }
  if (el.dataset.config) {
    // 入力が終わったら、保存された値で表示する
    const k = el.dataset.config;
    clearTimeout(configTimers[k]);
    hub.act('setConfig', k, el.value).then(() => { delete V.inputs['cfg:' + k]; });
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Enter' && e.target.dataset?.enter && !e.isComposing) actions[e.target.dataset.enter]?.(e.target.dataset, e.target);
});

// 日本語入力（変換中）は描き直さない
let composing = false;
document.addEventListener('compositionstart', () => { composing = true; });
document.addEventListener('compositionend', () => { composing = false; render(); });

window.addEventListener('resize', () => render());
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => render());
new ResizeObserver(() => placeBrowser(document.getElementById('bview') ? currentService() : null)).observe(document.getElementById('browser'));

hub.onState(s => {
  const toastChanged = s.toast?.id !== S?.toast?.id;
  S = s;
  if (toastChanged) scheduleToastClear();
  if (!composing) render();
});
hub.onNavigate(s => navigate(s));

hub.init().then(r => {
  if (!r) return;
  S = r.state;
  ART = r.artwork ?? {};
  document.documentElement.dataset.platform = r.platform;
  if (r.section) V.selection = r.section;
  render();
  // 1分ごとに「あと○時間」などを描き直す
  setInterval(() => { if (!composing) render(); }, 60000);
});
