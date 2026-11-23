'use strict';
// 画面（renderer）に渡すのは、決まった操作の呼び出しと状態の受け取りだけ。
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('hub', {
  init: () => ipcRenderer.invoke('init'),
  act: (name, ...args) => ipcRenderer.invoke('action', name, ...args),
  onState: fn => ipcRenderer.on('state', (_e, s) => fn(s)),
  onNavigate: fn => ipcRenderer.on('navigate', (_e, s) => fn(s)),
});
