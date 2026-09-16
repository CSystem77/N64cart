const { contextBridge, ipcRenderer, webUtils } = require('electron');

const listen = (channel) => (callback) => {
  const handler = (_event, payload) => callback(payload);
  ipcRenderer.on(channel, handler);
  return () => ipcRenderer.removeListener(channel, handler);
};

contextBridge.exposeInMainWorld('cart', {
  setLanguage: (language) => ipcRenderer.invoke('app:setLanguage', language),
  state: () => ipcRenderer.invoke('cart:state'),
  connect: () => ipcRenderer.invoke('cart:connect'),
  disconnect: () => ipcRenderer.invoke('cart:disconnect'),
  list: (path) => ipcRenderer.invoke('cart:list', path),
  mkdir: (path, name) => ipcRenderer.invoke('cart:mkdir', path, name),
  remove: (entry) => ipcRenderer.invoke('cart:delete', entry),
  rename: (entry, newName) => ipcRenderer.invoke('cart:rename', entry, newName),
  format: () => ipcRenderer.invoke('cart:format'),
  reboot: () => ipcRenderer.invoke('cart:reboot'),
  flashFirmware: () => ipcRenderer.invoke('cart:flashFirmware'),
  installManager: () => ipcRenderer.invoke('cart:installManager'),
  upload: (files, targetDir, options) => ipcRenderer.invoke('cart:upload', files, targetDir, options),
  download: (entry) => ipcRenderer.invoke('cart:download', entry),
  pickRoms: () => ipcRenderer.invoke('dialog:pickRoms'),
  confirm: (options) => ipcRenderer.invoke('dialog:confirm', options),
  pathForFile: (file) => webUtils.getPathForFile(file),
  onState: listen('cart:state'),
  onBusy: listen('cart:busy'),
  onProgress: listen('cart:progress')
});
