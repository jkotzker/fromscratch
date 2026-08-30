import fs from 'node:fs';
import path from 'node:path';

export const THEMES_DIRNAME = 'themes';

/**
 * Reads iTerm2 `.itermcolors` files, which are XML property lists holding one dict per colour:
 *
 *   <key>Background Color</key>
 *   <dict>
 *     <key>Blue Component</key><real>0.076218985021114349</real>
 *     ...
 *   </dict>
 *
 * Only the background and foreground are used. The app's whole palette derives from those two
 * (see palette.js), so the sixteen ANSI entries are read but currently ignored.
 *
 * Parsing is done with regular expressions rather than a plist library on purpose: the format is
 * this regular, and the alternative is a runtime dependency for one file type. Colour Space keys
 * appear as either "sRGB" or not at all; both are treated as sRGB, which is accurate enough for a
 * UI tint and avoids a colour-management dependency.
 */
const COLOR_BLOCK = /<key>([^<]+)<\/key>\s*<dict>([\s\S]*?)<\/dict>/g;
const COMPONENT = /<key>(\w+) Component<\/key>\s*<(?:real|integer)>([^<]+)<\/(?:real|integer)>/g;

const toHex = components => {
  const channel = name => {
    const value = Number(components[name]);
    if (!Number.isFinite(value)) return null;
    return Math.round(Math.min(1, Math.max(0, value)) * 255);
  };
  const rgb = ['Red', 'Green', 'Blue'].map(channel);
  if (rgb.some(c => c === null)) return null;
  return '#' + rgb.map(c => c.toString(16).padStart(2, '0')).join('');
};

/** @returns {{background: string, foreground: string} | null} */
export function parseItermColors(text) {
  const colors = {};

  for (const [, name, body] of text.matchAll(COLOR_BLOCK)) {
    const components = {};
    for (const [, channel, value] of body.matchAll(COMPONENT)) components[channel] = value;

    const hex = toHex(components);
    if (hex) colors[name] = hex;
  }

  const background = colors['Background Color'];
  const foreground = colors['Foreground Color'];
  if (!background || !foreground) return null;

  return { background, foreground };
}

/**
 * Finds every readable `.itermcolors` file in <dataDir>/themes.
 *
 * The directory is created when missing so there is somewhere obvious to drop files. A file that
 * cannot be read or lacks a background/foreground pair is skipped with a warning rather than
 * failing the scan -- one bad file should not hide the rest.
 */
export function discoverSchemes(dataDir) {
  const dir = path.join(dataDir, THEMES_DIRNAME);

  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch (error) {
    console.error('Could not create the themes directory:', error);
    return [];
  }

  let entries = [];
  try {
    entries = fs.readdirSync(dir).filter(name => name.toLowerCase().endsWith('.itermcolors'));
  } catch (error) {
    console.error('Could not read the themes directory:', error);
    return [];
  }

  const schemes = [];
  for (const entry of entries.sort((a, b) => a.localeCompare(b))) {
    const file = path.join(dir, entry);
    let parsed = null;

    try {
      parsed = parseItermColors(fs.readFileSync(file, 'utf8'));
    } catch (error) {
      console.error(`Could not read ${entry}:`, error.message);
      continue;
    }

    if (!parsed) {
      console.error(`Skipped ${entry}: no Background Color / Foreground Color pair`);
      continue;
    }

    const name = entry.replace(/\.itermcolors$/i, '');
    schemes.push({ id: `file:${name}`, name, ...parsed });
  }

  return schemes;
}
