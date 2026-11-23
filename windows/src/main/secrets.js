'use strict';
// ID・パスワード・Google のトークンを暗号化して保存する。
// - Windows では DPAPI（このWindowsユーザーでログオン中だけ復号できる）、Mac で開発中はキーチェーンの鍵で暗号化される（Electron safeStorage）
// - 保存先: %APPDATA%\キャンパスハブ\secrets.json（中身は暗号文だけ）
// - 画面やログには出さない。使うのは公式ログインページの入力欄へ入れるときと、Google のトークン更新のときだけ

const fs = require('node:fs');
const path = require('node:path');
const { app, safeStorage } = require('electron');

const file = () => path.join(app.getPath('userData'), 'secrets.json');

function readAll() {
  try { return JSON.parse(fs.readFileSync(file(), 'utf8')) || {}; } catch { return {}; }
}

function writeAll(obj) {
  fs.mkdirSync(path.dirname(file()), { recursive: true });
  const tmp = file() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(obj), { mode: 0o600 });
  fs.renameSync(tmp, file());
}

const Secrets = {
  available: () => safeStorage.isEncryptionAvailable(),

  save(key, value) {
    if (!safeStorage.isEncryptionAvailable()) return false;
    const all = readAll();
    all[key] = safeStorage.encryptString(String(value)).toString('base64');
    writeAll(all);
    return true;
  },

  read(key) {
    const v = readAll()[key];
    if (!v || !safeStorage.isEncryptionAvailable()) return null;
    try { return safeStorage.decryptString(Buffer.from(v, 'base64')); } catch { return null; }
  },

  delete(key) {
    const all = readAll();
    if (key in all) { delete all[key]; writeAll(all); }
  },
};

/** Moodle / Campus Square のID・パスワード */
const CredentialStore = {
  save(service, c) { return Secrets.save(`cred.${service}`, JSON.stringify({ username: c.username, password: c.password })); },
  read(service) {
    const s = Secrets.read(`cred.${service}`);
    try { return s ? JSON.parse(s) : null; } catch { return null; }
  },
  delete(service) { Secrets.delete(`cred.${service}`); },
};

/** Google のクライアントシークレット・リフレッシュトークン */
const GoogleSecrets = {
  save: (key, v) => Secrets.save(`google.${key}`, v),
  read: key => Secrets.read(`google.${key}`),
  delete: key => Secrets.delete(`google.${key}`),
};

module.exports = { Secrets, CredentialStore, GoogleSecrets };
