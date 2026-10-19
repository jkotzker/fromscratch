// Generates Tests/FromScratchCoreTests/Fixtures/palette.json from the vendored v2 palette.js (scripts/reference/palette.mjs),
// so the Swift port is checked against what v2 actually emits.
//   node native/scripts/gen-palette-fixtures.mjs > native/Tests/FromScratchCoreTests/Fixtures/palette.json
import { derivePalette, isDark, BUILT_IN_SCHEMES } from './reference/palette.mjs';

const inputs = [
  ...BUILT_IN_SCHEMES.map(s => ({ background: s.background, foreground: s.foreground })),
  { background: '#1d1f21', foreground: '#c5c8c6', selection: '#373b41', selectedText: '#ffffff', cursor: '#c5c8c6' },
  { background: '#fafafa', foreground: '#383a42' },
  { background: '#000000', foreground: '#ffffff' },
  { background: '#ffffff', foreground: '#000000' },
  // Luminance threshold pair (0.179 boundary) straddling dark/light.
  { background: '#757575', foreground: '#ffffff' },
  { background: '#767676', foreground: '#000000' },
  // Saturated mid-tone to exercise the HSL round trip and hue branches.
  { background: '#2b3a67', foreground: '#e0def4' },
];

const keys = ['--bg-translucent', '--bg-1-translucent', '--selection', '--selected-text', '--cursor', '--overlay-bg', '--overlay-text', '--overlay-text-hover', '--bg', '--text'];

const out = inputs.map(input => {
  const p = derivePalette(input);
  const entry = { input, dark: isDark(input.background) };
  for (const k of keys) entry[k] = p[k];
  return entry;
});

process.stdout.write(JSON.stringify(out, null, 2) + '\n');
