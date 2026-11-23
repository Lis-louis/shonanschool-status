'use strict';
// アプリ内ブラウザ（公式サイトをそのまま表示）。
// - 大学のドメイン以外へのリンクは既定のブラウザで開く
// - 公式ログインページを開いたときだけ、保存済みのID・パスワードを自動入力する
// - 教材のダウンロード（ダウンロード フォルダ）・課題ファイルのアップロード（標準のファイル選択）に対応

const { WebContentsView, shell } = require('electron');
const { SafeURL, Urls } = require('./config');
const Scripts = require('./scripts');
const { appSession, runAutoLogin } = require('./web');

const EXTERNAL_SCHEMES = ['http:', 'https:', 'mailto:'];

class BrowserController {
  /** @param {'moodle'|'campus'} service  @param {import('./store').AppStore} store */
  constructor(service, store) {
    this.service = service;
    this.store = store;
    this.view = new WebContentsView({
      webPreferences: { session: appSession(), sandbox: true, contextIsolation: true },
    });
    this.view.setVisible(false);
    this.view.setBackgroundColor('#00000000');
    this.hasLoaded = false;
    this.lastAutoSubmit = 0;
    this.message = null;
    this.attached = false;
    const wc = this.view.webContents;

    const sync = () => this.store.emit();
    wc.on('did-start-loading', sync);
    wc.on('did-stop-loading', sync);
    wc.on('page-title-updated', sync);
    wc.on('did-navigate', sync);
    wc.on('did-navigate-in-page', sync);
    wc.on('did-finish-load', () => {
      sync();
      this.applyTheme();
      this.tryAutoLogin();
    });
    wc.on('did-fail-load', (_e, code, desc, _url, isMain) => {
      sync();
      if (!isMain || code === -3) return; // 中止・ダウンロードへの切り替え
      this.setMessage(`ページを開けませんでした：${desc}`);
    });

    // 大学以外のサイト・メールリンク等は既定のアプリで開く
    const guard = (e, url, isMain) => {
      let u;
      try { u = new URL(url); } catch { return; }
      if (['about:', 'blob:', 'data:', 'javascript:'].includes(u.protocol)) return;
      if (isMain && !SafeURL.isTrusted(url, this.store.config.trustedDomain)) {
        e.preventDefault();
        if (EXTERNAL_SCHEMES.includes(u.protocol)) shell.openExternal(url);
      }
    };
    wc.on('will-navigate', e => guard(e, e.url, e.isMainFrame));
    wc.on('will-redirect', e => guard(e, e.url, e.isMainFrame));

    // target=_blank / window.open は同じ画面で開く
    wc.setWindowOpenHandler(({ url }) => {
      if (SafeURL.isTrusted(url, this.store.config.trustedDomain)) wc.loadURL(url);
      else if (/^https?:/i.test(url)) shell.openExternal(url);
      return { action: 'deny' };
    });
  }

  get wc() { return this.view.webContents; }

  info() {
    const wc = this.wc;
    let host = '';
    try { host = new URL(wc.getURL()).host; } catch {}
    return {
      canGoBack: wc.navigationHistory.canGoBack(), canGoForward: wc.navigationHistory.canGoForward(),
      isLoading: wc.isLoading(), url: wc.getURL(), host, title: wc.getTitle(), message: this.message,
    };
  }

  setMessage(m) {
    this.message = m;
    this.store.emit();
    if (m) setTimeout(() => { if (this.message === m) { this.message = null; this.store.emit(); } }, 6000);
  }

  load(url) {
    if (!url) return;
    this.hasLoaded = true;
    this.wc.loadURL(url).catch(() => {});
  }

  loadIfNeeded() {
    if (!this.hasLoaded) this.load(Urls.startURL(this.store.config, this.service));
  }

  async applyTheme() {
    if (!this.store.prefs.themeOfficialPages) return;
    if (!SafeURL.isTrusted(this.wc.getURL(), this.store.config.trustedDomain)) return;
    try { await this.wc.insertCSS(Scripts.themeCSS); } catch {}
  }

  /** 現在のページが設定した大学のログインページ（https・ホスト一致）なら、その入力欄定義と資格情報を返す */
  loginContext() {
    let u;
    try { u = new URL(this.wc.getURL()); } catch { return null; }
    const c = this.store.config;
    if (u.protocol !== 'https:' || u.hostname.toLowerCase() !== Urls.loginHost(c, this.service)) return null;
    return { spec: Urls.loginSpec(c, this.service), creds: this.store.credentials(this.service) };
  }

  /** 「ログイン情報を入力」ボタン用（押したときはボタンも押す） */
  async fillCredentialsNow() {
    const ctx = this.loginContext();
    if (!ctx) return this.setMessage('このページは自動入力の対象外です（設定した大学のログインページではありません）。');
    if (!ctx.creds) return this.setMessage('ID・パスワードが保存されていません。設定で保存してください。');
    const r = await runAutoLogin(this.wc, ctx.spec, ctx.creds, { submit: true, checkOnly: false });
    this.setMessage(r === 'submitted' ? 'ログイン情報を入力しました。'
      : r === 'error' ? 'ログインページにエラーが表示されています。ID・パスワードを確認してください。'
        : 'このページにログイン欄が見つかりません。');
  }

  async tryAutoLogin() {
    if (!this.store.prefs.autoLogin) return;
    const ctx = this.loginContext();
    if (!ctx || !ctx.creds) return;
    if (await runAutoLogin(this.wc, ctx.spec, null, { submit: false, checkOnly: true }) !== 'login') return;
    // 同じ失敗を繰り返さないよう、自動でボタンを押すのは30秒に1回まで
    const canSubmit = Date.now() - this.lastAutoSubmit > 30000;
    const r = await runAutoLogin(this.wc, ctx.spec, ctx.creds, { submit: canSubmit, checkOnly: false });
    if (r === 'submitted') { this.lastAutoSubmit = Date.now(); this.setMessage('自動ログインしています…'); }
    if (r === 'error') this.setMessage('ログインに失敗したようです。ID・パスワードを確認してください。');
  }
}

module.exports = { BrowserController };
