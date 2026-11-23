'use strict';
// Mac版 Tests/CampusHubTests と同じ確認を、Windows版のコードに対して行う（node --test、Electron なしで動く）。
process.env.TZ = 'Asia/Tokyo';
const test = require('node:test');
const assert = require('node:assert/strict');
const { DEFAULT_CONFIG, DEFAULT_PREFS, mergeDefaults, SafeURL, Urls } = require('../src/main/config');
const P = require('../src/main/parsers');
const L = require('../src/renderer/logic');
const { wrap } = require('../src/main/wrap');

const C = DEFAULT_CONFIG;

test('https だけを通す', () => {
  assert.ok(SafeURL.https('https://moodle2026.shonan-it.ac.jp'));
  assert.equal(SafeURL.https('http://moodle2026.shonan-it.ac.jp'), null);
  assert.equal(SafeURL.https('javascript:alert(1)'), null);
  assert.equal(SafeURL.https('https://user:pass@host.example'), null);
});

test('大学のドメインはサブドメインだけ一致', () => {
  const d = 'shonan-it.ac.jp';
  assert.ok(SafeURL.isTrusted('https://moodle2026.shonan-it.ac.jp/my/', d));
  assert.ok(SafeURL.isTrusted('https://shonan-it.ac.jp/', d));
  assert.ok(!SafeURL.isTrusted('https://evilshonan-it.ac.jp/', d));
  assert.ok(!SafeURL.isTrusted('https://shonan-it.ac.jp.evil.example/', d));
  assert.ok(!SafeURL.isTrusted('http://moodle2026.shonan-it.ac.jp/', d));
});

test('Campus Square のURLからセッションの値を除く', () => {
  assert.equal(SafeURL.stableCampusURL('https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowExecutionKey=_c1_k2&_flowId=RSW0001000-flow&x=1#top'),
    'https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=RSW0001000-flow');
  assert.equal(SafeURL.stableCampusURL('https://portal.shonan-it.ac.jp/campusweb/portal.do?page=main&_flowExecutionKey=abc'),
    'https://portal.shonan-it.ac.jp/campusweb/portal.do?page=main');
});

test('初期設定のログインホスト', () => {
  assert.equal(Urls.loginHost(C, 'moodle'), 'moodle2026.shonan-it.ac.jp');
  assert.equal(Urls.loginHost(C, 'campus'), 'portal.shonan-it.ac.jp');
  assert.equal(Urls.moodleLogin(C), 'https://moodle2026.shonan-it.ac.jp/login/index.php');
});

test('古い設定も読める', () => {
  const p = mergeDefaults(DEFAULT_PREFS, { showTodayClasses: false, autoLogin: false, unknown: 1 });
  assert.equal(p.showTodayClasses, false);
  assert.equal(p.autoLogin, false);
  assert.equal(p.showTimetableInCalendar, true);
  assert.ok(!('unknown' in p));
  const c = mergeDefaults(C, { moodleBaseURL: 'https://m.example', campusLogin: { error: '#e' } });
  assert.equal(c.moodleBaseURL, 'https://m.example');
  assert.equal(c.campusLogin.error, '#e');
  assert.equal(c.campusLogin.username, '#userNameInput');
});

test('Moodle の応答を読む', () => {
  const json = `{"courses":{"data":{"courses":[{"id":5,"fullname":"情報&amp;数理","shortname":"IM","coursecategory":"工学部","progress":40,"viewurl":"https://moodle2026.shonan-it.ac.jp/course/view.php?id=5"}],"nextoffset":1}},
   "events":{"data":{"events":[{"id":9,"name":"レポート1 の提出期限","timesort":1796050740,"url":"https://evil.example/x","course":{"fullname":"情報&amp;数理"}}]}},
   "notices":{"error":"accessexception"}}`;
  const s = P.parseMoodle(json, C, () => {}, 0);
  assert.equal(s.courses[0].fullName, '情報&数理');
  assert.equal(s.courses[0].progress, 40);
  assert.equal(s.deadlines[0].due, 1796050740 * 1000);
  assert.equal(s.deadlines[0].url, null); // 大学外のURLはリンクにしない
  assert.equal(s.notices.length, 0);
  assert.equal(s.warnings.length, 1);
});

test('未ログインはエラー', () => {
  assert.throws(() => P.parseMoodle('{"fatal":"nosesskey"}', C), P.ParseError);
});

