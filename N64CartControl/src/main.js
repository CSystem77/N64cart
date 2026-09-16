const { app, BrowserWindow, Menu, dialog, ipcMain } = require('electron');
const fs = require('node:fs');
const path = require('node:path');

const native = require(path.join(__dirname, '..', 'build', 'Release', 'n64cart.node'));
const { translate } = require('./renderer/i18n.js');

let language = 'fr';
const tr = (key, vars) => translate(language, key, vars);

const MAX_NAME_LENGTH = 53;

let mainWindow = null;

let queue = Promise.resolve();

function enqueue(task) {
  const run = queue.then(task, task);
  queue = run.catch(() => {});
  return run;
}

function send(channel, payload) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, payload);
  }
}

function state() {
  return { connected: native.isConnected(), info: native.info() };
}

function sendState() {
  send('cart:state', state());
}

function progressReporter(label) {
  return (processed, total) => send('cart:progress', { label, processed, total });
}

function operation(label, task) {
  return enqueue(async () => {
    send('cart:busy', { busy: true, label });
    try {
      return await task();
    } finally {
      send('cart:busy', { busy: false, label });
      send('cart:progress', null);
      sendState();
    }
  });
}

function validateName(name) {
  if (!name || name.includes('/') || name === '.' || name === '..') {
    throw new Error(tr('err.invalidName', { name }));
  }
  if (Buffer.byteLength(name, 'utf8') > MAX_NAME_LENGTH) {
    throw new Error(tr('err.nameTooLong', { max: MAX_NAME_LENGTH, name }));
  }
}

function joinRemote(dir, name) {
  return dir === '/' ? `/${name}` : `${dir}/${name}`;
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 720,
    minWidth: 820,
    minHeight: 520,
    title: 'N64 Cart Control',
    backgroundColor: '#13161c',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  Menu.setApplicationMenu(null);
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (native.isConnected()) {
    native.disconnect().catch(() => {});
  }
  app.quit();
});

ipcMain.handle('app:setLanguage', (_event, next) => {
  language = next === 'en' ? 'en' : 'fr';
});

ipcMain.handle('cart:state', () => state());

ipcMain.handle('cart:connect', () =>
  operation(tr('op.connect'), async () => {
    const info = await native.connect();
    return info;
  })
);

ipcMain.handle('cart:disconnect', () => operation(tr('op.disconnect'), () => native.disconnect()));

ipcMain.handle('cart:list', (_event, dirPath) => operation(tr('op.list'), () => native.list(dirPath || '/')));

ipcMain.handle('cart:mkdir', (_event, dirPath, name) =>
  operation(tr('op.mkdir'), () => {
    validateName(name);
    return native.mkdir(joinRemote(dirPath, name));
  })
);

ipcMain.handle('cart:delete', (_event, entry) =>
  operation(tr('op.delete'), () => (entry.isDirectory ? native.rmdir(entry.path) : native.unlink(entry.path)))
);

ipcMain.handle('cart:rename', (_event, entry, newName) =>
  operation(tr('op.rename'), () => {
    validateName(newName);
    const parent = entry.path.slice(0, entry.path.lastIndexOf('/')) || '/';
    return native.rename(entry.path, joinRemote(parent, newName), false);
  })
);

ipcMain.handle('cart:format', () => operation(tr('op.format'), () => native.format()));

ipcMain.handle('cart:reboot', () => operation(tr('op.reboot'), () => native.reboot()));

const MANAGER_NAME = 'n64cart-manager.z64';

function findManagerRom() {
  const appDir = app.getAppPath();
  const exeDir = path.dirname(app.getPath('exe'));
  const directories = [
    path.join(appDir, '..', 'Output', 'rom'),
    path.join(appDir, '..', '..', 'Output', 'rom'),
    path.join(exeDir, 'Output', 'rom'),
    path.join(exeDir, '..', 'Output', 'rom'),
    process.resourcesPath || exeDir
  ];

  for (const directory of directories) {
    const exact = path.join(directory, MANAGER_NAME);
    if (fs.existsSync(exact)) {
      return exact;
    }

    let names = [];
    try {
      names = fs.readdirSync(directory);
    } catch {
      continue;
    }
    const variant = names.find((name) => /^n64cart-manager.*\.z64$/i.test(name));
    if (variant) {
      return path.join(directory, variant);
    }
  }
  return null;
}

ipcMain.handle('cart:installManager', async () => {
  let file = findManagerRom();

  if (!file) {
    const pick = await dialog.showOpenDialog(mainWindow, {
      title: tr('dialog.managerTitle'),
      properties: ['openFile'],
      filters: [{ name: tr('dialog.romFilter'), extensions: ['z64', 'n64', 'v64'] }]
    });
    if (pick.canceled || pick.filePaths.length === 0) {
      return null;
    }
    file = pick.filePaths[0];
  }

  return operation(tr('op.installManager'), async () => {

    await native.upload(file, `/${MANAGER_NAME}`, { fixRom: true },
      progressReporter(tr('op.uploading', { name: MANAGER_NAME })));
    return { name: MANAGER_NAME, source: file, renamed: path.basename(file) !== MANAGER_NAME };
  });
});

