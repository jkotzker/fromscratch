# Icon sources

The app icon is generated from these files, not hand-drawn. Run `./build-icns.sh`
to rebuild `../icon.icns` and `../icon.png`.

The artwork was designed with LLM assistance (Claude) — the stroke geometry, the
colour treatment, and the measurement of Apple's icon grid described below. It
deliberately keeps the original icon's idea, scribbled lines and a text caret,
rather than inventing a new mark.

Requires `rsvg-convert` (`brew install librsvg`). `iconutil` and `python3` ship
with macOS.

## The grid

macOS app icons since Big Sur sit on a fixed grid, and getting it wrong has a
visible cost: macOS 26 (Tahoe) detects non-conforming icons and shrinks them
onto a grey squircle background — "squircle jail". The icon this replaced was a
sharp-cornered square with three window dots floating outside it on
transparency, which is close to a worst case for that heuristic.

The geometry here was measured rather than taken from a blog post. Extracting
Terminal, Notes, and Reminders from `/System/Applications` and thresholding
their alpha channels gives an opaque bounding box of exactly **824×824 at
+100,+100** in a 1024×1024 canvas, identical across all three.

The corner is a **superellipse, not a circular arc** — 200px in from the top
edge it is still converging on the straight edge. Fitting the exponent by
generating candidates and pixel-diffing them against Apple's real mask:

| exponent | differing pixels |
|---------:|-----------------:|
| 5.00     | 3223 |
| 5.05     | 3129 |
| **5.10** | **3075** |
| 5.15     | 3132 |

Against a perimeter of roughly 3230px, that is about one pixel of antialiasing
along the edge — so `N = 5.1` reproduces Apple's shape closely enough to be
indistinguishable, without shipping an extracted Apple asset in an MIT repo.

## Colours

Every colour except one comes from the app's own stylesheet
(`src/renderer/src/assets/style/app.css`):

- `#005269` — `--bg-10`
- `#829696` — `--text`, the scribbled rows
- `#b9c5c5` — `--text-light-20`, the small-size rows

`#001f28`, the dark stop of the background gradient, is the one invented colour;
it is darker than anything in the stylesheet.

## Small sizes use different artwork

Below about 64px the scribbled strokes fall under half a pixel wide and
`#829696` blends into the background. 16px and 32px therefore use
`variant-deep-small.svg` — three thick bars in the lighter ink. The caret only
appears at 64px and above. This is the same approach Apple's own icons take.

## Layers

`layer-1-background.svg`, `layer-2-lines.svg`, and `layer-3-caret.svg` are the
same artwork split back-to-front for **Icon Composer**, which builds the Liquid
Glass `.icon` bundle for macOS 26.

They are not used by `build-icns.sh` — they exist so the Liquid Glass version
can be assembled without redrawing anything. That step needs Icon Composer,
which requires **macOS Tahoe 26.4 or later**, and compiling `.icon` to
`Assets.car` needs `actool` from Xcode 26. Neither runs on Sequoia, which is why
only the `.icns` is built here.

## Determinism

The scribbled strokes need slight irregularity or they read as a sine wave
rather than handwriting, so `gen_icon.py` uses a fixed-seed LCG rather than
`random`. Regenerating produces byte-identical SVGs; the committed files will
not churn.
