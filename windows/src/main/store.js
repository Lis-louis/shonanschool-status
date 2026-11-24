'use strict';
// 状態管理と読み込みの流れ（Mac版 Store/AppStore.swift と同じ動き）。
// 画面（renderer）には emit() で状態をまるごと送り、画面からの操作は actions で受ける。

const fs = require('node:fs');
const path = require('node:path');
const { app, Notification } = require('electron');
const { DEFAULT_CONFIG, DEFAULT_PREFS, mergeDefaults, SafeURL, Urls, serviceLabel } = require('./config');
const { CredentialStore, GoogleSecrets, Secrets } = require('./secrets');
const { HeadlessSession, WebError, clearAllSessions, sleep } = require('./web');
const { GoogleAuth, GoogleAuthError, GmailClient } = require('./google');
const Parsers = require('./parsers');
const Scripts = require('./scripts');
const Sample = require('./sample');

const loading = () => ({ state: 'loading' });
const loaded = value => ({ state: 'loaded', value });
const notConfigured = message => ({ state: 'notConfigured', message });
const failed = message => ({ state: 'failed', message });

const monthKey = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;

/** 診断ログのファイル（%APPDATA%\キャンパスハブ\logs\diagnostics.log）。ID・パスワード・内容は書かない */
const DiagFile = {
  get path() { return path.join(app.getPath('logs'), 'diagnostics.log'); },
  append(e) {
    try {
      fs.mkdirSync(path.dirname(this.path), { recursive: true });
      try { if (fs.statSync(this.path).size > 1_000_000) fs.rmSync(this.path); } catch {}
      const t = new Date(e.time);
      const off = -t.getTimezoneOffset();
      const pad = n => String(Math.abs(n)).padStart(2, '0');
      const iso = `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}T${pad(t.getHours())}:${pad(t.getMinutes())}:${pad(t.getSeconds())}`
        + `${off >= 0 ? '+' : '-'}${pad(Math.trunc(off / 60))}:${pad(off % 60)}`;
      fs.appendFileSync(this.path, `${iso} [${e.service}] ${e.ok ? 'OK' : 'NG'} ${e.message}\n`);
    } catch {}
  },
};

class AppStore {
  constructor() {
    this.file = path.join(app.getPath('userData'), 'settings.json');
    let saved = {};
    try { saved = JSON.parse(fs.readFileSync(this.file, 'utf8')) || {}; } catch {}
    this.config = mergeDefaults(DEFAULT_CONFIG, saved.config);
    this.prefs = mergeDefaults(DEFAULT_PREFS, saved.prefs);
    this.doneIDs = new Set(Array.isArray(saved.doneIDs) ? saved.doneIDs : []);

    this.moodle = loading();
    this.campus = loading();
    this.mail = loading();
    this.lastUpdated = null;
    /** アプリの自動更新（updater.js が書き換える）: null | { status: 'downloading' | 'ready', version, percent } */
    this.update = null;
    this.isRefreshing = false;
    this.toast = null;
    this.diagnostics = [];
    this.campusMenu = [];
    this.googleBusy = false;
    this.monthItems = {};
    this.monthErrors = {};
    this.monthLoading = new Set();

    this.sessions = {};
    this.google = new GoogleAuth();
    this.browsers = {};
    this.listeners = new Set();
    this.emitTimer = null;
    this.notifyTimer = null;
    this.scheduled = [];
    this.refreshSecrets();
  }

  /** 保存済みかどうか（復号は保存・削除のときだけ行い、結果を覚えておく） */
  refreshSecrets() {
    this.savedUsername = { moodle: CredentialStore.read('moodle')?.username ?? null, campus: CredentialStore.read('campus')?.username ?? null };
    this.hasRefreshToken = GoogleSecrets.read('refreshToken') != null;
    this.hasClientSecret = GoogleSecrets.read('clientSecret') != null;
  }

  // MARK: - 画面への通知

