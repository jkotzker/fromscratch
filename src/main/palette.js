/**
 * Derives the app's full CSS custom-property set from two colours.
 *
 * The original palette was a Sass file whose values were precomputed into `app.css`:
 * `lighten($bg, N%)` produced --bg-1 … --bg-20, and lighten/darken of the text colour produced
 * the --text-* ramp. That relationship is exact for the text ramp and within 1-3/255 for the
 * background ramp (Sass and this code round HSL slightly differently), so a colour scheme only
 * ever needs to supply a background and a foreground.
 *
 * Everything here is direction-aware. A ramp that lightens looks correct on a dark background and
 * collapses to white on a light one -- `lighten('#fdf6e3', 10%)` is `#ffffff` -- so each step
 * moves *away* from the background instead of always upward.
 */

const clamp01 = n => Math.min(1, Math.max(0, n));

const hexToRgb = hex => {
  const h = hex.replace('#', '').trim();
  const full = h.length === 3 ? [...h].map(c => c + c).join('') : h;
  return [0, 2, 4].map(i => parseInt(full.slice(i, i + 2), 16) / 255);
};

const rgbToHex = ([r, g, b]) =>
  '#' +
  [r, g, b]
    .map(c =>
      Math.round(clamp01(c) * 255)
        .toString(16)
        .padStart(2, '0')
    )
    .join('');

const rgbToHsl = ([r, g, b]) => {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];

  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? ((g - b) / d + (g < b ? 6 : 0)) / 6 : max === g ? ((b - r) / d + 2) / 6 : ((r - g) / d + 4) / 6;
  return [h, s, l];
};

const hslToRgb = ([h, s, l]) => {
  if (s === 0) return [l, l, l];

  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const channel = t => {
    const u = (t + 1) % 1;
    if (u < 1 / 6) return p + (q - p) * 6 * u;
    if (u < 1 / 2) return q;
    if (u < 2 / 3) return p + (q - p) * (2 / 3 - u) * 6;
    return p;
  };
  return [channel(h + 1 / 3), channel(h), channel(h - 1 / 3)];
};

/** Sass's lighten()/darken(), plus optional desaturation, in one HSL round-trip. */
const adjust = (hex, { lightness = 0, saturation = 1 } = {}) => {
  const [h, s, l] = rgbToHsl(hexToRgb(hex));
  return rgbToHex(hslToRgb([h, clamp01(s * saturation), clamp01(l + lightness / 100)]));
};

const shift = (hex, delta) => adjust(hex, { lightness: delta });

/** Blend two colours, `t` of the way from `a` to `b`. */
const mix = (a, b, t) => {
  const [ar, ag, ab] = hexToRgb(a);
  const [br, bg, bb] = hexToRgb(b);
  return rgbToHex([ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t]);
};

const withAlpha = (hex, alpha) => {
  const [r, g, b] = hexToRgb(hex).map(c => Math.round(c * 255));
  // Rounded, or scaling an alpha lands things like 0.8049999999999999 in the stylesheet.
  return `rgba(${r}, ${g}, ${b}, ${Math.round(alpha * 1000) / 1000})`;
};

