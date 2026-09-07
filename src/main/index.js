import path from 'node:path';
import { app, BrowserWindow, ipcMain, Menu, nativeTheme, screen, shell } from 'electron';
import minimist from 'minimist';
import { buildMenu } from './menu';
import { BUILT_IN_SCHEMES, derivePalette, isDark } from './palette';
import {
  DEFAULT_HIGHLIGHT_LINE,
  DEFAULT_SCHEME,
  flushContent,
  flushSettings,
  initStorage,
  readContent,
  settings,
  writeContent,
} from './storage';
import { discoverSchemes, THEMES_DIRNAME } from './themes';
import { getNewerVersion } from './updates';

const APP_NAME = 'FromScratch';

app.setName(APP_NAME);

const isDev = !app.isPackaged;
let mainWindow = null;

const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  app.quit();
} else {
  const argv = minimist(process.argv.slice(app.isPackaged ? 1 : 2), {
    boolean: ['help'],
    string: ['portable'],
    alias: { help: 'h' },
  });

  if (argv.help) {
    console.log(`Usage: fromscratch [OPTION]...

Optional arguments:
  --portable [DIRECTORY] run in portable mode, saving data in executable directory, or in alternate path
  -h, --help                 show this usage text.
  `);

    process.exit(0);
  }

  const getDataLocation = () => {
    if (typeof argv.portable !== 'undefined') {
      const location = argv.portable !== '' ? argv.portable : path.join(process.cwd(), 'userdata');
      app.setPath('userData', location);
      return location;
    }

    const home = process.env[process.platform === 'win32' ? 'USERPROFILE' : 'HOME'];
    return path.join(home, '.fromscratch', isDev ? 'dev' : '');
  };

  initStorage(getDataLocation());

  const dispatch = shortcut => {
    if (mainWindow) mainWindow.webContents.send('shortcut', shortcut);
  };

  const toggleFullscreen = () => {
    if (mainWindow) mainWindow.setFullScreen(!mainWindow.isFullScreen());
  };

  // Schemes loaded from ~/.fromscratch/themes. Rescanned on demand rather than watched, so a
  // half-written file being copied in cannot be picked up mid-copy.
  let discovered = [];
  const rescanSchemes = () => {
    discovered = discoverSchemes(settings.directory);
    return discovered;
  };

  const allSchemes = () => [...BUILT_IN_SCHEMES, ...discovered];

  const describe = ({ id, name, background }) => ({ id, name, dark: isDark(background) });

  // A scheme is stored as an id; everything the renderer needs is derived from its two colours.
  // An id that no longer resolves -- a theme file deleted since it was chosen -- falls back to
  // the first built-in rather than leaving the window unstyled.
  const resolveScheme = id => {
    const scheme = allSchemes().find(s => s.id === id) || BUILT_IN_SCHEMES[0];
    return { ...describe(scheme), palette: derivePalette(scheme) };
  };

  // The macOS vibrancy material follows nativeTheme, so a light scheme has to say so or the
  // window keeps a dark backdrop behind a light palette.
  const applyScheme = scheme => {
    nativeTheme.themeSource = scheme.dark ? 'dark' : 'light';
  };

  const rebuildMenu = () => {
    Menu.setApplicationMenu(
      buildMenu({
        appName: APP_NAME,
        version: app.getVersion(),
        platform: process.platform,
        dispatch,
        toggleFullscreen,
        quit: () => app.quit(),
        schemes: allSchemes().map(describe),
        // The resolved id, not the stored one: if a theme file has been deleted since it was
        // chosen, the window falls back to the first built-in, and the checkmark has to follow
        // it rather than pointing at a scheme that no longer exists.
        activeSchemeId: resolveScheme(settings.get('colorScheme', DEFAULT_SCHEME)).id,
        selectScheme: id => selectScheme(id),
        reloadSchemes: () => {
          rescanSchemes();
          rebuildMenu();
          if (mainWindow) mainWindow.webContents.send('schemes-changed', allSchemes().map(describe));
        },
        openThemesFolder: () => shell.openPath(path.join(settings.directory, THEMES_DIRNAME)),
        highlightLine: settings.get('highlightCurrentLine', DEFAULT_HIGHLIGHT_LINE),
        setHighlightLine: value => setHighlightLine(value),
      })
    );
  };

  const selectScheme = id => {
    const scheme = resolveScheme(id);
    settings.set('colorScheme', scheme.id);
    applyScheme(scheme);
    rebuildMenu();
    if (mainWindow) mainWindow.webContents.send('scheme-changed', scheme);
    return scheme;
  };

  // Pushed to the renderer rather than dispatched as a shortcut: the menu owns the checkmark, so
  // the value has to live here and the window has to be told what it became.
  const setHighlightLine = value => {
    settings.set('highlightCurrentLine', value);
    rebuildMenu();
    if (mainWindow) mainWindow.webContents.send('setting-changed', 'highlightCurrentLine', value);
  };

  const checkForUpdates = async () => {
    const newer = await getNewerVersion(app.getVersion());
    if (!newer || !mainWindow) return;

    const hidden = settings.get('hideUpdateMessage');
    if (hidden && hidden.version === newer) return;

    mainWindow.webContents.send('update-available', newer);
  };

  // Stored bounds can point at a display that is no longer connected, which would open the
  // window somewhere invisible.
  const isOnAConnectedDisplay = bounds =>
    screen.getAllDisplays().some(({ workArea }) => {
      return (
        bounds.x < workArea.x + workArea.width &&
        bounds.x + bounds.width > workArea.x &&
        bounds.y < workArea.y + workArea.height &&
        bounds.y + bounds.height > workArea.y
      );
    });

  const createWindow = () => {
    const windowState = settings.get('windowstate', {}) || {};
    const stored = windowState.bounds || {};
    const hasBounds = ['x', 'y', 'width', 'height'].every(key => Number.isFinite(stored[key]));
    const bounds = hasBounds && isOnAConnectedDisplay(stored) ? stored : {};
    applyScheme(resolveScheme(settings.get('colorScheme', DEFAULT_SCHEME)));

    const windowSettings = {
      show: false,
      title: APP_NAME,
      x: bounds.x,
      y: bounds.y,
      width: bounds.width || 550,
      height: bounds.height || 450,
      minWidth: 300,
      minHeight: 200,
      autoHideMenuBar: true,
      backgroundColor: process.platform === 'darwin' ? '#00000000' : '#002b36',
      webPreferences: {
        preload: path.join(__dirname, '../preload/index.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    };

    if (process.platform === 'darwin') {
      // 'medium-light'/'ultra-dark' were removed in Electron 27. 'under-window' is the modern
      // material; it follows nativeTheme, so the theme toggle drives the vibrancy too.
      Object.assign(windowSettings, {
        vibrancy: 'under-window',
        visualEffectState: 'active',
        titleBarStyle: 'hidden',
        trafficLightPosition: { x: 12, y: 10 },
      });
    }

    mainWindow = new BrowserWindow(windowSettings);

    if (isDev && process.env.ELECTRON_RENDERER_URL) {
      mainWindow.loadURL(process.env.ELECTRON_RENDERER_URL);
    } else {
      mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
    }

    mainWindow.webContents.setVisualZoomLevelLimits(1, 1);

    mainWindow.once('ready-to-show', () => {
      mainWindow.show();
      if (windowState.isMaximized) mainWindow.maximize();
      mainWindow.focus();
      checkForUpdates();
    });

    // Esc leaves fullscreen. Not preventing default, so CodeMirror still sees the key and can
    // close its search panel.
    mainWindow.webContents.on('before-input-event', (_event, input) => {
      if (input.type === 'keyDown' && input.key === 'Escape' && mainWindow.isFullScreen()) {
        mainWindow.setFullScreen(false);
      }
    });

    const storeWindowState = () => {
      if (!mainWindow) return;
      windowState.isMaximized = mainWindow.isMaximized();
      if (!windowState.isMaximized) {
        windowState.bounds = mainWindow.getBounds();
      }
      settings.set('windowstate', windowState);
    };

    ['resize', 'move', 'close'].forEach(event => mainWindow.on(event, storeWindowState));

    mainWindow.on('closed', () => {
      mainWindow = null;
    });

    if (isDev) {
      mainWindow.webContents.openDevTools({ mode: 'detach' });
      // Surface renderer logs in the terminal that runs `npm run dev`.
      mainWindow.webContents.on('console-message', event => {
        console.log(`[renderer:${event.level}] ${event.message}`);
      });
    }
  };

  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });

  app.on('window-all-closed', () => {
    app.quit();
  });

  app.on('before-quit', () => {
    flushContent();
    flushSettings();
  });

  app.whenReady().then(() => {
    ipcMain.handle('app:init', () => ({
      platform: process.platform,
      version: app.getVersion(),
      content: readContent(),
      settings: {
        font: settings.get('font', { family: null, size: 16 }),
        folds: settings.get('folds2', []),
        highlightLine: settings.get('highlightCurrentLine', DEFAULT_HIGHLIGHT_LINE),
      },
      scheme: resolveScheme(settings.get('colorScheme', DEFAULT_SCHEME)),
      schemes: allSchemes().map(describe),
    }));

    ipcMain.on('content:write', (_event, content) => writeContent(content));

    ipcMain.on('settings:set', (_event, key, value) => settings.set(key, value));

    ipcMain.handle('scheme:set', (_event, id) => selectScheme(id));

    ipcMain.on('update:dismiss', (_event, version) => {
      settings.set('hideUpdateMessage', { version });
    });

    ipcMain.on('shell:open-external', (_event, url) => {
      if (/^https:\/\//.test(url)) shell.openExternal(url);
    });

    rescanSchemes();
    rebuildMenu();
    createWindow();
  });
}
