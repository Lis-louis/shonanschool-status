'use strict';
// Google 公式の OAuth 2.0（デスクトップアプリ向け：ループバック＋PKCE）と Gmail API（読み取りのみ）。
// - ログインは既定のブラウザで Google のページから行う（アプリはパスワードを見ない）
// - 権限は Gmail の読み取りのみ（gmail.readonly）
// - リフレッシュトークンとクライアントシークレットは暗号化して保存（secrets.js）

const crypto = require('node:crypto');
const http = require('node:http');
const { shell } = require('electron');
const { GoogleSecrets } = require('./secrets');
const { plainText } = require('./parsers');

const SCOPE = 'https://www.googleapis.com/auth/gmail.readonly';

class GoogleAuthError extends Error {
  constructor(kind, detail) {
    super(GoogleAuthError.message(kind, detail));
    this.kind = kind;
    this.detail = detail;
  }
  static message(kind, e) {
    switch (kind) {
      case 'notConfigured': return 'GoogleのクライアントIDとシークレットが未設定です（設定 → メール）。';
      case 'cancelled': return 'ログインが中止されました。';
      case 'timeout': return 'ログインの完了を待ちましたが、時間切れになりました。';
      case 'denied': return e === 'access_denied'
        ? 'アクセスが許可されませんでした。大学の管理者が外部アプリを制限している可能性があります。' : `Googleがエラーを返しました（${e}）。`;
      case 'stateMismatch': return 'ログインの応答が正しくありません（state不一致）。もう一度お試しください。';
      case 'token': return `トークンを取得できませんでした（${e}）。`;
      default: return 'Googleにログインしていません。設定 → メール →「Googleでログイン」を押してください。';
    }
  }
}

const b64url = buf => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const randomURLSafe = n => b64url(crypto.randomBytes(n));

async function tokenRequest(form) {
  let r;
  try {
    r = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(form).toString(),
      signal: AbortSignal.timeout(20000),
    });
  } catch (e) {
    throw new GoogleAuthError('token', e.message);
  }
  const j = await r.json().catch(() => null);
  if (j && j.access_token) return j;
  throw new GoogleAuthError('token', j?.error ? `${j.error} ${j.error_description ?? ''}`.trim() : `HTTP ${r.status}`);
}

/** 127.0.0.1 で一度だけ認可コードを受け取る小さなHTTPサーバー */
function startLoopback() {
  return new Promise((resolve, reject) => {
    let done;
    const result = new Promise(r => { done = r; });
    const server = http.createServer((req, res) => {
      const params = Object.fromEntries(new URL(req.url, 'http://127.0.0.1').searchParams);
      const ok = !!params.code;
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', Connection: 'close' });
      res.end(`<!doctype html><meta charset="utf-8"><title>キャンパスハブ</title>
<body style="font-family:'Yu Gothic UI','Meiryo',sans-serif;background:#F6F8FF;color:#2B3A6E;display:grid;place-items:center;height:90vh">
<div style="background:#fff;border:1px solid #DCE4FA;border-radius:22px;padding:32px 40px;text-align:center">
<h2>${ok ? 'Googleとの連携ができました' : '連携できませんでした'}</h2>
<p>このタブを閉じて、キャンパスハブに戻ってください。</p></div></body>`);
      if (params.code || params.error) done(params);
    });
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => resolve({ port: server.address().port, result, close: () => server.close() }));
  });
}

class GoogleAuth {
  constructor() {
    this.accessToken = null;
    this.expiry = 0;
    this.pending = null;
  }

  get isSignedIn() { return GoogleSecrets.read('refreshToken') != null; }

  signOut() {
    this.accessToken = null;
    this.expiry = 0;
    GoogleSecrets.delete('refreshToken');
  }

  cancel() { this.pending?.(new GoogleAuthError('cancelled')); }

