import fs from 'node:fs';
import path from 'node:path';
import { JSONStorage } from 'node-localstorage';

// Content used to be written synchronously on every keystroke. It is debounced now, with an
// explicit flush before the app quits so nothing is ever lost.
const WRITE_DEBOUNCE = 250;

let storage = null;
let contentFile = null;
let pendingContent = null;
let writeTimer = null;

export function initStorage(location) {
  fs.mkdirSync(location, { recursive: true });
  storage = new JSONStorage(location);
  contentFile = path.join(location, 'content.txt');
}

export const settings = {
  get(key, fallback = null) {
    try {
      const value = storage.getItem(key);
      return value === null || value === undefined ? fallback : value;
    } catch {
      // A corrupt or empty settings file should never keep the app from starting.
      return fallback;
    }
  },
  set(key, value) {
    try {
      storage.setItem(key, value);
    } catch (error) {
      console.error(`Could not store setting "${key}":`, error);
    }
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
  if (writeTimer) return;

  writeTimer = setTimeout(() => {
    writeTimer = null;
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