const UF2_MAGIC = 0x0a324655;
const RP2040_MARKER = 'INFO_UF2.TXT';

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function volumeRoots() {
  if (process.platform === 'win32') {
    return Array.from({ length: 26 }, (_, i) => `${String.fromCharCode(65 + i)}:\\`);
  }

  const bases = process.platform === 'darwin' ? ['/Volumes'] : ['/media', '/run/media', '/mnt'];
  const roots = [];
  for (const base of bases) {
    let entries = [];
    try {
      entries = fs.readdirSync(base, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }
      const child = path.join(base, entry.name);
      roots.push(child);

      try {
        for (const sub of fs.readdirSync(child, { withFileTypes: true })) {
          if (sub.isDirectory()) {
            roots.push(path.join(child, sub.name));
          }
        }
      } catch {}
    }
  }
  return roots;
}

function findBootloaderDrive() {
  for (const root of volumeRoots()) {
    try {
      if (fs.existsSync(path.join(root, RP2040_MARKER))) {
        return root;
      }
    } catch {}
  }
  return null;
}

async function waitForBootloaderDrive(timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const drive = findBootloaderDrive();
    if (drive) {
      return drive;
    }
    await delay(500);
  }
  throw new Error(tr('err.noDrive'));
}

function assertUf2(file) {
  const header = Buffer.alloc(4);
  const handle = fs.openSync(file, 'r');
  try {
    fs.readSync(handle, header, 0, 4, 0);
  } finally {
    fs.closeSync(handle);
  }
  if (header.readUInt32LE(0) !== UF2_MAGIC) {
    throw new Error(tr('err.notUf2', { name: path.basename(file) }));
  }
}

ipcMain.handle('cart:flashFirmware', async () => {
  const pick = await dialog.showOpenDialog(mainWindow, {
    title: tr('dialog.firmwareTitle'),
    properties: ['openFile'],
    filters: [{ name: tr('dialog.firmwareFilter'), extensions: ['uf2'] }]
  });
  if (pick.canceled || pick.filePaths.length === 0) {
    return null;
  }
  const file = pick.filePaths[0];

  return operation(tr('op.firmware'), async () => {
    const step = (label) => send('cart:progress', { label, processed: 0, total: 0 });

    assertUf2(file);

    if (native.isConnected()) {
      step(tr('fw.bootloader'));
      await native.bootloader();
    }

    step(tr('fw.wait'));
    const drive = await waitForBootloaderDrive();

    step(tr('fw.copy', { name: path.basename(file) }));

    fs.copyFileSync(file, path.join(drive, path.basename(file)));

    step(tr('fw.reboot'));
    let reconnected = false;
    for (let attempt = 0; attempt < 20 && !reconnected; attempt++) {
      await delay(1000);
      try {
        await native.connect();
        reconnected = true;
      } catch {}
    }

    return { name: path.basename(file), drive, reconnected };
  });
});

ipcMain.handle('dialog:pickRoms', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: tr('dialog.pickRoms'),
    properties: ['openFile', 'multiSelections'],
    filters: [
      { name: tr('dialog.romFilter'), extensions: ['z64', 'n64', 'v64'] },
      { name: tr('dialog.allFilter'), extensions: ['*'] }
    ]
  });
  return result.canceled ? [] : result.filePaths;
});

ipcMain.handle('cart:upload', (_event, files, targetDir, options) =>
  operation(tr('op.upload'), async () => {
    const results = [];
    for (const file of files) {
      const name = path.basename(file);
      validateName(name);
      const remotePath = joinRemote(targetDir, name);
      await native.upload(file, remotePath, options || {}, progressReporter(tr('op.uploading', { name })));
      results.push(remotePath);
    }
    return results;
  })
);

ipcMain.handle('cart:download', async (_event, entry) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: tr('dialog.saveTitle'),
    defaultPath: entry.name,
    filters: [{ name: tr('dialog.romFilter'), extensions: ['z64'] }]
  });
  if (result.canceled || !result.filePath) {
    return null;
  }
  return operation(tr('op.download'), async () => {
    await native.download(entry.path, result.filePath, progressReporter(tr('op.downloading', { name: entry.name })));
    return result.filePath;
  });
});

ipcMain.handle('dialog:confirm', async (_event, { title, message, detail, confirmLabel }) => {
  const result = await dialog.showMessageBox(mainWindow, {
    type: 'warning',
    title,
    message,
    detail,
    buttons: [confirmLabel || tr('btn.validate'), tr('btn.cancel')],
    defaultId: 1,
    cancelId: 1
  });
  return result.response === 0;
});
