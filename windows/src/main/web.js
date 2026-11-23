'use strict';
// 裏で動くブラウザ（ログイン後のページを開いて読み取る）と、自動ログインの共通部分。

const { BrowserWindow, session } = require('electron');
const Scripts = require('./scripts');
const { wrap } = require('./wrap');

/** Cookie は既定のブラウザと別の、このアプリ専用の保存場所に残る */
const PARTITION = 'persist:campushub';
/** ページの外（メインプロセスへの橋渡しなし）で動かす、隔離された実行環境の番号 */
const ISOLATED_WORLD = 1001;

class WebError extends Error {
  constructor(kind, detail) {
    super(WebError.message(kind, detail));
    this.kind = kind;
  }
  static message(kind, m) {
    switch (kind) {
      case 'timeout': return '読み込みがタイムアウトしました。ネットワークを確認して再試行してください。';
      case 'needsLogin': return 'ログインが必要です。設定でID・パスワードを保存するか、「ブラウザ」タブで一度ログインしてください。';
      case 'loginFailed': return '自動ログインできませんでした。ID・パスワードを確認するか、「ブラウザ」タブでログインしてください。';
      case 'loginRejected': return 'ログインページにエラーが表示されています。ID・パスワードを確認してください。';
      case 'navigation': return `ページを開けませんでした：${m}`;
      default: return `ページの読み取りに失敗しました：${m}`;
    }
  }
}

let sessionReady = false;
function appSession() {
  const s = session.fromPartition(PARTITION);
  if (!sessionReady) {
    sessionReady = true;
    // 「Electron」「キャンパスハブ」をUAから外し、通常の Chrome と同じ見え方にする
    s.setUserAgent(s.getUserAgent().replace(/\s(Electron|campushub|キャンパスハブ)\/\S+/gi, ''));
  }
  return s;
}


/** 公式ログインページの入力欄にID・パスワードを入れる（隔離された環境で実行） */
async function runAutoLogin(wc, spec, credentials, { submit, checkOnly }) {
  const args = {
    userSel: spec.username, passSel: spec.password, submitSel: spec.submit, errSel: spec.error ?? '',
    username: credentials?.username ?? '', password: credentials?.password ?? '', submit, checkOnly,
  };
  try {
    const r = await wc.executeJavaScriptInIsolatedWorld(ISOLATED_WORLD, [{ code: wrap(Scripts.autoLogin, args) }], true);
    return typeof r === 'string' ? r : 'none';
  } catch {
    return 'none';
  }
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

/** 画面に出さないウィンドウで、ログイン後のページを開いて情報を読み取る */
class HeadlessSession {
  constructor() {
    this.win = new BrowserWindow({
      show: false, width: 1280, height: 900,
      webPreferences: { session: appSession(), backgroundThrottling: false, sandbox: true, contextIsolation: true, javascript: true },
    });
    this.win.webContents.setAudioMuted(true);
    this.finished = 0;
    this.lastError = null;
    const wc = this.win.webContents;
    wc.on('did-finish-load', () => { this.finished++; });
    wc.on('did-fail-load', (_e, code, desc, _url, isMain) => {
      if (!isMain || code === -3 /* ERR_ABORTED（別のページへ移った） */) return;
      this.lastError = desc || `エラー ${code}`;
      this.finished++;
    });
    // 裏のウィンドウからは新しいウィンドウを開かない
    wc.setWindowOpenHandler(() => ({ action: 'deny' }));
  }

  get wc() { return this.win.webContents; }

  destroy() { if (!this.win.isDestroyed()) this.win.destroy(); }

  async load(url, timeout = 30000) {
    const start = this.finished;
    this.lastError = null;
    this.wc.loadURL(url).catch(() => {});
    await this.waitForFinish(start, timeout);
  }

  async waitForFinish(count, timeout) {
    const deadline = Date.now() + timeout;
    while (this.finished <= count) {
      if (Date.now() > deadline) throw new WebError('timeout');
      await sleep(150);
    }
    if (this.lastError) throw new WebError('navigation', this.lastError);
  }

  /** world: 'page'（ページと同じ環境。Moodle の M.cfg を使う）/ 'isolated' */
  async run(body, args = {}, world = 'isolated') {
    const code = wrap(body, args);
    try {
      return world === 'page'
        ? await this.wc.executeJavaScript(code, true)
        : await this.wc.executeJavaScriptInIsolatedWorld(ISOLATED_WORLD, [{ code }], true);
    } catch (e) {
      throw new WebError('script', e?.message ?? String(e));
    }
  }

  async runJSON(body, args = {}, world = 'isolated') {
    const s = await this.run(body, args, world);
    if (typeof s !== 'string') return null;
    try { return JSON.parse(s); } catch { return null; }
  }

  /** 今いるページ（診断ログ用。クエリは含めない） */
  get where() {
    try { const u = new URL(this.wc.getURL()); return u.host + u.pathname; } catch { return '（なし）'; }
  }

  /** target を開き、ログインページが出たら保存済みのID・パスワードで公式フォームからログインする */
  async ensureLoggedIn(target, host, spec, credentials, log = () => {}) {
    await this.load(target);
    log(`ページを開きました: ${this.where}`, true);
    if (await runAutoLogin(this.wc, spec, null, { submit: false, checkOnly: true }) !== 'login') {
      log('ログイン済みです', true);
      return;
    }
    log('ログインフォームを検出しました', true);
    if (!credentials) { log('ID・パスワードが未保存（または自動ログインがオフ）', false); throw new WebError('needsLogin'); }
    // 入力先が設定した大学のログインページ（https・ホスト一致）であることを確認してから入れる
    let cur;
    try { cur = new URL(this.wc.getURL()); } catch { cur = null; }
    if (!cur || cur.protocol !== 'https:' || cur.hostname.toLowerCase() !== host) {
      log(`ログインページのホストが設定と違うため入力しません: ${this.where}`, false);
      throw new WebError('loginFailed');
    }
    const before = this.finished;
    const result = await runAutoLogin(this.wc, spec, credentials, { submit: true, checkOnly: false });
    if (result === 'error') { log('ログインページにエラー表示があります', false); throw new WebError('loginRejected'); }
    if (result !== 'submitted') { log(`ログイン欄に入力できませんでした（${result}）`, false); throw new WebError('loginFailed'); }
    log('ID・パスワードを入力して送信しました', true);
    await this.waitForFinish(before, 30000);
    await sleep(800);
    log(`ログイン後のページ: ${this.where}`, true);
    if (await runAutoLogin(this.wc, spec, null, { submit: false, checkOnly: true }) === 'login') {
      log('ログイン後もログインフォームが表示されています（ID・パスワード違いの可能性）', false);
      throw new WebError('loginFailed');
    }
    let path = null;
    try { path = new URL(this.wc.getURL()).pathname; } catch {}
    if (path !== new URL(target).pathname) {
      await this.load(target);
      log(`目的のページを開き直しました: ${this.where}`, true);
    }
  }
}

async function clearAllSessions() {
  await appSession().clearStorageData();
  await appSession().clearCache();
}

module.exports = { PARTITION, WebError, HeadlessSession, appSession, runAutoLogin, clearAllSessions, sleep, wrap };
