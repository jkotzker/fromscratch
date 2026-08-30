/**
 * Enumerates the fonts installed on this machine.
 *
 * Uses the Local Font Access API. Electron grants `local-fonts` by default -- no permission
 * handler and no user gesture are needed -- but it does require a secure context, which the
 * packaged app has because it loads over file://. If the API is missing (or refuses), this
 * returns an empty list and the picker falls back to the bundled font alone.
 */

// The bundled face. It is a @font-face, not an installed font, so it never appears in
// queryLocalFonts() output and has to be added by hand.
export const BUNDLED_FAMILY = 'FiraCode';

/**
 * A font is monospace when narrow and wide glyphs share an advance width.
 *
 * This is a heuristic: a handful of CJK and symbol faces (Wingdings 2, SimSong, PCMyungjo) have
 * uniform advances too and come through as monospace. It is right for the fonts anyone would
 * actually pick for an editor, which is what it is for.
 */
const monospaceTester = () => {
  const context = document.createElement('canvas').getContext('2d');
  return family => {
    context.font = `64px "${CSS.escape ? family.replace(/"/g, '\\"') : family}"`;
    const narrow = context.measureText('i').width;
    const wide = context.measureText('W').width;
    const el = context.measureText('l').width;
    return narrow > 0 && Math.abs(narrow - wide) < 0.01 && Math.abs(narrow - el) < 0.01;
  };
};

/** @returns {Promise<Array<{family: string, monospace: boolean}>>} sorted, deduped to families */
export async function listFontFamilies() {
  const bundled = { family: BUNDLED_FAMILY, monospace: true, bundled: true };

  if (typeof window.queryLocalFonts !== 'function') return [bundled];

  let records = [];
  try {
    records = await window.queryLocalFonts();
  } catch {
    // Permission denied or unavailable; the bundled face is still selectable.
    return [bundled];
  }

  const isMonospace = monospaceTester();
  const families = [...new Set(records.map(record => record.family))]
    .filter(family => family && family !== BUNDLED_FAMILY)
    .sort((a, b) => a.localeCompare(b))
    .map(family => ({ family, monospace: isMonospace(family), bundled: false }));

  return [bundled, ...families];
}

/**
 * A CSS font-family value for a chosen family, always falling back to the bundled face and then
 * a generic monospace, so a family uninstalled since it was chosen still renders sensibly.
 */
export function fontStack(family) {
  if (!family || family === BUNDLED_FAMILY) return null;
  return `"${family.replace(/"/g, '\\"')}", "${BUNDLED_FAMILY}", monospace`;
}
