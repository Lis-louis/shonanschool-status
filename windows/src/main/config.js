'use strict';
// 大学ごとの初期設定値（湘南工科大学）。Mac版 Sources/CampusHub/Config/DefaultConfig.swift と同じ値。
// - URL はすべて「設定」画面から上書きできます（settings.json に保存）。
// - 「推定」と書いた Campus Square のページは、他大学の Campus Square で一般的な画面IDからの推定です。
// - ここには公開情報だけを書きます。ID・パスワードは書かないでください（設定画面から入力 → 暗号化して保存）。

const DEFAULT_QUERY = 'newer_than:30d -category:promotions -category:social';

const DEFAULT_CONFIG = Object.freeze({
  universityName: '湘南工科大学',
  // 自動ログイン・アプリ内ブラウザで「大学のサイト」とみなすドメイン
  trustedDomain: 'shonan-it.ac.jp',
  moodleBaseURL: 'https://moodle2026.shonan-it.ac.jp',
  // 公開ログインページで確認したフォーム（2026-11-23 時点）
  moodleLogin: { username: '#username', password: '#password', submit: '#loginbtn', error: '#loginerrormessage' },
  campusSquare: {
    login: 'https://portal.shonan-it.ac.jp/campusweb/',
    portal: 'https://portal.shonan-it.ac.jp/campusweb/portal.do?page=main',
    timetable: 'https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=RSW0001000-flow', // 履修登録・登録状況照会
    cancellations: 'https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=KHW0001100-flow', // 休講補講参照（2026-11-24 確認）
    grades: 'https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=SIW0001300-flow', // 推定: 成績照会
    syllabus: 'https://portal.shonan-it.ac.jp/campusweb/campussquare.do?_flowId=SYW0001000-flow', // 推定: シラバス
    attendance: 'https://syusseki.shonan-it.ac.jp/campusaa/', // ログインページ上のリンクより
  },
  campusLogin: { username: '#userNameInput', password: '#passwordInput', submit: '#login-form button[type=submit]', error: null },
  // 大学メール: MX が Google を指している（2026-11-23 DNSで確認）
  mail: { webURL: 'https://mail.google.com/', provider: 'googleWorkspace', address: '', googleClientID: '', searchQuery: DEFAULT_QUERY },
});

const DEFAULT_PREFS = Object.freeze({
  showTodayClasses: true,
  showDeadlines: true,
  showNotices: true,
  showMail: true,
  deadlineWindowDays: 30,
  notificationsEnabled: false,
  notifyHoursBefore: 24,
  useSampleData: false,
  autoLogin: true, // 保存したID・パスワードで公式ログインページに自動入力し、ログインボタンを押す
  sameCredentials: true, // Campus Square も Moodle と同じID・パスワードを使う
  themeOfficialPages: true, // アプリ内ブラウザで大学のページに鈴テーマの配色を少しだけ重ねる
  showTimetableInCalendar: true,
});

/** 保存済みの値に、増えた項目の初期値を足す（古い設定も読めるように） */
function mergeDefaults(defaults, saved) {
  if (saved === null || typeof saved !== 'object' || Array.isArray(saved)) return structuredClone(defaults);
  const out = {};
  for (const [k, v] of Object.entries(defaults)) {
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) out[k] = mergeDefaults(v, saved[k]);
    else out[k] = k in saved && (v === null || typeof saved[k] === typeof v || saved[k] === null) ? saved[k] : v;
  }
  return out;
}

// MARK: - URL の検証

const SafeURL = {
  /** https で、ホストがあり、ユーザー名・パスワードを含まないURLだけを通す */
  https(s) {
    try {
      const u = new URL(String(s ?? '').trim());
      if (u.protocol !== 'https:' || !u.hostname || u.username || u.password) return null;
      return u.href;
    } catch {
      return null;
    }
  },
  host(s) {
    try { return new URL(s).hostname.toLowerCase(); } catch { return null; }
  },
  isPlaceholder(url) {
    const h = url && SafeURL.host(url);
    if (!h) return true;
    return h === 'example' || h.endsWith('.example') || h.endsWith('.invalid')
      || h.endsWith('example.com') || h.endsWith('example.org') || h.endsWith('example.net');
  },
  appending(path, base) {
    const b = SafeURL.https(base);
    if (!b) return null;
    return SafeURL.https(b.replace(/\/+$/, '') + path);
  },
  /** 大学のドメイン（またはそのサブドメイン）かどうか */
  isTrusted(url, domain) {
    let u;
    try { u = new URL(url); } catch { return false; }
    if (u.protocol !== 'https:') return false;
    const d = String(domain || '').toLowerCase().replace(/^[. ]+|[. ]+$/g, '');
    if (!d) return false;
    const h = u.hostname.toLowerCase();
    return h === d || h.endsWith('.' + d);
  },
  /** Campus Square のURLから、セッション固有の値（_flowExecutionKey など）を取り除く */
  stableCampusURL(url) {
    let u;
    try { u = new URL(url); } catch { return url; }
    const flow = u.searchParams.get('_flowId');
    if (flow) {
      u.search = '';
      u.searchParams.set('_flowId', flow);
    } else {
      for (const k of [...u.searchParams.keys()]) {
        if (k.startsWith('_flowExecutionKey') || k === '_eventId') u.searchParams.delete(k);
      }
    }
    u.hash = '';
    return u.href;
  },
};

const Urls = {
  moodleHome: c => SafeURL.https(c.moodleBaseURL),
  moodleLogin: c => SafeURL.appending('/login/index.php', c.moodleBaseURL),
  moodleDashboard: c => SafeURL.appending('/my/', c.moodleBaseURL),
  moodleCourses: c => SafeURL.appending('/my/courses.php', c.moodleBaseURL),
  moodleUpcoming: c => SafeURL.appending('/calendar/view.php?view=upcoming', c.moodleBaseURL),
  moodleNotifications: c => SafeURL.appending('/message/output/popup/notifications.php', c.moodleBaseURL),
  moodleCourse: (c, id) => SafeURL.appending(`/course/view.php?id=${id}`, c.moodleBaseURL),
  loginSpec: (c, s) => (s === 'moodle' ? c.moodleLogin : c.campusLogin),
  loginHost: (c, s) => {
    const u = s === 'moodle' ? Urls.moodleLogin(c) : SafeURL.https(c.campusSquare.login);
    return u ? SafeURL.host(u) : null;
  },
  startURL: (c, s) => (s === 'moodle' ? Urls.moodleDashboard(c) : SafeURL.https(c.campusSquare.portal)),
};

const serviceLabel = s => (s === 'moodle' ? 'Moodle' : 'Campus Square');

module.exports = { DEFAULT_CONFIG, DEFAULT_PREFS, DEFAULT_QUERY, mergeDefaults, SafeURL, Urls, serviceLabel };