test('未完了一覧が取れないときは今後の予定で補う', () => {
  const json = `{"events":{"error":"servicenotavailable"},
   "upcoming":{"data":{"events":[
     {"id":3,"name":"課題2 期限","timestart":1796050740,"timesort":1796050740,"eventtype":"due","modulename":"assign","course":{"fullname":"情報数理"}},
     {"id":4,"name":"オフィスアワー","timestart":1796000000,"timeduration":3600,"eventtype":"course"}]}}}`;
  const s = P.parseMoodle(json, C, () => {}, 0);
  assert.equal(s.deadlines.length, 1);
  assert.equal(s.deadlines[0].needsAction, false);
  assert.equal(s.upcoming.length, 2);
  const e4 = s.upcoming.find(x => x.id === 'c-4');
  assert.equal(e4.kind, 'moodleEvent');
  assert.ok(e4.end != null);
});

test('月のカレンダーを平らにして重複を除く', () => {
  const json = `{"month":{"data":{"weeks":[{"days":[{"events":[{"id":1,"name":"A","timestart":1796000000,"eventtype":"due"}]},{"events":[]}]},
    {"days":[{"events":[{"id":1,"name":"A","timestart":1796000000,"eventtype":"due"},{"id":2,"name":"B","timestart":1796100000}]}]}]}}}`;
  const items = P.parseMonth(json, C);
  assert.deepEqual(items.map(i => i.id), ['c-1', 'c-2']);
  assert.equal(items[0].kind, 'deadline');
});

test('受付終了のアンケートは除き、遅れて出せる課題は残す', () => {
  const past = Math.floor(Date.now() / 1000) - 86400;
  const json = JSON.stringify({ events: { data: { events: [
    { id: 1, name: '出席アンケート（アンケート終了）', timesort: past, eventtype: 'close', modulename: 'questionnaire', action: { actionable: true } },
    { id: 2, name: 'レポート1 期限', timesort: past, eventtype: 'due', modulename: 'assign', action: { actionable: true } },
    { id: 3, name: 'アンケート開始', timesort: past + 200000, eventtype: 'open', modulename: 'questionnaire' },
  ] } } });
  assert.deepEqual(P.parseMoodle(json, C).deadlines.map(d => d.id), ['m-2']);
});

test('HTMLの文字参照を戻す', () => {
  assert.equal(P.plainText('<b>A&amp;B</b>&nbsp;'), 'A&B');
  assert.equal(P.plainText('It&#39;s &#x30A2;&amp;B'), "It's ア&B");
});

// メールの仕分け
const ref = new Date(2026, 10, 23, 10).getTime();
const mail = (subject, snippet, from = 'kyomu@sit.shonan-it.ac.jp') => P.MailClassifier.classify({
  id: '1', threadId: '1', subject, from: '教務課', fromAddress: from, date: ref, snippet, unread: true,
  category: 'other', isFromSchool: false, dueDate: null, looksOverdue: false, reasons: [],
}, 'shonan-it.ac.jp');

test('期限つきの要対応', () => {
  const m = mail('【重要】奨学金継続手続き', '提出期限は12月5日17時までです。');
  assert.equal(m.category, 'action');
  assert.ok(m.isFromSchool);
  const d = new Date(m.dueDate);
  assert.deepEqual([d.getMonth() + 1, d.getDate(), d.getHours()], [12, 5, 17]);
});

test('督促', () => {
  const m = mail('【督促】履修登録が未完了の方へ', 'まだ完了していません');
  assert.equal(m.category, 'action');
  assert.ok(m.looksOverdue);
});

test('休講が優先', () => assert.equal(mail('休講のお知らせ', '12/2 3限は休講です。').category, 'classChange'));
test('外部の広告はその他', () => {
  const m = mail('セール', '今だけ', 'news@shop.example');
  assert.equal(m.category, 'other');
  assert.ok(!m.isFromSchool);
});
test('似たドメインは大学ではない', () => assert.ok(!mail('お知らせ', '', 'x@evil-shonan-it.ac.jp').isFromSchool));
test('1月の日付は翌年', () => assert.equal(new Date(P.DateExtractor.findDeadline('1月10日までに提出', ref)).getFullYear(), 2027));
test('期限の言葉がなければ期限にしない', () => assert.equal(P.DateExtractor.findDeadline('12月5日に説明会を開催します', ref), null));