/** WCAG relative luminance. */
export const luminance = hex => {
  const lin = c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const [r, g, b] = hexToRgb(hex).map(lin);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

// 0.179 is the luminance at which white and black text contrast equally. Asking "would this
// background want light text?" is the same question as "is this a dark scheme?".
export const isDark = background => luminance(background) < 0.179;

/**
 * @param {{background: string, foreground: string}} colors
 * @returns {Record<string, string>} CSS custom properties, ready to set on documentElement
 */
export function derivePalette({ background, foreground, selection = null, selectedText = null, cursor = null }) {
  const dark = isDark(background);

  // Away from the background: lighter on a dark scheme, darker on a light one.
  const surface = pct => shift(background, dark ? pct : -pct);
  // Away from the background too, so "lighter" text means "more contrast" either way.
  const emphasis = pct => shift(foreground, dark ? pct : -pct);
  const recede = pct => shift(foreground, dark ? -pct : pct);
  // Overlays sit on top of the surface, so they invert with it.
  const ink = alpha => (dark ? `rgba(255, 255, 255, ${alpha})` : `rgba(0, 0, 0, ${alpha})`);

  // On macOS these colours are painted over the window's vibrancy material, not an opaque
  // surface. Measured, that material is a flat neutral grey: about rgb(36,36,36) in dark mode and
  // rgb(202,203,204) in light. At the original 0.35 alpha it therefore contributed 65% of every
  // pixel, which was fine when the app had exactly one scheme but collapses distinct schemes onto
  // nearly the same colour -- Brogrammer rendered rgb(30,30,30) and GitHub Dark rgb(29,30,31),
  // a difference of one or two values per channel.
  //
  // The scheme has to dominate for schemes to be tellable apart, so the editor surface is close
  // to opaque and keeps only a hint of the material behind it.
  const SURFACE_ALPHA = 0.85;

  // Active line, search match and selection used to be fixed HSL lightness steps off the
  // background: 1%, 4% and 5%. Those are not perceptually uniform. +1% lightness on a background
  // at 10% lightness is visible; -1% on one at 94% is not, which left the line highlight invisible
  // on light schemes -- a difference of (0,2,5) before alpha on Solarized Light.
  //
  // Mixing toward the foreground instead guarantees contrast on any scheme, because the foreground
  // is by definition the colour chosen to be readable against that background, and it keeps the
  // overlays inside the scheme's own palette rather than washing them toward grey.
  const overlay = t => mix(background, foreground, t);

  // The active line must stay half-transparent. CodeMirror paints line backgrounds *over* the
  // selection layer -- there is no z-index on it, and .cm-content comes later in the DOM -- so an
  // opaque active line hides the selection underneath it, which is why CodeMirror's own default
  // is only 27% alpha. Contrast therefore comes from mixing further toward the foreground rather
  // than from opacity. These four values were solved so that, on both built-ins plus Brogrammer
  // and GitHub Dark, the active line reads against the surface AND a selection still reads
  // underneath it (>= 12/255 in both cases).
  const ACTIVE_LINE_MIX = 0.26;
  const ACTIVE_LINE_ALPHA = 0.5;

  // `.itermcolors` files carry their own Selection Color and Cursor Color, and every scheme tested
  // supplied both. Those are used as-is; mixing our own from the background and foreground gave
  // Brogrammer a mid-grey selection against its light-grey text, when the scheme itself specifies
  // a near-black #1f1f1f. Deriving is only the fallback for a scheme that omits them.
  const selectionColor = selection || overlay(0.38);
  const cursorColor = cursor || recede(5);
  // Several schemes brighten text while it is selected -- GitHub Dark goes from #8b949e to
  // #ffffff -- which is what makes a dark selection colour readable.
  const selectedTextColor = selectedText || foreground;

  return {
    '--bg': background,
    '--bg-1': surface(1),
    '--bg-3': surface(3),
    '--bg-4': surface(4),
    '--bg-5': surface(5),
    '--bg-8': surface(8),
    '--bg-10': surface(10),
    '--bg-20': surface(20),

    '--bg-translucent': withAlpha(background, SURFACE_ALPHA),
    '--bg-solid-ish': withAlpha(background, 0.95),
    '--bg-transparent': withAlpha(background, 0),
    '--bg-1-translucent': withAlpha(overlay(ACTIVE_LINE_MIX), ACTIVE_LINE_ALPHA),
    '--bg-4-translucent': withAlpha(overlay(0.3), 0.85),
    // Opaque: a scheme's Selection Color should render as the colour it names, not a blend of it
    // with whatever is behind the window.
    '--bg-5-translucent': selectionColor,

    '--text': foreground,
    '--text-dark-5': recede(5),
    '--text-light-15': emphasis(15),
    '--text-light-20': emphasis(20),

    // The original rgb(25, 64, 74) is not a plain ramp step: it is the same hue at +8.8 lightness
    // points with saturation halved. Fitting those two parameters reproduces it to within one
    // channel value, so panels keep their slightly muted look instead of picking up the full
    // saturation of the background.
    '--panel-bg': adjust(background, { lightness: dark ? 8.5 : -8.5, saturation: 0.5 }),

    // Selection and caret come straight from the scheme when it names them.
    '--selection': selectionColor,
    '--selected-text': selectedTextColor,
    '--cursor': cursorColor,

    '--overlay-bg': ink(0.1),
    '--overlay-bg-hover': ink(0.15),
    '--overlay-text': ink(0.4),
    '--overlay-text-hover': ink(0.7),
  };
}

/**
 * Built-in schemes. The dark one is the app's original palette verbatim; the light one is its
 * actual Solarized counterpart (base3/base00), since the dark palette is Solarized base03/base0.
 */
export const BUILT_IN_SCHEMES = [
  { id: 'built-in:dark', name: 'Dark', background: '#002b36', foreground: '#829696' },
  { id: 'built-in:light', name: 'Light', background: '#fdf6e3', foreground: '#657b83' },
];