  onChange(fn) { this.listeners.add(fn); }

  emit() {
    if (this.emitTimer) return;
    this.emitTimer = setTimeout(() => {
      this.emitTimer = null;
      const s = this.snapshot();
      for (const fn of this.listeners) fn(s);
    }, 16);
  }

  snapshot() {
    const browsers = {};
    for (const [k, b] of Object.entries(this.browsers)) browsers[k] = b.info();
    return {
      config: this.config, prefs: this.prefs, doneIDs: [...this.doneIDs],
      moodle: this.moodle, campus: this.campus, mail: this.mail,
      lastUpdated: this.lastUpdated, isRefreshing: this.isRefreshing, toast: this.toast,
      diagnostics: this.diagnostics, campusMenu: this.campusMenu,
      savedUsername: this.savedUsername,
      googleSignedIn: this.googleSignedIn, googleClientReady: this.googleClientReady, googleBusy: this.googleBusy,
      monthItems: this.monthItems, monthErrors: this.monthErrors, monthLoading: [...this.monthLoading],
      browsers, encryptionAvailable: Secrets.available(), diagPath: DiagFile.path,
      update: this.update, appVersion: app.getVersion(),
    };
  }

  setToast(t) {
    this.toast = t ? { text: t, id: Date.now() } : null;
    this.emit();
  }

