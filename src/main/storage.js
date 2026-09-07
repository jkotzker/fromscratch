import fs from 'node:fs';
import path from 'node:path';

// Content used to be written synchronously on every keystroke. It is debounced now, with an
// explicit flush before the app quits so nothing is ever lost. Settings work the same way.
const WRITE_DEBOUNCE = 250;

const SETTINGS_FILE = 'settings.json';
const SETTINGS_VERSION = 1;

// Settings used to live in node-localstorage's JSONStorage, which writes one file per key, named
// after the (URL-encoded) key and containing JSON.stringify(value). Those files are read once to
// build settings.json and then left alone -- deleting them would make a downgrade lose data.
const LEGACY_KEYS = ['windowstate', 'folds2', 'fontSize', 'lightTheme', 'hideUpdateMessage'];

// The rem base the old multiplier was applied against, used to turn it into an absolute size.
const REM_BASE_PX = 16;

export const DEFAULT_FONT = { family: null, size: REM_BASE_PX };
export const DEFAULT_SCHEME = 'built-in:dark';
export const DEFAULT_HIGHLIGHT_LINE = true;

let dir = null;
let contentFile = null;
let settingsFile = null;
let data = {};

let pendingContent = null;
let contentTimer = null;
let settingsTimer = null;

const readJson = file => {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return undefined;
  }
};

/** Build a settings.json document from the per-key files node-localstorage left behind. */
function migrateLegacy(location) {
  const migrated = { version: SETTINGS_VERSION };
  let found = 0;

  for (const key of LEGACY_KEYS) {
    const value = readJson(path.join(location, key));
    if (value === undefined) continue;
    found += 1;

    if (key === 'fontSize') {
      // Was a 0.5-2.5 rem multiplier; it becomes an absolute pixel size.
      migrated.font = { ...DEFAULT_FONT, size: Math.round(value * REM_BASE_PX) };
    } else if (key === 'lightTheme') {
      migrated.colorScheme = value ? 'built-in:light' : 'built-in:dark';
    } else {
      migrated[key] = value;
    }
  }

  if (found) console.log(`Migrated ${found} setting(s) into ${SETTINGS_FILE}`);
  return migrated;
}

export function initStorage(location) {
  fs.mkdirSync(location, { recursive: true });
  dir = location;
  contentFile = path.join(location, 'content.txt');
  settingsFile = path.join(location, SETTINGS_FILE);

  const existing = readJson(settingsFile);

  if (existing && typeof existing === 'object') {
    data = existing;
    return;
  }

  // Unparseable but present means something went wrong; keep it rather than overwriting it, so
  // whatever it held can still be recovered by hand.
  if (fs.existsSync(settingsFile)) {
    const backup = `${settingsFile}.corrupt`;
    try {
      fs.renameSync(settingsFile, backup);
      console.error(`Could not parse ${SETTINGS_FILE}; kept it as ${path.basename(backup)}`);
    } catch (error) {
      console.error('Could not preserve the unreadable settings file:', error);
    }
  }

  data = migrateLegacy(location);
  writeSettings();
}

function writeSettings() {
  try {
    fs.writeFileSync(settingsFile, JSON.stringify({ version: SETTINGS_VERSION, ...data }, null, 2), 'utf8');
  } catch (error) {
    console.error('Could not write settings:', error);
  }
}

export function flushSettings() {
  if (!settingsTimer) return;
  clearTimeout(settingsTimer);
  settingsTimer = null;
  writeSettings();
}

export const settings = {
  get(key, fallback = null) {
    const value = data[key];
    return value === null || value === undefined ? fallback : value;
  },
  set(key, value) {
    data[key] = value;
    if (settingsTimer) return;
    settingsTimer = setTimeout(() => {
      settingsTimer = null;
      writeSettings();
    }, WRITE_DEBOUNCE);
  },
  /** The whole document, for handing to the renderer in one go. */
  all() {
    return { ...data };
  },
  get directory() {
    return dir;
  },
};

export function readContent() {
  try {
    return fs.existsSync(contentFile) ? fs.readFileSync(contentFile, 'utf8') : null;
  } catch (error) {
    console.error('Could not read content:', error);
    return null;
  }
}

export function writeContent(content) {
  pendingContent = content;
  if (contentTimer) return;

  contentTimer = setTimeout(() => {
    contentTimer = null;
    flushContent();
  }, WRITE_DEBOUNCE);
}

export function flushContent() {
  if (pendingContent === null) return;

  const content = pendingContent;
  pendingContent = null;

  try {
    fs.writeFileSync(contentFile, content, 'utf8');
  } catch (error) {
    console.error('Could not write content:', error);
  }
}