  /** ブラウザでログイン → 認可コード → トークン */
  async signIn(clientID, loginHint) {
    const secret = GoogleSecrets.read('clientSecret');
    if (!clientID || !secret) throw new GoogleAuthError('notConfigured');
    const verifier = randomURLSafe(64);
    const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
    const state = randomURLSafe(24);
    const server = await startLoopback();
    const redirect = `http://127.0.0.1:${server.port}`;
    try {
      const u = new URL('https://accounts.google.com/o/oauth2/v2/auth');
      const q = {
        client_id: clientID, redirect_uri: redirect, response_type: 'code', scope: SCOPE,
        code_challenge: challenge, code_challenge_method: 'S256', state, access_type: 'offline', prompt: 'consent',
      };
      if (loginHint) q.login_hint = loginHint;
      for (const [k, v] of Object.entries(q)) u.searchParams.set(k, v);
      await shell.openExternal(u.href);

      const callback = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new GoogleAuthError('timeout')), 300000);
        this.pending = e => { clearTimeout(timer); reject(e); };
        server.result.then(p => { clearTimeout(timer); resolve(p); });
      });
      if (callback.error) throw new GoogleAuthError('denied', callback.error);
      if (callback.state !== state) throw new GoogleAuthError('stateMismatch');
      if (!callback.code) throw new GoogleAuthError('cancelled');

      const t = await tokenRequest({
        client_id: clientID, client_secret: secret, code: callback.code, code_verifier: verifier,
        grant_type: 'authorization_code', redirect_uri: redirect,
      });
      if (!t.refresh_token) throw new GoogleAuthError('token', 'refresh_tokenがありません');
      GoogleSecrets.save('refreshToken', t.refresh_token);
      this.accessToken = t.access_token;
      this.expiry = Date.now() + ((t.expires_in ?? 3000) - 60) * 1000;
    } finally {
      this.pending = null;
      server.close();
    }
  }

  async validAccessToken(clientID) {
    if (this.accessToken && Date.now() < this.expiry) return this.accessToken;
    const refresh = GoogleSecrets.read('refreshToken');
    if (!refresh) throw new GoogleAuthError('notSignedIn');
    const secret = GoogleSecrets.read('clientSecret');
    if (!clientID || !secret) throw new GoogleAuthError('notConfigured');
    try {
      const t = await tokenRequest({ client_id: clientID, client_secret: secret, refresh_token: refresh, grant_type: 'refresh_token' });
      this.accessToken = t.access_token;
      this.expiry = Date.now() + ((t.expires_in ?? 3000) - 60) * 1000;
      return t.access_token;
    } catch (e) {
      if (e instanceof GoogleAuthError && e.kind === 'token' && String(e.detail).includes('invalid_grant')) {
        GoogleSecrets.delete('refreshToken');
        throw new GoogleAuthError('notSignedIn');
      }
      throw e;
    }
  }
}

class GmailError extends Error {
  constructor(code, body) {
    let m;
    if (code === 403 && (body.includes('accessNotConfigured') || body.includes('has not been used'))) {
      m = 'Google Cloud で Gmail API が有効になっていません。プロジェクトで「Gmail API」を有効にしてください。';
    } else if (code === 401) {
      m = 'Googleの認証が切れました。設定 → メールからもう一度ログインしてください。';
    } else {
      m = `Gmail APIのエラー（${code}）：${body.slice(0, 160)}`;
    }
    super(m);
  }
}

/** Gmail API（読み取りのみ）。件名・差出人・日時・冒頭の抜粋（snippet）だけを取得する */
class GmailClient {
  constructor(token) { this.token = token; }

  async get(path, query = []) {
    const u = new URL('https://gmail.googleapis.com/gmail/v1/users/me/' + path);
    for (const [k, v] of query) u.searchParams.append(k, v);
    const r = await fetch(u, { headers: { Authorization: `Bearer ${this.token}` }, signal: AbortSignal.timeout(20000) });
    const text = await r.text();
    if (!r.ok) throw new GmailError(r.status, text);
    return JSON.parse(text);
  }

  async fetch(query, max = 60) {
    const profile = await this.get('profile');
    const inbox = await this.get('labels/INBOX').catch(() => null);
    const list = await this.get('messages', [['q', query], ['maxResults', String(max)]]);
    const ids = (list.messages ?? []).map(m => m.id);
    const messages = [];
    // 6件ずつ並行して取得
    for (let i = 0; i < ids.length; i += 6) {
      messages.push(...await Promise.all(ids.slice(i, i + 6).map(id =>
        this.get(`messages/${id}`, [['format', 'metadata'], ['metadataHeaders', 'Subject'], ['metadataHeaders', 'From']]))));
    }
    return { email: profile.emailAddress, unread: inbox?.messagesUnread ?? 0, messages };
  }

  /** Google フォームの「回答のコピー」メール（件名・抜粋・日時） */
  async formReceipts(days = 180) {
    const list = await this.get('messages', [['q', `from:forms-receipts-noreply@google.com newer_than:${days}d`], ['maxResults', '100']]);
    const out = [];
    for (const ref of (list.messages ?? []).slice(0, 100)) {
      const m = await this.get(`messages/${ref.id}`, [['format', 'metadata'], ['metadataHeaders', 'Subject']]);
      const subject = m.payload?.headers?.find(h => h.name.toLowerCase() === 'subject')?.value ?? '';
      out.push({ text: subject + ' ' + plainText(m.snippet ?? ''), date: Number(m.internalDate ?? 0) });
    }
    return out;
  }
}

module.exports = { GoogleAuth, GoogleAuthError, GmailClient };
