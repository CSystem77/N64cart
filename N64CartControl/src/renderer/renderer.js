const ROMFS_TYPE = { FIRMWARE: 0, FLASHLIST: 1, FLASHMAP: 2, DIR: 3, MISC: 0x1f };
const ROMFS_MODE_READONLY = 1;
const ROMFS_MODE_SYSTEM = 2;

const ui = {
  statusLabel: document.getElementById('statusLabel'),
  deviceInfo: document.getElementById('deviceInfo'),
  langSelect: document.getElementById('langSelect'),
  btnTheme: document.getElementById('btnTheme'),
  themePanel: document.getElementById('themePanel'),
  themeChoices: document.getElementById('themeChoices'),
  colorSwatches: document.getElementById('colorSwatches'),
  btnConnect: document.getElementById('btnConnect'),
  btnDisconnect: document.getElementById('btnDisconnect'),
  btnUp: document.getElementById('btnUp'),
  btnRefresh: document.getElementById('btnRefresh'),
  btnAdd: document.getElementById('btnAdd'),
  btnMkdir: document.getElementById('btnMkdir'),
  btnSystem: document.getElementById('btnSystem'),
  btnDownload: document.getElementById('btnDownload'),
  btnRename: document.getElementById('btnRename'),
  btnDelete: document.getElementById('btnDelete'),
  btnReboot: document.getElementById('btnReboot'),
  btnFirmware: document.getElementById('btnFirmware'),
  btnFormat: document.getElementById('btnFormat'),
  breadcrumb: document.getElementById('breadcrumb'),
  optFixRom: document.getElementById('optFixRom'),
  dropzone: document.getElementById('dropzone'),
  entries: document.getElementById('entries'),
  emptyMessage: document.getElementById('emptyMessage'),
  managerNotice: document.getElementById('managerNotice'),
  btnInstallManager: document.getElementById('btnInstallManager'),
  freeSpace: document.getElementById('freeSpace'),
  statusMessage: document.getElementById('statusMessage'),
  overlay: document.getElementById('overlay'),
  overlayLabel: document.getElementById('overlayLabel'),
  progressBar: document.getElementById('progressBar'),
  progressText: document.getElementById('progressText'),
  prompt: document.getElementById('prompt'),
  promptForm: document.getElementById('promptForm'),
  promptLabel: document.getElementById('promptLabel'),
  devByCsystem: document.getElementById('devByCsystem'),
  promptInput: document.getElementById('promptInput'),
  promptCancel: document.getElementById('promptCancel')
};

let connected = false;
let busy = false;
let currentPath = '/';
let entries = [];
let selectedPath = null;
let showSystem = false;
let freeBytes = 0;
let deviceInfo = null;

const MANAGER_NAME = 'n64cart-manager.z64';

const THEMES = ['threatrix', 'cyber'];
const ACCENTS = {
  blue: '#67ceff',
  cyan: '#6aebef',
  teal: '#64ffda',
  green: '#82ff9b',
  lime: '#d4ff92',
  yellow: '#ebef6a',
  orange: '#ffbf89',
  red: '#ff9999',
  pink: '#ff96cd',
  purple: '#e89dff',
  indigo: '#a59ffd'
};

let theme = 'threatrix';
let accent = 'cyan';
try {
  const storedTheme = localStorage.getItem('theme');
  const storedAccent = localStorage.getItem('accent');
  if (THEMES.includes(storedTheme)) {
    theme = storedTheme;
  }
  if (storedAccent && ACCENTS[storedAccent]) {
    accent = storedAccent;
  }
} catch {}

let language = 'fr';
try {
  const stored = localStorage.getItem('language');
  if (stored && TRANSLATIONS[stored]) {
    language = stored;
  }
} catch {}

const t = (key, vars) => translate(language, key, vars);

function applyStaticTranslations() {
  document.documentElement.lang = language;
  for (const node of document.querySelectorAll('[data-i18n]')) {
    node.textContent = t(node.dataset.i18n);
  }
  for (const node of document.querySelectorAll('[data-i18n-title]')) {
    node.title = t(node.dataset.i18nTitle);
  }
}

