#!/usr/bin/env python3
"""Generate layered FromScratch icon artwork on the macOS app-icon grid.

Geometry is measured, not guessed: Apple system icons (Terminal, Notes,
Reminders) occupy exactly 824x824 at +100,+100 in a 1024x1024 canvas, and the
corner is a superellipse with exponent ~5.1 (fitted by pixel-diffing generated
candidates against the real mask).

Layers are emitted separately, named back-to-front, so they drop straight into
Icon Composer on Tahoe without rework.
"""
import math

CANVAS = 1024
SIZE = 824.0
OFF = 100.0
N = 5.1                      # superellipse exponent, fitted against Apple's mask
A = SIZE / 2.0
CX = CY = OFF + A

CHOSEN = "deep"             # colour treatment selected for the shipped icon
TEXT = "#829696"             # --text from the app stylesheet


def squircle_points(steps=2000, inset=0.0):
    a = A - inset
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = CX + a * math.copysign(abs(ct) ** (2.0 / N), ct)
        y = CY + a * math.copysign(abs(st) ** (2.0 / N), st)
        pts.append(f"{x:.2f},{y:.2f}")
    return " ".join(pts)


def svg(body, defs=""):
    d = f"<defs>{defs}</defs>" if defs else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" '
            f'height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">{d}{body}</svg>')


# --- deterministic pseudo-randomness -----------------------------------------
# Hand-written strokes need slight irregularity or they read as a sine wave, but
# the output must be byte-identical on every run, so this is a fixed LCG rather
# than `random`.
class Rng:
    def __init__(self, seed):
        self.s = seed

    def next(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s / 0x7FFFFFFF

    def between(self, lo, hi):
        return lo + (hi - lo) * self.next()


def word(x0, y, cycles, amp, period, rng):
    """One 'word': a run of tight cursive loops.

    Each cycle is two quadratics -- down then up -- with the control points
    pushed outward so the bottoms round off like handwritten u/w shapes. A
    single symmetric quadratic per cycle reads as a sine wave instead.
    """
    d = [f"M {x0:.1f},{y:.1f}"]
    x = x0
    for _ in range(cycles):
        p = period * rng.between(0.88, 1.12)
        a = amp * rng.between(0.85, 1.15)
        d.append(f"q {p * 0.30:.1f},{a:.1f} {p * 0.5:.1f},{a * 0.06:.1f}")
        d.append(f"q {p * 0.22:.1f},{-a * 1.05:.1f} {p * 0.5:.1f},{-a * 0.06:.1f}")
        x += p
    return " ".join(d), x


def scribble(x0, x1, y, amp, period, rng):
    """A line of 'text': several words with gaps, filling up to x1.

    A word that would overrun is retried at shorter lengths rather than dropped,
    otherwise every line stops well short of the margin and the block reads as
    left-weighted with a ragged hole down the right.
    """
    segs = []
    x = x0
    while x < x1:
        placed = False
        for cycles in range(int(rng.between(3, 5.99)), 1, -1):
            w, xe = word(x, y, cycles, amp, period, rng)
            if xe <= x1:
                segs.append(w)
                x = xe + period * rng.between(0.55, 0.95)   # word gap
                placed = True
                break
        if not placed:
            break
    # x currently includes the trailing gap; report where the ink actually ended.
    return " ".join(segs), (x - period * 0.7 if segs else x0)


def build_lines(rows=4, stroke=26):
    """The scribbled 'text' rows -- the mid layer."""
    rng = Rng(20260829)
    left, right = 232.0, 792.0
    top, gap = 336.0, 128.0
    amp, period = 17.0, 58.0
    out = []
    end_x = left
    for i in range(rows):
        y = top + i * gap
        # Last row stops short, like a paragraph ending, leaving room for the caret.
        limit = right if i < rows - 1 else left + (right - left) * 0.55
        d, end_x = scribble(left, limit, y, amp, period, rng)
        out.append(
            f'<path d="{d}" fill="none" stroke="{TEXT}" stroke-width="{stroke}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
        )
    return "\n".join(out), top + (rows - 1) * gap, end_x


def build_caret(x, y, h=112, w=24):
    """The blinking text cursor -- the foreground layer."""
    return (f'<rect x="{x + 26:.1f}" y="{y - h / 2:.1f}" width="{w}" height="{h}" '
            f'rx="{w / 2}" fill="{TEXT}"/>')


BACKGROUNDS = {
    # name: (defs, fill)
    "flat": ("", "#002b36"),
    "subtle": (
        '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#003e4f"/><stop offset="1" stop-color="#002b36"/>'
        "</linearGradient>", "url(#g)"),
    "vivid": (
        '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#00799c"/><stop offset="1" stop-color="#002b36"/>'
        "</linearGradient>", "url(#g)"),
    "deep": (
        '<linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#005269"/><stop offset="1" stop-color="#001f28"/>'
        "</linearGradient>", "url(#g)"),
}


def build_small():
    """Simplified artwork for 16px and 32px.

    The detailed version washes out below ~64px: at 16px a 26-unit stroke is
    under half a pixel and #829696 blends into the background. Small sizes get
    fewer, much thicker rows in a lighter ink (--text-light-20) so the icon
    still reads as written-on paper in the Finder sidebar and Cmd-Tab strip.
    """
    ink = "#b9c5c5"
    left, right = 250.0, 774.0
    rows = [(0.00, 1.00), (0.34, 0.86), (0.68, 0.55)]
    top, gap, stroke = 396.0, 132.0, 62.0
    out = []
    for i, (_, frac) in enumerate(rows):
        y = top + i * gap
        x1 = left + (right - left) * frac
        out.append(f'<path d="M {left},{y} L {x1:.1f},{y}" stroke="{ink}" '
                   f'stroke-width="{stroke}" stroke-linecap="round"/>')
    return "\n".join(out)


def main():
    pts = squircle_points()
    lines, last_y, last_x = build_lines()
    caret = build_caret(last_x, last_y)

    # Layers, back to front, for Icon Composer. The background carries the same
    # gradient as the shipped flat artwork so the two cannot drift apart.
    bg_defs, bg_fill = BACKGROUNDS[CHOSEN]
    open("layer-1-background.svg", "w").write(
        svg(f'<polygon points="{pts}" fill="{bg_fill}"/>', bg_defs))
    open("layer-2-lines.svg", "w").write(svg(lines))
    open("layer-3-caret.svg", "w").write(svg(caret))

    # Flattened variants for comparison. Content is clipped to the squircle so
    # nothing can spill past the mask.
    for name, (defs, fill) in BACKGROUNDS.items():
        clip = f'<clipPath id="c"><polygon points="{pts}"/></clipPath>'
        body = (f'<polygon points="{pts}" fill="{fill}"/>'
                f'<g clip-path="url(#c)">{lines}{caret}</g>')
        open(f"variant-{name}.svg", "w").write(svg(body, defs + clip))

    # Small-size artwork, same background so the two read as one icon.
    defs, fill = BACKGROUNDS[CHOSEN]
    clip = f'<clipPath id="c"><polygon points="{pts}"/></clipPath>'
    open(f"variant-{CHOSEN}-small.svg", "w").write(svg(
        f'<polygon points="{pts}" fill="{fill}"/>'
        f'<g clip-path="url(#c)">{build_small()}</g>', defs + clip))

    print("wrote 3 layers + %d variants + small" % len(BACKGROUNDS))


if __name__ == "__main__":
    main()
