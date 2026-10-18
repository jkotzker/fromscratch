# Icon sources

The app icon is generated from these files, not hand-drawn. Run `./build-icns.sh` to rebuild `../icon.icns`, `../icon.png` and `../icon.ico`.

Requires `rsvg-convert` (`brew install librsvg`) and `magick` (`brew install imagemagick`). `iconutil` and `python3` ship with macOS.

## The mark

Four left-aligned rounded bars — a block of text — on a deep teal plate, with the last line of each pair running short the way a paragraph does.

Every path is emitted from the constants at the top of `gen_icon.py`: four `<rect>` elements with an `rx` of half their height. **No third-party vector data is used.** The proportions were measured off a reference drawing and rescaled onto Apple's grid — bar height 52, row pitch 137.3, long bar 540 units, short bar 345 (a ratio of 0.64), all scaled by 824/864 — so the artwork reproduces a familiar shape without copying anyone's file. This matters because the repo is MIT-licensed and distributed: an icon containing, say, SF Symbols artwork could not be shipped under those terms.

The artwork was designed with LLM assistance (Claude), including the glyph metrics, the glass treatment, and the measurement of Apple's icon grid described below.

## The grid

macOS app icons since Big Sur sit on a fixed grid, and getting it wrong has a visible cost: macOS 26 (Tahoe) detects non-conforming icons and shrinks them onto a grey squircle background — "squircle jail".

The geometry here was measured rather than taken from a blog post, and re-verified against the icons installed on this machine. Extracting Notes, Reminders, Terminal and Mail from `/System/Applications` and thresholding their alpha channels gives an opaque bounding box of exactly **206×206 at +25,+25** in their 256px slices — **824×824 at +100,+100** in a 1024×1024 canvas, identical across all four.

The corner is a **superellipse, not a circular arc**. Fitting the exponent by generating candidates and pixel-diffing them against Notes' real alpha mask at 256×256:

| exponent | differing pixels |
|---------:|-----------------:|
| 4.80     | 374 |
| 5.00     | 234 |
| **5.10** | **210** |
| 5.20     | 212 |
| 5.40     | 224 |
| 6.00     | 404 |

210 pixels out of 65,536, against a perimeter of roughly 800px, is about a quarter-pixel of antialiasing along the edge — so `N = 5.1` reproduces Apple's shape closely enough to be indistinguishable, without shipping an extracted Apple asset.

## No baked drop shadow

System icons carry **no outer shadow**: alpha is 0 three pixels in from every edge on all four icons measured above. macOS draws the shadow itself at composite time, so baking one into the `.icns` doubles it up. Icon tools that target older conventions still add one — if artwork is ever brought in from elsewhere, check for it.

## Colours

Every colour except one comes from the app's own stylesheet (`src/renderer/src/assets/style/app.css`):

- `#829696` — `--text`, the bars
- `#b9c5c5` — `--text-light-20`, the small-size bars
- `#537482` — the light stop of the plate gradient

`#0f2f3d`, the dark stop of the plate gradient, is the one invented colour; it is darker than anything in the stylesheet.

`#9aacac` and `#73898a` are the lighter and darker stops used to give the bars a vertical gradient in the glass treatment. They bracket `--text`, which sits at the gradient's midpoint, so the bars read as the same colour as the app's body text.

## Treatments

`gen_icon.py` emits three, selected by the `CHOSEN` constant:

- **`clean`** — the mark flat on the gradient, nothing added.
- **`glass`** — *shipped.* A lit inner rim (bright along the top edge, gone by the middle, a faint lift at the bottom), a weak top sheen, and bars with a vertical gradient and a soft cast shadow.
- **`glass-plus`** — retained, not shipped. `glass` plus a diagonal sweep across the upper left, a brighter rim, and slightly translucent bars. Glassier up close; flattens out at Dock size, which is why `glass` ships.

Switching the shipped treatment is a one-line change to `CHOSEN` followed by `./build-icns.sh`.

Two notes on the glass treatment, both found by rendering rather than by reading specs:

- **librsvg silently ignores `feDropShadow`** — it renders as a no-op with no warning. The bar shadow uses the `feGaussianBlur` → `feOffset` → `feFlood` → `feComposite` → `feMerge` longhand, which does render. Check any change to it against output.
- **The sheen is deliberately weak.** A stronger one washes out the dark top of the plate gradient, which is the part carrying the icon's depth.

## Small sizes use different artwork

Below about 64px the four bars blur into a single smear — at 16px a 50-unit bar is 0.78px wide. 16px and 32px therefore use `variant-glass-small.svg`: three much thicker rows in the lighter ink, with no rim, sheen or shadow, none of which survive the downscale. This is the same approach Apple's own icons take.

## Layers

`layer-1-background.svg` and `layer-2-bars.svg` are the same artwork split back-to-front for **Icon Composer**, which builds the Liquid Glass `.icon` bundle for macOS 26.

They are deliberately **flat** — no rim, sheen or shadow. Icon Composer applies its own material; the treatment in `variant-glass.svg` exists only because an `.icns` gets no such treatment from the system, and layering both would double it.

They are not used by `build-icns.sh` — they exist so the Liquid Glass version can be assembled without redrawing anything. That step needs Icon Composer, which requires **macOS Tahoe 26.4 or later**, and compiling `.icon` to `Assets.car` needs `actool` from Xcode 26. Neither runs on Sequoia, which is why only the `.icns` is built here.

## The Windows .ico

`build-icns.sh` also regenerates `../icon.ico` from these same sources. It previously did not, so the `.ico` still held the original upstream artwork and Windows builds shipped a different icon from macOS. The Windows target is untested from this machine, but the asset is now at least consistent.

## Determinism

`gen_icon.py` contains no randomness and no timestamps: regenerating produces byte-identical SVGs, so the committed files will not churn. Verify with `md5 variant-glass.svg`, re-run, and compare.