async function setLanguage(next) {
  language = TRANSLATIONS[next] ? next : 'fr';
  try {
    localStorage.setItem('language', language);
  } catch {}
  ui.langSelect.value = language;

  applyStaticTranslations();

  await window.cart.setLanguage(language);

  renderDeviceState();
  renderThemePanel();
  renderBreadcrumb();
  renderEntries();
  renderStatus();
  setStatus('');
  updateControls();
}

function applyTheme() {
  document.documentElement.dataset.theme = theme;
  document.documentElement.dataset.accent = accent;
  try {
    localStorage.setItem('theme', theme);
    localStorage.setItem('accent', accent);
  } catch {}
  renderThemePanel();
}

function renderThemePanel() {
  ui.themeChoices.innerHTML = '';
  for (const name of THEMES) {
    const button = document.createElement('button');
    button.textContent = t(`theme.${name}`);
    button.classList.toggle('active', name === theme);
    button.addEventListener('click', () => {
      theme = name;
      applyTheme();
    });
    ui.themeChoices.append(button);
  }

  ui.colorSwatches.innerHTML = '';
  for (const [name, value] of Object.entries(ACCENTS)) {
    const swatch = document.createElement('button');
    swatch.style.setProperty('--swatch', value);
    swatch.title = t(`color.${name}`);
    swatch.setAttribute('aria-label', swatch.title);
    swatch.classList.toggle('active', name === accent);
    swatch.addEventListener('click', () => {
      accent = name;
      applyTheme();
    });
    ui.colorSwatches.append(swatch);
  }
}

