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
  const h =
    max === r ? ((g - b) / d + (g < b ? 6 : 0)) / 6 : max === g ? ((b - r) / d + 2) / 6 : ((r - g) / d + 4) / 6;
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
export function derivePalette({ background, foreground }) {
  const dark = isDark(background);

  // Away from the background: lighter on a dark scheme, darker on a light one.
  const surface = pct => shift(background, dark ? pct : -pct);
  // Away from the background too, so "lighter" text means "more contrast" either way.
  const emphasis = pct => shift(foreground, dark ? pct : -pct);
  const recede = pct => shift(foreground, dark ? -pct : pct);
  // Overlays sit on top of the surface, so they invert with it.
  const ink = alpha => (dark ? `rgba(255, 255, 255, ${alpha})` : `rgba(0, 0, 0, ${alpha})`);

  // On macOS these colours are painted over the window's vibrancy material rather than over an
  // opaque background. That material is a light neutral grey (measured at about rgb(202,203,204)),
  // so at the original 0.35 alpha it swamps a light scheme: Solarized Light's #fdf6e3 rendered as
  // rgb(220,216,212), losing almost all of its warmth. Dark schemes sit against a dark material
  // and keep their character, so only light schemes need the extra opacity.
  const veil = dark ? 1 : 2.3;
  const tint = (hex, alpha) => withAlpha(hex, Math.min(0.95, alpha * veil));

  return {
    '--bg': background,
    '--bg-1': surface(1),
    '--bg-3': surface(3),
    '--bg-4': surface(4),
    '--bg-5': surface(5),
    '--bg-8': surface(8),
    '--bg-10': surface(10),
    '--bg-20': surface(20),

    '--bg-translucent': tint(background, 0.35),
    '--bg-solid-ish': withAlpha(background, 0.95),
    '--bg-transparent': withAlpha(background, 0),
    '--bg-1-translucent': tint(surface(1), 0.5),
    '--bg-4-translucent': tint(surface(4), 0.5),
    '--bg-5-translucent': tint(surface(5), 0.5),

    '--text': foreground,
    '--text-dark-5': recede(5),
    '--text-light-15': emphasis(15),
    '--text-light-20': emphasis(20),
    '--text-transparent': withAlpha(foreground, 0),

    // The original rgb(25, 64, 74) is not a plain ramp step: it is the same hue at +8.8 lightness
    // points with saturation halved. Fitting those two parameters reproduces it to within one
    // channel value, so panels keep their slightly muted look instead of picking up the full
    // saturation of the background.
    '--panel-bg': adjust(background, { lightness: dark ? 8.5 : -8.5, saturation: 0.5 }),

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