  save() {
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      fs.writeFileSync(this.file + '.tmp', JSON.stringify({ config: this.config, prefs: this.prefs, doneIDs: [...this.doneIDs] }, null, 2));
      fs.renameSync(this.file + '.tmp', this.file);
    } catch (e) {
      this.diag('全体', `設定を保存できませんでした: ${e.message}`, false);
    }
  }

  diag(service, message, ok = true) {
    const e = { id: `${Date.now()}-${Math.random()}`, time: Date.now(), service, message, ok };
    this.diagnostics.push(e);
    if (this.diagnostics.length > 300) this.diagnostics.splice(0, this.diagnostics.length - 300);
    DiagFile.append(e);
    this.emit();
  }

  // MARK: - 設定

  setConfig(keyPath, value) {
    const keys = String(keyPath).split('.');
    let o = this.config;
    for (const k of keys.slice(0, -1)) {
      if (!o[k] || typeof o[k] !== 'object') return;
      o = o[k];
    }
    const last = keys.at(-1);
    if (!(last in o) || typeof value !== 'string') return;
    o[last] = value;
    this.save();
    this.emit();
  }

  setPref(key, value) {
    if (!(key in DEFAULT_PREFS) || typeof value !== typeof DEFAULT_PREFS[key]) return;
    const old = this.prefs[key];
    if (old === value) return;
    this.prefs[key] = value;
    this.save();
    this.emit();
    if (key === 'useSampleData' || key === 'deadlineWindowDays') this.refresh();
    if (key === 'notificationsEnabled' || key === 'notifyHoursBefore') this.updateNotifications();
  }

  resetConfig() {
    const mail = this.config.mail;
    this.config = structuredClone(DEFAULT_CONFIG);
    this.config.mail.address = mail.address;
    this.config.mail.googleClientID = mail.googleClientID;
    this.config.mail.searchQuery = mail.searchQuery;
    this.save();
    this.setToast('URLを初期値に戻しました');
  }

  setCampusPage(key, url) {
    if (!['timetable', 'cancellations', 'grades'].includes(key) || !SafeURL.https(url)) return;
    this.config.campusSquare[key] = SafeURL.stableCampusURL(url);
    this.save();
    this.setToast('設定しました。次の更新から反映されます');
  }

  // MARK: - ログイン情報

  credentials(s) {
    return CredentialStore.read(s === 'campus' && this.prefs.sameCredentials ? 'moodle' : s);
  }

  loginCredentials(s) { return this.prefs.autoLogin ? this.credentials(s) : null; }

  saveCredentials(service, username, password) {
    const u = String(username ?? '').trim();
    if (!u || !password) return 'IDとパスワードを入力してください。';
    if (!Secrets.available()) return 'このPCでは暗号化した保存が使えません。';
    if (!CredentialStore.save(service, { username: u, password: String(password) })) return '保存に失敗しました。';
    this.refreshSecrets();
    this.setToast(`${serviceLabel(service)}のログイン情報を保存しました`);
    this.refresh();
    return null;
  }

  deleteCredentials(service) {
    CredentialStore.delete(service);
    this.refreshSecrets();
    this.setToast(`${serviceLabel(service)}のログイン情報を削除しました`);
  }

  async clearSessions() {
    await clearAllSessions();
    for (const s of Object.values(this.sessions)) s.destroy();
    this.sessions = {};
    this.setToast('ログイン状態（Cookie）を消去しました');
    await this.refresh();
  }

  // MARK: - Google

  get googleSignedIn() { return this.hasRefreshToken; }
  get googleClientReady() { return !!this.config.mail.googleClientID && this.hasClientSecret; }

  saveGoogleClient(id, secret) {
    const i = String(id ?? '').trim(), s = String(secret ?? '').trim();
    if (!i.endsWith('.apps.googleusercontent.com')) return 'クライアントIDは「….apps.googleusercontent.com」の形です。';
    if (!s) return 'クライアントシークレットを入力してください。';
    if (!GoogleSecrets.save('clientSecret', s)) return 'このPCでは暗号化した保存が使えません。';
    this.refreshSecrets();
    this.config.mail.googleClientID = i;
    this.save();
    this.setToast('Googleのクライアント情報を保存しました');
    return null;
  }

  async signInGoogle() {
    if (this.googleBusy) return;
    this.googleBusy = true;
    this.emit();
    try {
      this.diag('メール', 'ブラウザでGoogleのログインを開きました');
      await this.google.signIn(this.config.mail.googleClientID, this.config.mail.address);
      this.refreshSecrets();
      this.diag('メール', 'Googleとの連携が完了しました');
      this.setToast('Googleと連携しました');
      this.mail = loading();
      this.emit();
      this.mail = await this.fetchMail();
    } catch (e) {
      this.diag('メール', `Googleのログインに失敗: ${e.message}`, false);
      this.setToast(e.message);
    } finally {
      this.googleBusy = false;
      this.emit();
    }
  }

  cancelGoogle() { this.google.cancel(); }

  signOutGoogle() {
    this.google.signOut();
    this.refreshSecrets();
    this.mail = notConfigured('Googleとの連携を解除しました。');
    this.setToast('Googleとの連携を解除しました');
  }

  // MARK: - やること

  toggleDone(id) {
    if (this.doneIDs.has(id)) this.doneIDs.delete(id); else this.doneIDs.add(id);
    this.save();
    this.emit();
  }

  // MARK: - カレンダー

  async loadMonth(year, month, force = false) {
    const key = `${year}-${String(month).padStart(2, '0')}`;
    if (this.prefs.useSampleData || this.monthLoading.has(key) || (!force && this.monthItems[key])) return;
    const dash = Urls.moodleDashboard(this.config), host = Urls.loginHost(this.config, 'moodle');
    if (!dash || !host) return;
    this.monthLoading.add(key);
    this.emit();
    const s = this.session('moodle');
    try {
      let raw = await s.run(Scripts.moodleMonth, { year, mon: month }, 'page');
      if (typeof raw !== 'string' || raw.includes('nosesskey')) {
        await s.ensureLoggedIn(dash, host, this.config.moodleLogin, this.loginCredentials('moodle'), (m, ok) => this.diag('Moodle', m, ok));
        raw = await s.run(Scripts.moodleMonth, { year, mon: month }, 'page');
      }
      const items = Parsers.parseMonth(typeof raw === 'string' ? raw : '', this.config);
      this.monthItems[key] = items;
      delete this.monthErrors[key];
      this.diag('Moodle', `カレンダー ${key}: ${items.length}件`);
    } catch (e) {
      this.monthErrors[key] = e.message;
      this.diag('Moodle', `カレンダー ${key}: ${e.message}`, false);
    } finally {
      this.monthLoading.delete(key);
      this.emit();
    }
  }

  // MARK: - 読み込み

  async refresh() {
    if (this.isRefreshing) return;
    this.isRefreshing = true;
    this.emit();
    try {
      if (this.prefs.useSampleData) {
        this.moodle = loaded(Sample.moodle());
        this.campus = loaded(Sample.campus());
        this.mail = loaded(Sample.mail(this.config.trustedDomain));
        this.lastUpdated = Date.now();
        return;
      }
      this.diag('全体', '更新を開始しました');
      this.moodle = loading();
      this.campus = loading();
      // 未連携ならすぐに案内を出す（他の読み込みを待たない）
      this.mail = this.googleSignedIn ? loading() : await this.fetchMail();
      this.emit();
      const m = this.fetchMoodle().then(v => { this.moodle = v; this.emit(); });
      const c = this.fetchCampus().then(v => { this.campus = v; this.emit(); });
      const g = this.fetchMail().then(v => { this.mail = v; this.emit(); });
      await Promise.all([m, c, g]);
      this.monthItems = {};
      this.lastUpdated = Date.now();
      const now = new Date();
      await this.loadMonth(now.getFullYear(), now.getMonth() + 1);
      this.updateNotifications();
    } finally {
      this.isRefreshing = false;
      this.emit();
    }
  }

  session(s) {
    if (!this.sessions[s] || this.sessions[s].win.isDestroyed()) this.sessions[s] = new HeadlessSession();
    return this.sessions[s];
  }

  async fetchMoodle() {
    const dash = Urls.moodleDashboard(this.config), host = Urls.loginHost(this.config, 'moodle');
    if (!dash || !host) return notConfigured('MoodleのURLが正しくありません。設定を確認してください。');
    const s = this.session('moodle');
    const log = (m, ok) => this.diag('Moodle', m, ok);
    try {
      await s.ensureLoggedIn(dash, host, this.config.moodleLogin, this.loginCredentials('moodle'), log);
      const start = new Date(); start.setHours(0, 0, 0, 0);
      const from = Math.floor((start.getTime() - 14 * 86400e3) / 1000);
      const to = Math.floor((Date.now() + this.prefs.deadlineWindowDays * 86400e3) / 1000);
      const raw = await s.run(Scripts.moodleFetch, { from, to }, 'page');
      if (typeof raw !== 'string') { log('読み取りスクリプトの結果が空です', false); throw new Error('Moodleの応答を読み取れませんでした。'); }
      const snap = Parsers.parseMoodle(raw, this.config, log);
      await this.checkSubmissions(snap, s, log);
      return loaded(snap);
    } catch (e) {
      if (e instanceof WebError && e.kind === 'needsLogin') return notConfigured(e.message);
      log(e.message, false);
      return failed(e.message);
    }
  }

  /** 課題・アンケートのページを開いて提出状況を確かめ、外部フォームは Gmail の控えメールと照合する。
   *  通知（「提出期限 …: 第7回課題」など）も、リンク先が課題などのページなら同じように確かめる */
  async checkSubmissions(snap, s, log) {
    const targets = snap.deadlines.filter(d => d.url).slice(0, 60);
    const noticeTargets = snap.notices.filter(n => n.url && Parsers.isActivityURL(n.url));
    const urls = [...new Set([...targets.map(d => d.url), ...noticeTargets.map(n => n.url)])];
    if (!urls.length) return;
    try {
      const raw = await s.run(Scripts.moodleSubmissionStatus, { urls }, 'page');
      let results;
      try { results = JSON.parse(raw); } catch { results = null; }
      if (!Array.isArray(results)) { log('提出状況の確認: 結果を読めませんでした', false); return; }
      const byURL = new Map();
      for (const r of results) if (!byURL.has(r.url)) byURL.set(r.url, r);
      const valid = ['unknown', 'submitted', 'notSubmitted', 'notOpenYet', 'form', 'formReceipt'];
      for (const d of snap.deadlines) {
        const r = d.url && byURL.get(d.url);
        if (!r) continue;
        d.status = valid.includes(r.status) ? r.status : 'unknown';
        d.formURL = r.form ? SafeURL.https(r.form) : null;
      }
      for (const n of noticeTargets) {
        const r = byURL.get(n.url);
        if (r) n.status = valid.includes(r.status) ? r.status : 'unknown';
      }
      // 何の文言で判定したかを集計してログに残す（内容は残さない）
      const counts = {};
      for (const r of results) { const k = `${r.status}:${r.hit}`; counts[k] = (counts[k] ?? 0) + 1; }
      log(`提出状況の確認 ${results.length}件: ` + Object.entries(counts).map(([k, v]) => `${k}×${v}`).sort().join(' / '), true);
      if (noticeTargets.length) {
        const doneN = noticeTargets.filter(n => Parsers.doneStatus(n.status)).length;
        log(`通知のうち課題などへのリンク ${noticeTargets.length}件: 提出済み ${doneN}件を「提出済みの通知」にまとめます`, true);
      }
    } catch (e) {
      log(`提出状況の確認に失敗: ${e.message}`, false);
      return;
    }

    // 外部フォーム：Gmail に Google フォームの控えがあれば回答済みとみなす
    const forms = snap.deadlines.filter(d => d.status === 'form');
    if (!forms.length || !this.googleSignedIn) return;
    try {
      const token = await this.google.validAccessToken(this.config.mail.googleClientID);
      const receipts = await new GmailClient(token).formReceipts();
      let matched = 0;
      for (const d of forms) if (Parsers.hasReceipt(d, receipts)) { d.status = 'formReceipt'; matched++; }
      log(`フォームの控えメール ${receipts.length}通と照合: ${matched}/${forms.length}件が回答済み`, true);
    } catch (e) {
      log(`フォームの控えメールを確認できませんでした: ${e.message}`, false);
    }
    // 同じ課題の締切が「控えメールあり」になったら、その通知も回答済みにする
    const byDeadline = new Map(snap.deadlines.filter(d => d.url).map(d => [d.url, d.status]));
    for (const n of noticeTargets) if (byDeadline.get(n.url) === 'formReceipt') n.status = 'formReceipt';
  }

  async fetchCampus() {
    const portal = SafeURL.https(this.config.campusSquare.portal), host = Urls.loginHost(this.config, 'campus');
    if (!portal || !host) return notConfigured('Campus SquareのURLが正しくありません。設定を確認してください。');
    const s = this.session('campus');
    const log = (m, ok) => this.diag('Campus Square', m, ok);
    try {
      await s.ensureLoggedIn(portal, host, this.config.campusLogin, this.loginCredentials('campus'), log);
      await sleep(1500); // ポータルの枠は後から読み込まれることがある
      const portlets = (await s.runJSON(Scripts.campusPortlets)) ?? [];
      log(`ポータルの枠: ${portlets.length}個（${portlets.map(p => p.title).join('、')}）`, true);
      const menu = (await s.runJSON(Scripts.campusMenu)) ?? [];
      this.campusMenu = menu.map(m => [m.text, m.flow]);
      log('メニュー: ' + menu.map(m => `${m.text || '?'}=${m.flow}`).join(' / '), true);
      const warnings = [];

      let timetable = null;
      const ttURL = SafeURL.https(this.config.campusSquare.timetable);
      if (ttURL) {
        try {
          await s.load(ttURL);
          await sleep(3000);
          timetable = await s.runJSON(Scripts.campusTimetable);
          if (!timetable) {
            const h = await s.run(Scripts.pageHeading).catch(() => null);
            if (typeof h === 'string') {
              log(`時間割ページの見出し: ${h}`, false);
              const shapes = await s.run(Scripts.tableShapes).catch(() => null);
              if (typeof shapes === 'string') log(`表の構造: ${shapes}`, false);
            }
          }
          log(`時間割ページ ${s.where}: ` + (timetable ? `${timetable.periods.length}時限分` : '表が見つかりません'), !!timetable);
          if (!timetable) warnings.push('時間割ページで表を見つけられませんでした。「ブラウザ」タブで時間割を開き、「このページを時間割に設定」を押してください。');
        } catch (e) { warnings.push('時間割: ' + e.message); log(`時間割: ${e.message}`, false); }
      }

      let cancellations = null;
      const cURL = SafeURL.https(this.config.campusSquare.cancellations);
      if (cURL) {
        try {
          await s.load(cURL);
          await sleep(1000);
          cancellations = await s.runJSON(Scripts.largestTable);
          log(`休講ページ ${s.where}: ${cancellations?.rows?.length ?? 0}行`, true);
        } catch (e) { warnings.push('休講情報: ' + e.message); log(`休講: ${e.message}`, false); }
      }
      return loaded({ timetable, portlets, cancellations, warnings });
    } catch (e) {
      if (e instanceof WebError && e.kind === 'needsLogin') return notConfigured(e.message);
      log(e.message, false);
      return failed(e.message);
    }
  }

  async fetchMail() {
    if (!this.googleSignedIn) {
      return notConfigured(this.googleClientReady
        ? 'Googleと連携していません。設定 → メール →「Googleでログイン」を押してください。'
        : 'メールを読み込むには、設定 → メール でGoogleとの連携を設定してください。');
    }
    try {
      const token = await this.google.validAccessToken(this.config.mail.googleClientID);
      const r = await new GmailClient(token).fetch(this.config.mail.searchQuery);
      const messages = r.messages.map(m => Parsers.convertGmail(m, this.config.trustedDomain)).sort((a, b) => b.date - a.date);
      this.diag('メール', `${messages.length}通を取得（未読 ${r.unread}）`);
      return loaded({ email: r.email, messages, unreadCount: r.unread });
    } catch (e) {
      if (e instanceof GoogleAuthError && e.kind === 'notSignedIn') { this.refreshSecrets(); return notConfigured(e.message); }
      this.diag('メール', e.message, false);
      return failed(e.message);
    }
  }

  // MARK: - 締切の通知（アプリが起動している間だけ。Windows の通知センターに出る）

  updateNotifications() {
    this.scheduled = [];
    if (!this.prefs.notificationsEnabled || this.prefs.useSampleData || !Notification.isSupported()) return;
    const now = Date.now();
    const deadlines = (this.moodle.value?.deadlines ?? []).filter(d => d.due > now && d.needsAction && !Parsers.doneStatus(d.status));
    for (const d of deadlines.slice(0, 50)) {
      const fireAt = d.due - this.prefs.notifyHoursBefore * 3600e3;
      if (fireAt > now) this.scheduled.push({ id: d.id, fireAt, body: [d.title, d.course].filter(Boolean).join(' / ') });
    }
    if (!this.notifyTimer) {
      this.notifyTimer = setInterval(() => this.fireNotifications(), 30000);
    }
  }

  fireNotifications() {
    const now = Date.now();
    const due = this.scheduled.filter(n => n.fireAt <= now);
    this.scheduled = this.scheduled.filter(n => n.fireAt > now);
    for (const n of due) {
      if (this.doneIDs.has(n.id)) continue;
      new Notification({ title: '締切が近づいています', body: n.body }).show();
    }
  }

  testNotification() {
    if (!Notification.isSupported()) return this.setToast('このPCでは通知を使えません');
    new Notification({ title: 'キャンパスハブ', body: '通知のテストです。締切が近づくとこのように知らせます。' }).show();
  }
}

module.exports = { AppStore, monthKey, DiagFile };