function formatSize(bytes) {
  if (bytes < 1024) {
    return `${bytes} ${t('unit.b')}`;
  }
  const units = [t('unit.kb'), t('unit.mb'), t('unit.gb')];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toFixed(value < 10 ? 2 : 1)} ${units[unit]}`;
}

function isRom(name) {
  return /\.(z64|n64|v64)$/i.test(name);
}

function typeLabel(entry) {
  if (entry.isDirectory) {
    return t('type.folder');
  }
  switch (entry.type) {
    case ROMFS_TYPE.FIRMWARE:
      return t('type.firmware');
    case ROMFS_TYPE.FLASHLIST:
    case ROMFS_TYPE.FLASHMAP:
      return t('type.system');
    default:
      return isRom(entry.name) ? t('type.rom') : t('type.file');
  }
}

function isProtected(entry) {
  return (entry.mode & (ROMFS_MODE_READONLY | ROMFS_MODE_SYSTEM)) !== 0 || entry.type < ROMFS_TYPE.DIR;
}

function isSystemEntry(entry) {
  return entry.type < ROMFS_TYPE.DIR || (entry.mode & ROMFS_MODE_SYSTEM) !== 0;
}

function visibleEntries() {
  return showSystem ? [...entries] : entries.filter((entry) => !isSystemEntry(entry));
}

function selected() {
  return entries.find((entry) => entry.path === selectedPath) || null;
}

function setStatus(message, kind = '') {
  ui.statusMessage.textContent = message || '';
  ui.statusMessage.className = `status-message ${kind}`;
}

function updateControls() {
  const entry = selected();
  const canAct = connected && !busy;
  ui.btnConnect.hidden = connected;
  ui.btnDisconnect.hidden = !connected;
  ui.btnConnect.disabled = busy;
  ui.btnDisconnect.disabled = busy;
  ui.langSelect.disabled = busy;

  const cartButtons = [
    ui.btnRefresh,
    ui.btnAdd,
    ui.btnMkdir,
    ui.btnSystem,
    ui.btnFormat,
    ui.btnReboot,
    ui.btnFirmware
  ];
  for (const button of cartButtons) {
    button.disabled = !canAct;
  }
  ui.btnInstallManager.disabled = !canAct;
  ui.btnUp.disabled = !canAct || currentPath === '/';
  ui.btnDownload.disabled = !canAct || !entry || entry.isDirectory;
  ui.btnRename.disabled = !canAct || !entry || isProtected(entry);
  ui.btnDelete.disabled = !canAct || !entry || isProtected(entry);
}

function renderBreadcrumb() {
  ui.breadcrumb.innerHTML = '';
  const parts = currentPath === '/' ? [] : currentPath.slice(1).split('/');

  const root = document.createElement('button');
  root.textContent = t('path.root');
  root.addEventListener('click', () => navigate('/'));
  ui.breadcrumb.append(root);

  let acc = '';
  parts.forEach((part) => {
    acc += `/${part}`;
    const separator = document.createElement('span');
    separator.textContent = '/';
    const crumb = document.createElement('button');
    crumb.textContent = part;
    const target = acc;
    crumb.addEventListener('click', () => navigate(target));
    ui.breadcrumb.append(separator, crumb);
  });
}

function renderEntries() {
  ui.entries.innerHTML = '';
  const sorted = visibleEntries().sort((a, b) => {
    if (a.isDirectory !== b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.name.localeCompare(b.name, language, { numeric: true });
  });

  for (const entry of sorted) {
    const row = document.createElement('tr');
    row.classList.toggle('selected', entry.path === selectedPath);

    const name = document.createElement('td');
    const icon = document.createElement('span');
    icon.className = 'icon';
    icon.textContent = entry.isDirectory ? '📁' : isRom(entry.name) ? '🎮' : '📄';
    name.append(icon, document.createTextNode(entry.name));
    if (entry.mode & ROMFS_MODE_READONLY) {
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = t('badge.readonly');
      name.append(badge);
    }

    const type = document.createElement('td');
    type.textContent = typeLabel(entry);

    const size = document.createElement('td');
    size.textContent = entry.isDirectory ? '—' : formatSize(entry.size);

    row.append(name, type, size);
    row.addEventListener('click', () => {
      selectedPath = entry.path;
      renderEntries();
      updateControls();
    });
    row.addEventListener('dblclick', () => {
      if (entry.isDirectory) {
        navigate(entry.path);
      }
    });
    ui.entries.append(row);
  }

  renderEmptyMessage(sorted.length);
}

function renderEmptyMessage(count = visibleEntries().length) {
  ui.emptyMessage.textContent = connected ? t('list.empty') : t('list.connectFirst');
  ui.emptyMessage.hidden = connected && count > 0;
}

function renderStatus() {
  if (!connected) {
    ui.freeSpace.textContent = '';
    return;
  }
  const shown = visibleEntries().length;
  const hidden = entries.length - shown;
  ui.freeSpace.textContent =
    t('statusbar.free', { size: formatSize(freeBytes), count: shown }) +
    (hidden > 0 ? t('statusbar.hidden', { count: hidden }) : '');
}

function renderManagerNotice() {
  const atRoot = currentPath === '/';
  const present = entries.some((entry) => entry.name.toLowerCase() === MANAGER_NAME);
  ui.managerNotice.hidden = !connected || !atRoot || present;
}

function renderDeviceState() {
  if (connected && deviceInfo) {
    ui.statusLabel.textContent = t('status.connected');
    ui.deviceInfo.textContent = t('status.device', {
      version: deviceInfo.firmwareVersion,
      size: formatSize(deviceInfo.romfsSize),
      offset: deviceInfo.romfsStart.toString(16).toUpperCase()
    });
  } else {
    ui.statusLabel.textContent = t('status.disconnected');
    ui.deviceInfo.textContent = t('status.hint');
  }
  renderEmptyMessage();
}

function askName(label, initial = '') {
  return new Promise((resolve) => {
    ui.promptLabel.textContent = label;
    ui.promptInput.value = initial;
    ui.prompt.hidden = false;
    ui.promptInput.focus();
    ui.promptInput.select();

    const close = (value) => {
      ui.prompt.hidden = true;
      ui.promptForm.onsubmit = null;
      ui.promptCancel.onclick = null;
      resolve(value);
    };

    ui.promptForm.onsubmit = (event) => {
      event.preventDefault();
      close(ui.promptInput.value.trim() || null);
    };
    ui.promptCancel.onclick = () => close(null);
  });
}

async function run(description, action) {
  try {
    const result = await action();
    if (description) {
      setStatus(description, 'ok');
    }
    return result;
  } catch (error) {
    setStatus(error.message.replace(/^Error: /, ''), 'error');
    return undefined;
  }
}

async function refresh() {
  if (!connected) {
    entries = [];
    renderEntries();
    ui.freeSpace.textContent = '';
    return;
  }

  const listing = await run(null, () => window.cart.list(currentPath));
  if (!listing) {
    return;
  }
  entries = listing.entries;
  if (!entries.some((entry) => entry.path === selectedPath)) {
    selectedPath = null;
  }
  freeBytes = listing.freeBytes;
  renderManagerNotice();
  renderBreadcrumb();
  renderEntries();
  renderStatus();
  updateControls();
}

async function navigate(path) {
  currentPath = path || '/';
  selectedPath = null;
  await refresh();
}

function applyState(state) {
  connected = state.connected;
  deviceInfo = state.info;
  if (!connected) {
    ui.managerNotice.hidden = true;
  }
  renderDeviceState();
  updateControls();
}

async function uploadFiles(paths) {
  if (!paths.length) {
    return;
  }
  const options = { fixRom: ui.optFixRom.checked };
  await run(t('msg.uploaded', { count: paths.length }), () => window.cart.upload(paths, currentPath, options));
  await refresh();
}

ui.btnTheme.addEventListener('click', (event) => {
  event.stopPropagation();
  const open = ui.themePanel.hidden;
  ui.themePanel.hidden = !open;
  ui.btnTheme.setAttribute('aria-expanded', String(open));
  ui.btnTheme.classList.toggle('active', open);
});

document.addEventListener('click', (event) => {
  if (!ui.themePanel.hidden && !ui.themePanel.contains(event.target)) {
    ui.themePanel.hidden = true;
    ui.btnTheme.setAttribute('aria-expanded', 'false');
    ui.btnTheme.classList.remove('active');
  }
});

ui.langSelect.addEventListener('change', () => setLanguage(ui.langSelect.value));

ui.btnConnect.addEventListener('click', async () => {
  const info = await run(t('msg.connected'), () => window.cart.connect());
  if (info) {

    applyState(await window.cart.state());
    await navigate('/');
  }
});

ui.btnDisconnect.addEventListener('click', async () => {
  await run(t('msg.disconnected'), () => window.cart.disconnect());
  entries = [];
  currentPath = '/';
  selectedPath = null;
  renderBreadcrumb();
  renderEntries();
  ui.freeSpace.textContent = '';
});

ui.btnRefresh.addEventListener('click', () => refresh());

ui.btnInstallManager.addEventListener('click', async () => {
  const installed = await run(null, () => window.cart.installManager());
  if (installed) {
    setStatus(t('manager.installed'), 'ok');
    await refresh();
  }
});

ui.btnSystem.addEventListener('click', () => {
  showSystem = !showSystem;
  ui.btnSystem.setAttribute('aria-pressed', String(showSystem));
  ui.btnSystem.classList.toggle('active', showSystem);
  if (selectedPath && !visibleEntries().some((entry) => entry.path === selectedPath)) {
    selectedPath = null;
  }
  renderEntries();
  renderStatus();
  updateControls();
});

ui.btnUp.addEventListener('click', () => {
  const parent = currentPath.slice(0, currentPath.lastIndexOf('/')) || '/';
  navigate(parent);
});

ui.btnAdd.addEventListener('click', async () => {
  const paths = await window.cart.pickRoms();
  await uploadFiles(paths);
});

ui.btnMkdir.addEventListener('click', async () => {
  const name = await askName(t('prompt.newFolder'));
  if (!name) {
    return;
  }
  await run(t('msg.folderCreated', { name }), () => window.cart.mkdir(currentPath, name));
  await refresh();
});

ui.btnDownload.addEventListener('click', async () => {
  const entry = selected();
  if (!entry) {
    return;
  }
  const saved = await run(null, () => window.cart.download(entry));
  if (saved) {
    setStatus(t('msg.saved', { path: saved }), 'ok');
  }
});

ui.btnRename.addEventListener('click', async () => {
  const entry = selected();
  if (!entry) {
    return;
  }
  const name = await askName(t('prompt.newName'), entry.name);
  if (!name || name === entry.name) {
    return;
  }
  await run(t('msg.renamed', { name }), () => window.cart.rename(entry, name));
  await refresh();
});

ui.btnDelete.addEventListener('click', async () => {
  const entry = selected();
  if (!entry) {
    return;
  }
  const ok = await window.cart.confirm({
    title: t('confirm.deleteTitle'),
    message: t('confirm.deleteMessage', { name: entry.name }),
    detail: entry.isDirectory ? t('confirm.deleteDirDetail') : t('confirm.deleteFileDetail'),
    confirmLabel: t('btn.delete')
  });
  if (!ok) {
    return;
  }
  await run(t('msg.deleted', { name: entry.name }), () => window.cart.remove(entry));
  await refresh();
});

ui.btnFormat.addEventListener('click', async () => {
  const ok = await window.cart.confirm({
    title: t('confirm.formatTitle'),
    message: t('confirm.formatMessage'),
    detail: t('confirm.formatDetail'),
    confirmLabel: t('btn.format')
  });
  if (!ok) {
    return;
  }
  await run(t('msg.formatted'), () => window.cart.format());
  await navigate('/');
});

ui.btnReboot.addEventListener('click', async () => {
  await run(t('msg.rebooted'), () => window.cart.reboot());
  entries = [];
  renderEntries();
});

ui.btnFirmware.addEventListener('click', async () => {
  const result = await run(null, () => window.cart.flashFirmware());
  if (!result) {
    return;
  }

  setStatus(
    result.reconnected
      ? t('msg.firmwareOk', { name: result.name })
      : t('msg.firmwareManual', { name: result.name }),
    'ok'
  );

  applyState(await window.cart.state());
  if (result.reconnected) {
    await navigate('/');
  } else {
    entries = [];
    renderEntries();
  }
});

ui.dropzone.addEventListener('dragover', (event) => {
  event.preventDefault();
  if (connected && !busy) {
    ui.dropzone.classList.add('dragover');
  }
});

ui.dropzone.addEventListener('dragleave', (event) => {
  if (event.target === ui.dropzone) {
    ui.dropzone.classList.remove('dragover');
  }
});

ui.dropzone.addEventListener('drop', async (event) => {
  event.preventDefault();
  ui.dropzone.classList.remove('dragover');
  if (!connected || busy) {
    return;
  }
  const paths = [...event.dataTransfer.files].map((file) => window.cart.pathForFile(file)).filter(Boolean);
  await uploadFiles(paths);
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !ui.prompt.hidden) {
    ui.promptCancel.click();
  }
  if (event.key === 'Escape' && !ui.themePanel.hidden) {
    ui.themePanel.hidden = true;
    ui.btnTheme.setAttribute('aria-expanded', 'false');
    ui.btnTheme.classList.remove('active');
  }
  if (event.key === 'F5') {
    event.preventDefault();
    if (connected && !busy) {
      refresh();
    }
  }
});

window.cart.onState(applyState);

window.cart.onBusy(({ busy: isBusy, label }) => {
  busy = isBusy;
  ui.overlayLabel.textContent = `${label || t('overlay.working')}…`;
  ui.overlay.hidden = !isBusy;
  if (!isBusy) {
    ui.progressBar.style.width = '0';
    ui.progressText.textContent = '';
  }
  updateControls();
});

window.cart.onProgress((progress) => {
  if (!progress) {
    ui.progressBar.style.width = '0';
    ui.progressText.textContent = '';
    return;
  }
  ui.overlayLabel.textContent = `${progress.label}…`;
  if (progress.total <= 0) {

    ui.progressBar.style.width = '0';
    ui.progressText.textContent = '';
    return;
  }
  const ratio = Math.min(1, progress.processed / progress.total);
  ui.progressBar.style.width = `${(ratio * 100).toFixed(1)}%`;
  ui.progressText.textContent = `${formatSize(progress.processed)} / ${formatSize(progress.total)} (${(
    ratio * 100
  ).toFixed(0)} %)`;
});

applyTheme();
setLanguage(language).then(() => window.cart.state().then(applyState));
