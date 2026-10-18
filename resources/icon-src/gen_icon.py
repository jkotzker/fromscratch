#!/usr/bin/env python3
"""Generate the FromScratch app icon on the macOS app-icon grid.

The mark is four left-aligned rounded bars -- a block of text -- on a deep
teal plate. Every path is emitted from the constants below; no third-party
vector data is used, so the artwork is safe to ship under the repo's licence.

Geometry is measured, not guessed. Apple system icons occupy exactly 824x824
at +100,+100 in a 1024x1024 canvas, and the corner is a superellipse with
exponent ~5.1 (both re-verified against the installed system icons -- see
README.md for the method and the numbers).
"""
import math

CANVAS = 1024
SIZE = 824.0
OFF = 100.0
N = 5.1                      # superellipse exponent, fitted against Apple's mask
A = SIZE / 2.0
CX = CY = OFF + A

CHOSEN = "glass"             # treatment used for the shipped icon

# --- glyph metrics ------------------------------------------------------------
# Proportions measured off the reference artwork (bar height 52, row pitch
# 137.3, long bar 540 wide, short bar 345) and rescaled from its 864-unit box
# onto Apple's 824-unit box.
BAR_H = 50.0
LONG_W = 516.0
SHORT_W = 330.0
PITCH = 131.0
LEFT = CX - LONG_W / 2.0
ROWS = (1.0, SHORT_W / LONG_W, 1.0, SHORT_W / LONG_W)

# --- colours ------------------------------------------------------------------
# Everything but the dark gradient stop comes from the app's own stylesheet
# (src/renderer/src/assets/style/app.css).
INK = "#829696"              # --text, the bars
INK_HI = "#9aacac"           # lighter stop, glass bars only
INK_LO = "#73898a"           # darker stop, glass bars only
INK_SMALL = "#b9c5c5"        # --text-light-20, the 16px artwork
TOP = "#0f2f3d"              # plate gradient, top
BOT = "#537482"              # plate gradient, bottom


def squircle(steps=2000, inset=0.0):
    a = A - inset
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = CX + a * math.copysign(abs(ct) ** (2.0 / N), ct)
        y = CY + a * math.copysign(abs(st) ** (2.0 / N), st)
        pts.append(f"{x:.2f},{y:.2f}")
    return " ".join(pts)


def bars(fill, opacity=1.0):
    """The four text rows, centred on the plate."""
    out = []
    for i, frac in enumerate(ROWS):
        y = CY + (i - (len(ROWS) - 1) / 2.0) * PITCH - BAR_H / 2.0
        out.append(
            f'<rect x="{LEFT:.1f}" y="{y:.1f}" width="{LONG_W * frac:.1f}" '
            f'height="{BAR_H:.1f}" rx="{BAR_H / 2:.1f}" fill="{fill}" '
            f'opacity="{opacity}"/>'
        )
    return "\n".join(out)


def small_bars():
    """16px and 32px artwork.

    At 16px a 50-unit bar is 0.78px wide and the four rows blur into a single
    smear, so small sizes get three much thicker rows in the lighter ink. This
    is the same approach Apple's own icons take.
    """
    h, pitch, long_w = 96.0, 196.0, 496.0
    left = CX - long_w / 2.0
    out = []
    for i, frac in enumerate((1.0, 0.62, 1.0)):
        y = CY + (i - 1) * pitch - h / 2.0
        out.append(
            f'<rect x="{left:.1f}" y="{y:.1f}" width="{long_w * frac:.1f}" '
            f'height="{h:.1f}" rx="{h / 2:.1f}" fill="{INK_SMALL}"/>'
        )
    return "\n".join(out)


# --- shared defs --------------------------------------------------------------
BG_GRAD = (
    '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
    f'<stop offset="0" stop-color="{TOP}"/>'
    f'<stop offset="1" stop-color="{BOT}"/>'
    "</linearGradient>"
)

# A lit inner edge -- bright along the top, gone by the middle, a faint lift at
# the bottom. This is what reads as glass at a glance; a uniform stroke reads as
# a drawn outline instead.
RIM_GRAD = (
    '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0.34"/>'
    '<stop offset="0.38" stop-color="#ffffff" stop-opacity="0.03"/>'
    '<stop offset="0.80" stop-color="#ffffff" stop-opacity="0.06"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0.13"/>'
    "</linearGradient>"
)

# Kept deliberately weak: a stronger sheen washes out the dark top of the plate
# gradient, which is the part that gives the icon its depth.
SHEEN_GRAD = (
    '<radialGradient id="sheen" cx="0.5" cy="-0.10" r="0.62">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0.085"/>'
    '<stop offset="0.6" stop-color="#ffffff" stop-opacity="0.02"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>'
    "</radialGradient>"
)

