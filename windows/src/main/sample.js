'use strict';
// 画面確認用の架空データ。実在の授業とは無関係（Mac版 SampleData.swift と同じ内容）。

const { MailClassifier } = require('./parsers');

const H = 3600e3, D = 86400e3;

function moodle(now = Date.now()) {
  const dl = (id, title, course, due) => ({ id, title, course, due, url: null, needsAction: true, module: null, status: 'unknown', formURL: null });
  return {
    courses: [
      { id: 1, fullName: 'サンプル講義A', shortName: 'SAMPLE-A', category: 'サンプル学科', progress: 62, url: null },
      { id: 2, fullName: 'サンプル演習B', shortName: 'SAMPLE-B', category: 'サンプル学科', progress: 35, url: null },
      { id: 3, fullName: 'サンプル実験C', shortName: 'SAMPLE-C', category: '共通科目', progress: null, url: null },
    ],
    deadlines: [
      dl('d0', '小レポート（未提出）', 'サンプル演習B', now - 20 * H),
      dl('d1', 'レポート1 の提出期限', 'サンプル講義A', now + 5 * H),
      dl('d2', '小テスト 第3回 終了', 'サンプル演習B', now + 50 * H),
      dl('d3', '実験ノート提出', 'サンプル実験C', now + 6 * D),
    ],
    upcoming: [],
    notices: [
      { id: 1, subject: 'サンプル講義A: 課題が評価されました', time: now - H, read: false, url: null },
      { id: 2, subject: 'サンプル演習B: 新しいフォーラム投稿', time: now - D, read: true, url: null },
    ],
    unreadCount: 1,
    warnings: [],
  };
}

function campus() {
  const days = ['月', '火', '水', '木', '金'];
  const row = (label, v) => ({ label, byDay: Object.fromEntries(days.map((d, i) => [d, v[i]])) });
  return {
    timetable: {
      days,
      periods: [
        row('1限', ['サンプル講義A\n担当 未定\n1号館101', '', 'サンプル講義A\n担当 未定\n1号館101', '', 'サンプル演習B\n担当 未定\n2号館203']),
        row('2限', ['サンプル演習B\n担当 未定\n2号館203', 'サンプル実験C\n担当 未定\n実験棟', '', 'サンプル講義D\n担当 未定\n3号館301', '']),
        row('3限', ['', 'サンプル実験C\n担当 未定\n実験棟', 'サンプル講義E\n担当 未定\n1号館102', '', 'サンプル講義A\n担当 未定\n1号館101']),
        row('4限', ['サンプル講義E\n担当 未定\n1号館102', '', '', 'サンプル演習B\n担当 未定\n2号館203', '']),
      ],
    },
    portlets: [
      { title: '大学からのお知らせ（サンプル）', lines: ['【重要】サンプル: 後期試験の時間割を公開しました', 'サンプル: 図書館の開館時間について', 'サンプル: 学生証の更新手続き'] },
      { title: '休講・補講（サンプル）', lines: ['サンプル講義E 休講（12/2 3限）', 'サンプル演習B 教室変更 2号館203→2号館301'] },
    ],
    cancellations: {
      title: '休講・補講（サンプル）', header: ['日付', '時限', '科目', '区分'],
      rows: [['12/2(水)', '3限', 'サンプル講義E', '休講'], ['12/9(水)', '5限', 'サンプル講義E', '補講']],
    },
    warnings: [],
  };
}

function mail(trustedDomain, now = Date.now()) {
  const due = new Date(now + 4 * D);
  const md = `${due.getMonth() + 1}月${due.getDate()}日`;
  const raw = [
    ['学生課', `gakusei@${trustedDomain}`, '【重要】奨学金継続手続きのお願い（サンプル）', `継続願の提出期限は${md}17時までです。必ず手続きしてください。`, -3, true],
    ['教務課', `kyomu@${trustedDomain}`, '【督促】履修登録が未完了の方へ（サンプル）', '履修登録がまだ完了していません。至急登録してください。', -20, true],
    ['教務課', `kyomu@${trustedDomain}`, '休講のお知らせ：サンプル講義E（サンプル）', '12月2日3限のサンプル講義Eは休講です。補講日は後日連絡します。', -30, false],
    ['Moodle', `noreply@moodle2026.${trustedDomain}`, 'サンプル講義A: 新しいフォーラム投稿（サンプル）', '第5回の資料をアップロードしました。', -50, false],
    ['キャリアセンター', `career@${trustedDomain}`, '就職ガイダンス開催のご案内（サンプル）', '来週水曜日に就職ガイダンスを開催します。', -70, false],
    ['Example Shop', 'news@shop.example', 'セールのお知らせ（サンプル）', '今だけ20%オフ', -90, false],
  ];
  const messages = raw.map((r, i) => MailClassifier.classify({
    id: `s${i}`, threadId: `s${i}`, subject: r[2], from: r[0], fromAddress: r[1], date: now + r[4] * H, snippet: r[3], unread: r[5],
    category: 'other', isFromSchool: false, dueDate: null, looksOverdue: false, reasons: [],
  }, trustedDomain));
  return { email: `student@${trustedDomain}`, messages, unreadCount: 2 };
}

module.exports = { moodle, campus, mail };