test('差出人の読み取り', () => {
  assert.deepEqual(P.parseFrom('"教務課" <kyomu@sit.shonan-it.ac.jp>'), ['教務課', 'kyomu@sit.shonan-it.ac.jp']);
  assert.deepEqual(P.parseFrom('a@b.jp'), ['a@b.jp', 'a@b.jp']);
});

test('フォームの控えメールとの照合', () => {
  assert.equal(P.coreTitle('(出席課題) 出席アンケート (締切：11月9日23:59)'), '出席アンケート');
  assert.equal(P.coreTitle('【情】第8回 出席確認'), '第8回出席確認');
  const due = 1_800_000_000_000;
  const d = { id: 'm-1', title: '(出席課題) 第8回 出席確認 (締切)', due };
  assert.ok(P.hasReceipt(d, [{ text: '「第8回 出席確認」の回答のコピー', date: due - 3600e3 }]));
  assert.ok(!P.hasReceipt(d, [{ text: '「第8回 出席確認」の回答のコピー', date: due - 40 * 86400e3 }]));
  assert.ok(!P.hasReceipt(d, [{ text: '「第9回 出席確認」の回答のコピー', date: due }]));
});

// 画面側の計算
test('時間割：空きコマを除く', () => {
  const tt = { days: ['月', '火'], periods: [{ label: '1限', byDay: { 月: '講義A\n1号館', 火: '' } }, { label: '2限', byDay: { 月: '-', 火: '演習B' } }] };
  assert.deepEqual(L.Timetable.classes(tt, '月').map(c => c.period), ['1限']);
  assert.deepEqual(L.Timetable.classes(tt, '火').map(c => c.text), ['演習B']);
  assert.equal(L.Timetable.classes(tt, '水').length, 0);
  assert.equal(L.Timetable.dayChar(new Date(2026, 10, 23, 12).getTime()), '月');
});

test('時間割：科目コードの行を分ける', () => {
  const r = L.Timetable.split('B30A02K1\n共通基盤ワークショップ1B\n担当 A\n2.0単位');
  assert.equal(r.code, 'B30A02K1');
  assert.equal(r.title, '共通基盤ワークショップ1B');
  assert.deepEqual(r.rest, ['担当 A', '2.0単位']);
  assert.equal(L.Timetable.split('情報数理\n1号館101').code, null);
});

test('残り時間と急ぎ度', () => {
  const H = 3600e3;
  assert.equal(L.urgency(-H, 0), 'overdue');
  assert.equal(L.urgency(5 * H, 0), 'urgent');
  assert.equal(L.urgency(48 * H, 0), 'soon');
  assert.equal(L.urgency(100 * H, 0), 'normal');
  assert.equal(L.remainingText(30 * 60e3, 0), 'あと30分');
  assert.equal(L.remainingText(-1, 0), '期限切れ');
  assert.ok(L.Importance.is('【休講】情報数理'));
  assert.ok(!L.Importance.is('図書館のお知らせ'));
});

test('やることの並び：督促が先、次に期限順', () => {
  const now = Date.now();
  const S = {
    config: C, doneIDs: ['m-done'], prefs: DEFAULT_PREFS, monthItems: {}, campus: { state: 'loading' },
    moodle: { state: 'loaded', value: { deadlines: [
      { id: 'm-late', title: 'B', due: now + 5 * 86400e3, needsAction: true, status: 'unknown', url: null },
      { id: 'm-soon', title: 'A', due: now + 86400e3, needsAction: true, status: 'unknown', url: null },
      { id: 'm-sub', title: 'C', due: now + 86400e3, needsAction: true, status: 'submitted', url: null },
      { id: 'm-done', title: 'D', due: now + 86400e3, needsAction: true, status: 'unknown', url: null },
    ] } },
    mail: { state: 'loaded', value: { email: 'a@b', messages: [
      { id: 'x', threadId: 't', subject: '督促', from: '教務課', date: now, category: 'action', dueDate: null, looksOverdue: true, reasons: ['督促'] },
    ] } },
  };
  assert.deepEqual(L.todos(S).map(t => t.id), ['mail-x', 'm-soon', 'm-late']);
  assert.equal(L.todos(S, true).length, 4);
});

test('ページ内スクリプトに引数を渡す形', async () => {
  const code = wrap('return a + b.length;', { a: 1, b: 'x"y', 'bad-name': 2 });
  assert.equal(await eval(code), 4);
});
