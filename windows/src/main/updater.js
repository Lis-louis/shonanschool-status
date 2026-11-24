'use strict';
// アプリの自動更新。
// GitHub の Releases（Lis-louis/shonanschool-status）に新しい版が出たら裏でダウンロードし、
// 画面の上に「再起動して更新」を出す。押さずに終了しても、終了するときに入れ替わる。
// Releases は windows/package.json の version を上げて main に push すると、
// GitHub Actions（.github/workflows/release-windows.yml）が自動で作る。

const { app } = require('electron');

const FIRST_CHECK_DELAY = 10 * 1000;          // 起動直後は読み込みを優先する
const CHECK_INTERVAL = 3 * 60 * 60 * 1000;   // 起動しっぱなしでも3時間ごとに確認

class Updater {
  constructor(store) {
    this.store = store;
    this.au = null;
    /** メニュー・設定から手動で確認したとき（結果をトーストで知らせる） */
    this.manual = false;
  }

  /** 配布版（インストールしたもの）だけ。開発中（npm start）は確認しない */
  get enabled() { return app.isPackaged && process.platform === 'win32'; }

  start() {
    if (!this.enabled) return;
    const { autoUpdater } = require('electron-updater');
    this.au = autoUpdater;
    autoUpdater.autoDownload = true;
    autoUpdater.autoInstallOnAppQuit = true;
    autoUpdater.logger = null;

    autoUpdater.on('update-available', i => {
      this.set({ status: 'downloading', version: i.version, percent: 0 });
      this.store.diag('アプリ', `新しいバージョン ${i.version} が見つかりました。ダウンロードします`);
    });
    autoUpdater.on('download-progress', p => {
      const u = this.store.update;
      const percent = Math.floor(p.percent ?? 0);
      if (u?.status === 'downloading' && u.percent !== percent) this.set({ ...u, percent });
    });
    autoUpdater.on('update-downloaded', i => {
      this.set({ status: 'ready', version: i.version });
      this.store.diag('アプリ', `新しいバージョン ${i.version} の準備ができました`);
      this.manual = false;
    });
    autoUpdater.on('update-not-available', () => {
      if (this.manual) this.store.setToast(`最新のバージョン（${app.getVersion()}）です`);
      this.manual = false;
    });
    autoUpdater.on('error', e => {
      const msg = String(e?.message ?? e).split('\n')[0].slice(0, 200);
      this.store.diag('アプリ', `アップデートの確認・ダウンロードに失敗: ${msg}`, false);
      if (this.manual) this.store.setToast('アップデートを確認できませんでした（インターネット接続を確認してください）');
      if (this.store.update?.status === 'downloading') this.set(null);
      this.manual = false;
    });

    setTimeout(() => this.check(), FIRST_CHECK_DELAY);
    setInterval(() => this.check(), CHECK_INTERVAL);
  }

  check(manual = false) {
    if (!this.au) {
      if (manual) this.store.setToast('開発中の起動ではアップデートを確認しません');
      return;
    }
    const st = this.store.update?.status;
    if (st === 'ready' || st === 'downloading') {
      if (manual) this.store.setToast(st === 'ready' ? '新しいバージョンの準備ができています。「再起動して更新」を押してください' : '新しいバージョンをダウンロード中です');
      return;
    }
    this.manual = manual;
    this.au.checkForUpdates().catch(() => {}); // 失敗は 'error' で扱う
  }

  /** 「再起動して更新」：インストーラーを画面なしで動かし、終わったらアプリを起動し直す */
  install() {
    if (this.au && this.store.update?.status === 'ready') this.au.quitAndInstall(true, true);
  }

  set(u) {
    this.store.update = u;
    this.store.emit();
  }
}

module.exports = { Updater };
