'use strict';
// キャンパスハブ（Windows版）の起動・ウィンドウ・画面とのやりとり。

const fs = require('node:fs');
const path = require('node:path');
const { app, BrowserWindow, Menu, ipcMain, shell, clipboard, dialog, nativeTheme } = require('electron');
const { AppStore } = require('./store');
const { BrowserController } = require('./browser');
const { appSession } = require('./web');
const { SafeURL, Urls } = require('./config');

const APP_ID = 'local.campushub.app';
const SECTIONS = ['home', 'calendar', 'moodle', 'campusSquare', 'mail', 'settings'];

app.setName('キャンパスハブ');
if (process.platform === 'win32') app.setAppUserModelId(APP_ID);

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', (_e, argv) => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.focus();
    const s = sectionFromArgs(argv);
    if (s) win.webContents.send('navigate', s);
  });
  app.whenReady().then(start);
}

let win = null;
let store = null;
/** 画面上でブラウザを表示する場所（renderer が知らせる） */
let browserPlacement = null;

function sectionFromArgs(argv) {
  const i = argv.indexOf('--section');
  return i >= 0 && SECTIONS.includes(argv[i + 1]) ? argv[i + 1] : null;
}

/** 鈴の画像（Mac版と同じファイル）。開発中はリポジトリの Sources から、配布版は resources から読む */
function artwork() {
  const dirs = [
    path.join(process.resourcesPath ?? '', 'Appearance'),
    path.join(__dirname, '..', '..', '..', 'Sources', 'CampusHub', 'Resources', 'Appearance'),
  ];
  const dir = dirs.find(d => fs.existsSync(path.join(d, 'face_smile.jpg')));
  const out = {};
  if (!dir) return out;
  for (const n of ['face_calm', 'face_laugh', 'face_smile', 'hero_day', 'hero_night']) {
    try { out[n] = 'data:image/jpeg;base64,' + fs.readFileSync(path.join(dir, `${n}.jpg`)).toString('base64'); } catch {}
  }
  return out;
}

function setupDownloads() {
  appSession().on('will-download', (_e, item, wc) => {
    const owner = Object.values(store.browsers).find(b => b.wc === wc);
    if (!owner) { item.cancel(); return; } // 裏の読み取り用ウィンドウではダウンロードしない
    const dir = app.getPath('downloads');
    const safe = path.basename(item.getFilename() || '') || 'download';
    const ext = path.extname(safe), base = ext ? safe.slice(0, -ext.length) : safe;
    let dest = path.join(dir, safe);
    for (let n = 1; fs.existsSync(dest); n++) dest = path.join(dir, `${base} (${n})${ext}`);
    item.setSavePath(dest);
    owner.setMessage(`ダウンロード中：${path.basename(dest)}`);
    item.once('done', (_ev, state) => {
      if (state === 'completed') {
        owner.setMessage(`ダウンロードしました：${path.basename(dest)}`);
        shell.showItemInFolder(dest);
      } else if (state !== 'cancelled') {
        owner.setMessage('ダウンロードに失敗しました');
      }
    });
  });
}

function placeBrowsers() {
  for (const [k, b] of Object.entries(store.browsers)) {
    const show = browserPlacement && browserPlacement.service === k;
    if (show) {
      const r = browserPlacement.bounds;
      b.view.setBounds({ x: Math.round(r.x), y: Math.round(r.y), width: Math.max(0, Math.round(r.width)), height: Math.max(0, Math.round(r.height)) });
      b.loadIfNeeded();
    }
    b.view.setVisible(!!show);
  }
}