BAR_GRAD = (
    '<linearGradient id="bar" x1="0" y1="0" x2="0" y2="1">'
    f'<stop offset="0" stop-color="{INK_HI}"/>'
    f'<stop offset="0.55" stop-color="{INK}"/>'
    f'<stop offset="1" stop-color="{INK_LO}"/>'
    "</linearGradient>"
)

# librsvg does not implement feDropShadow -- it renders as a no-op, silently.
# The longhand chain below does render; check any change to it against output,
# not against the spec.
SHADOW_F = (
    '<filter id="sh" x="-25%" y="-25%" width="150%" height="165%">'
    '<feGaussianBlur in="SourceAlpha" stdDeviation="11" result="b"/>'
    '<feOffset in="b" dy="5" result="o"/>'
    '<feFlood flood-color="#00141b" flood-opacity="0.30" result="f"/>'
    '<feComposite in="f" in2="o" operator="in" result="s"/>'
    '<feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge>'
    "</filter>"
)

# glass-plus only: a brighter rim and a diagonal sweep. Retained as an
# alternative treatment, not shipped.
SWEEP_GRAD = (
    '<linearGradient id="sweep" x1="0" y1="0" x2="0.85" y2="1">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0.11"/>'
    '<stop offset="0.45" stop-color="#ffffff" stop-opacity="0.02"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/>'
    "</linearGradient>"
)
RIM2_GRAD = (
    '<linearGradient id="rim2" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#ffffff" stop-opacity="0.46"/>'
    '<stop offset="0.40" stop-color="#ffffff" stop-opacity="0.05"/>'
    '<stop offset="0.82" stop-color="#ffffff" stop-opacity="0.08"/>'
    '<stop offset="1" stop-color="#ffffff" stop-opacity="0.17"/>'
    "</linearGradient>"
)


def svg(defs, body):
    d = f"<defs>{defs}</defs>" if defs else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" '
        f'height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">{d}{body}</svg>'
    )


def _overlay(grad_id):
    return (f'<g clip-path="url(#c)"><rect x="{OFF}" y="{OFF}" width="{SIZE}" '
            f'height="{SIZE}" fill="url(#{grad_id})"/></g>')


def _rim(grad_id, width):
    return (f'<g clip-path="url(#c)"><polygon points="{squircle(inset=2.0)}" '
            f'fill="none" stroke="url(#{grad_id})" stroke-width="{width}"/></g>')


def build(variant):
    pts = squircle()
    clip = f'<clipPath id="c"><polygon points="{pts}"/></clipPath>'
    plate = f'<polygon points="{pts}" fill="url(#bg)"/>'

    if variant == "clean":
        # Flat: the mark with no glass treatment at all.
        return svg(BG_GRAD + clip,
                   plate + f'<g clip-path="url(#c)">{bars(INK)}</g>')

    if variant == "glass":
        glyph = f'<g clip-path="url(#c)" filter="url(#sh)">{bars("url(#bar)")}</g>'
        return svg(BG_GRAD + RIM_GRAD + SHEEN_GRAD + BAR_GRAD + SHADOW_F + clip,
                   plate + _overlay("sheen") + glyph + _rim("rim", 4))

    if variant == "glass-plus":
        glyph = (f'<g clip-path="url(#c)" filter="url(#sh)">'
                 f'{bars("url(#bar)", opacity=0.93)}</g>')
        return svg(
            BG_GRAD + RIM_GRAD + SHEEN_GRAD + BAR_GRAD + SHADOW_F
            + SWEEP_GRAD + RIM2_GRAD + clip,
            plate + _overlay("sheen") + _overlay("sweep") + glyph
            + _rim("rim2", 5))

    if variant == "small":
        return svg(BG_GRAD + clip,
                   plate + f'<g clip-path="url(#c)">{small_bars()}</g>')

    raise ValueError(variant)


VARIANTS = ("clean", "glass", "glass-plus")


def main():
    for name in VARIANTS:
        open(f"variant-{name}.svg", "w").write(build(name))
    open(f"variant-{CHOSEN}-small.svg", "w").write(build("small"))

    # Layers for Icon Composer, back to front. Icon Composer applies its own
    # Liquid Glass material, so these are deliberately flat -- the rim, sheen
    # and bar shadow above exist only for the .icns, which gets no such
    # treatment from the system.
    pts = squircle()
    open("layer-1-background.svg", "w").write(
        svg(BG_GRAD, f'<polygon points="{pts}" fill="url(#bg)"/>'))
    open("layer-2-bars.svg", "w").write(svg("", bars(INK)))

    print(f"wrote {len(VARIANTS)} variants + small + 2 layers (chosen: {CHOSEN})")


if __name__ == "__main__":
    main()
