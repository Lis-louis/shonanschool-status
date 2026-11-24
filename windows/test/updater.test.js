'use strict';
// 自動更新（updater.js）の状態の移り変わり。electron と electron-updater は偽物に差し替えて確かめる。
const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');

function load() {
  const fake = new EventEmitter();
  fake.checks = 0;
  fake.installed = null;
  fake.checkForUpdates = async () => { fake.checks++; };
  fake.quitAndInstall = (silent, run) => { fake.installed = { silent, run }; };
  const stub = (name, exports) => { const p = require.resolve(name); require.cache[p] = { id: p, filename: p, loaded: true, exports }; };
  stub('electron', { app: { isPackaged: true, getVersion: () => '0.3.2' } });
  stub('electron-updater', { autoUpdater: fake });
  delete require.cache[require.resolve('../src/main/updater')];
  const { Updater } = require('../src/main/updater');
  const store = { update: null, toasts: [], diags: [], emit() {}, setToast(t) { this.toasts.push(t); }, diag(_s, m) { this.diags.push(m); } };
  return { fake, store, Updater };
}

test('ダウンロード → 準備完了 → 再起動して更新', { skip: process.platform !== 'win32' }, t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const { fake, store, Updater } = load();
  const u = new Updater(store);
  u.start();
  t.mock.timers.tick(10 * 1000);
  assert.equal(fake.checks, 1);
  fake.emit('update-available', { version: '0.3.3' });
  assert.deepEqual(store.update, { status: 'downloading', version: '0.3.3', percent: 0 });
  fake.emit('download-progress', { percent: 42.7 });
  assert.equal(store.update.percent, 42);
  fake.emit('update-downloaded', { version: '0.3.3' });
  assert.deepEqual(store.update, { status: 'ready', version: '0.3.3' });
  u.install();
  assert.deepEqual(fake.installed, { silent: true, run: true });
});

test('準備完了のまま使い続けても、さらに新しい版を確かめる（失敗したら元の表示に戻す）', { skip: process.platform !== 'win32' }, t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const { fake, store, Updater } = load();
  const u = new Updater(store);
  u.start();
  t.mock.timers.tick(10 * 1000);
  fake.emit('update-available', { version: '0.3.3' });
  fake.emit('update-downloaded', { version: '0.3.3' });
  // 3時間後の確認：準備済みでも確認する
  t.mock.timers.tick(3 * 60 * 60 * 1000);
  assert.equal(fake.checks, 2);
  // 同じ版なら表示は変えない
  fake.emit('update-available', { version: '0.3.3' });
  assert.equal(store.update.status, 'ready');
  // さらに新しい版 → ダウンロード中 → 失敗したら 0.3.3 の「再起動して更新」に戻す
  fake.emit('update-available', { version: '0.3.4' });
  assert.equal(store.update.status, 'downloading');
  fake.emit('error', new Error('net::ERR_INTERNET_DISCONNECTED'));
  assert.deepEqual(store.update, { status: 'ready', version: '0.3.3' });
  // 成功すれば新しい版になる
  fake.emit('update-available', { version: '0.3.4' });
  fake.emit('update-downloaded', { version: '0.3.4' });
  assert.deepEqual(store.update, { status: 'ready', version: '0.3.4' });
  // 手動の確認：準備済みならその旨を知らせる
  u.check(true);
  assert.match(store.toasts.at(-1), /準備ができています/);
});

test('ダウンロード中は重ねて確認しない', { skip: process.platform !== 'win32' }, t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const { fake, store, Updater } = load();
  const u = new Updater(store);
  u.start();
  t.mock.timers.tick(10 * 1000);
  fake.emit('update-available', { version: '0.3.3' });
  u.check(true);
  assert.equal(fake.checks, 1);
  assert.match(store.toasts.at(-1), /ダウンロード中/);
  // 失敗して、準備済みの版も無ければ表示を消す
  fake.emit('error', new Error('x'));
  assert.equal(store.update, null);
});