function buildMenu() {
  const template = [
    {
      label: 'ファイル',
      submenu: [
        { label: '更新', accelerator: 'CmdOrCtrl+R', click: () => store.refresh() },
        { type: 'separator' },
        { label: '診断ログのフォルダを開く', click: () => shell.showItemInFolder(require('./store').DiagFile.path) },
        { type: 'separator' },
        { role: 'quit', label: '終了' },
      ],
    },
    {
      label: '編集',
      submenu: [
        { role: 'undo', label: '元に戻す' }, { role: 'redo', label: 'やり直す' }, { type: 'separator' },
        { role: 'cut', label: '切り取り' }, { role: 'copy', label: 'コピー' }, { role: 'paste', label: '貼り付け' },
        { role: 'selectAll', label: 'すべて選択' },
      ],
    },
    {
      label: '表示',
      submenu: [
        ...SECTIONS.map((s, i) => ({
          label: ['ホーム', 'カレンダー', 'Moodle', 'Campus Square', 'メール', '設定'][i],
          accelerator: `CmdOrCtrl+${i + 1}`,
          click: () => win?.webContents.send('navigate', s),
        })),
        { type: 'separator' },
        { role: 'resetZoom', label: '実際のサイズ' }, { role: 'zoomIn', label: '拡大' }, { role: 'zoomOut', label: '縮小' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: '全画面表示' },
        ...(app.isPackaged ? [] : [{ role: 'toggleDevTools', label: '開発者ツール' }]),
      ],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  const dark = nativeTheme.shouldUseDarkColors;
  win = new BrowserWindow({
    width: 1000, height: 820, minWidth: 420, minHeight: 560,
    title: 'キャンパスハブ',
    backgroundColor: dark ? '#0F1530' : '#F6F8FF',
    autoHideMenuBar: true,
    icon: path.join(__dirname, '..', '..', 'build', 'icon.png'),
    show: false,
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload.js'),
      contextIsolation: true, sandbox: true, nodeIntegration: false, spellcheck: false,
    },
  });
  win.once('ready-to-show', () => win.show());

  for (const s of ['moodle', 'campus']) {
    const b = new BrowserController(s, store);
    store.browsers[s] = b;
    win.contentView.addChildView(b.view);
  }

  // 画面そのものは外のページへ移らない（リンクは既定のブラウザで開く）
  win.webContents.on('will-navigate', e => {
    e.preventDefault();
    if (/^https?:|^mailto:/i.test(e.url)) shell.openExternal(e.url);
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:|^mailto:/i.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
  // 裏の読み取り用ウィンドウが残っていても、メインのウィンドウを閉じたら終了する
  win.on('closed', () => { win = null; app.quit(); });
}

function registerIPC() {
  const fromApp = e => win && e.sender === win.webContents;
  const art = artwork();

  ipcMain.handle('init', e => {
    if (!fromApp(e)) return null;
    return { state: store.snapshot(), artwork: art, section: sectionFromArgs(process.argv), platform: process.platform };
  });

  const actions = {
    refresh: () => store.refresh(),
    setConfig: (k, v) => store.setConfig(k, v),
    setPref: (k, v) => store.setPref(k, v),
    resetConfig: () => store.resetConfig(),
    saveCredentials: (s, u, p) => store.saveCredentials(s === 'campus' ? 'campus' : 'moodle', u, p),
    deleteCredentials: s => store.deleteCredentials(s === 'campus' ? 'campus' : 'moodle'),
    clearSessions: () => store.clearSessions(),
    saveGoogleClient: (i, s) => store.saveGoogleClient(i, s),
    signInGoogle: () => store.signInGoogle(),
    cancelGoogle: () => store.cancelGoogle(),
    signOutGoogle: () => store.signOutGoogle(),
    toggleDone: id => store.toggleDone(String(id)),
    loadMonth: (y, m) => store.loadMonth(Number(y), Number(m)),
    dismissToast: () => store.setToast(null),
    testNotification: () => store.testNotification(),
    copyText: t => { clipboard.writeText(String(t ?? '')); },
    toast: t => store.setToast(String(t ?? '')),
    openDiagFolder: () => shell.showItemInFolder(require('./store').DiagFile.path),
    /** 既定のブラウザで開く（https / mailto だけ） */
    openExternal: url => {
      const u = String(url ?? '');
      if (SafeURL.https(u) || /^mailto:/i.test(u)) shell.openExternal(u);
    },
    /** アプリ内ブラウザで開く（大学のドメインだけ） */
    openInApp: (service, url) => {
      const b = store.browsers[service === 'campus' ? 'campus' : 'moodle'];
      const u = SafeURL.https(url);
      if (b && u && SafeURL.isTrusted(u, store.config.trustedDomain)) b.load(u);
      else if (u) shell.openExternal(u);
    },
    browserPlace: (service, bounds) => {
      browserPlacement = service && bounds ? { service, bounds } : null;
      placeBrowsers();
    },
    browserNav: (service, cmd) => {
      const b = store.browsers[service];
      if (!b) return;
      const h = b.wc.navigationHistory;
      if (cmd === 'back' && h.canGoBack()) h.goBack();
      if (cmd === 'forward' && h.canGoForward()) h.goForward();
      if (cmd === 'reload') b.wc.reload();
      if (cmd === 'home') b.load(Urls.startURL(store.config, service));
      if (cmd === 'fill') b.fillCredentialsNow();
      if (cmd === 'dismiss') b.setMessage(null);
    },
    browserMenu: (service, x, y) => {
      const b = store.browsers[service];
      if (!b || !win) return;
      const url = b.wc.getURL();
      const items = [];
      if (service === 'campus' && SafeURL.https(url)) {
        items.push(
          { label: 'このページを「時間割」に設定', click: () => store.setCampusPage('timetable', url) },
          { label: 'このページを「休講・補講」に設定', click: () => store.setCampusPage('cancellations', url) },
          { label: 'このページを「成績」に設定', click: () => store.setCampusPage('grades', url) },
          { type: 'separator' },
        );
      }
      items.push(
        { label: '既定のブラウザで開く', enabled: !!SafeURL.https(url), click: () => shell.openExternal(url) },
        { label: 'URLをコピー', click: () => clipboard.writeText(url) },
      );
      Menu.buildFromTemplate(items).popup({ window: win, x: Math.round(x), y: Math.round(y) });
    },
    confirm: async (message, ok) => {
      const r = await dialog.showMessageBox(win, { type: 'question', message: String(message), buttons: [String(ok || 'OK'), 'キャンセル'], defaultId: 1, cancelId: 1 });
      return r.response === 0;
    },
  };

  ipcMain.handle('action', async (e, name, ...args) => {
    if (!fromApp(e) || !Object.hasOwn(actions, name)) return null;
    return actions[name](...args);
  });

  store.onChange(s => { if (win && !win.isDestroyed()) win.webContents.send('state', s); });
}

function start() {
  store = new AppStore();
  setupDownloads();
  buildMenu();
  registerIPC();
  createWindow();
  nativeTheme.on('updated', () => {
    win?.setBackgroundColor(nativeTheme.shouldUseDarkColors ? '#0F1530' : '#F6F8FF');
  });
  store.refresh();
}

app.on('window-all-closed', () => app.quit());

// ほかのウィンドウ（裏の読み取り用など）を勝手に開かせない
app.on('web-contents-created', (_e, wc) => {
  wc.on('will-attach-webview', ev => ev.preventDefault());
});
