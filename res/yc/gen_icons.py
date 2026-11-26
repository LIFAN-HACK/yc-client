#!/usr/bin/env python3
"""Regenerate every OpenDesk icon from one drawing. Needs Pillow.

    python3 res/yc/gen_icons.py [web-dir]

Run from the repo root. The optional web-dir also refreshes the site icons.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

INK = (11, 13, 16, 255)
PAPER = (255, 255, 255, 255)
SS = 4  # supersampling factor
ROOT = Path(__file__).resolve().parents[2]

# The organisation mark (ring and dot, viewBox 320x310) laid on a 100-unit canvas, with the
# product glyph, a monitor with a pointer, cut into the ring's lower right like open-drive's lock.
K = 0.268
OX = 50 - (9.5 + 291.5 / 2) * K
OY = 49.5 - (15 + 261.5 / 2) * K
RING = (OX + 130 * K, OY + 156 * K, 110 * K, 21 * K)  # cx, cy, r, stroke
DOT = (OX + 279 * K, OY + 37 * K, 22 * K)
SCREEN = (56.0, 59.55, 87.0, 81.05, 4.2)  # x0, y0, x1, y1, radius
BASE = (63.3, 85.35, 79.7, 89.45, 2.05)
NECK = (68.9, 74.1)
GAP = 2.6
POINTER = [(0, 0), (0, 16.5), (4.4, 12.6), (7.4, 19.2), (10.6, 17.7), (7.6, 11.3), (13.4, 11.0)]
POINTER_AT = (66.5, 65.216, 0.62)  # x, y, scale


def _pointer():
    ax, ay, k = POINTER_AT
    return [(ax + x * k, ay + y * k) for x, y in POINTER]


SVG_MARK = (
    '<circle cx="{cx:.3f}" cy="{cy:.3f}" r="{r:.3f}" fill="none" stroke="{fg}" stroke-width="{w:.3f}"/>'
    '<circle cx="{dx:.3f}" cy="{dy:.3f}" r="{dr:.3f}" fill="{fg}"/>'
    '<rect x="{kx:.2f}" y="{ky:.2f}" width="{kw:.2f}" height="{kh:.2f}" rx="{kr:.2f}" fill="{bg}"/>'
    '<rect x="{bkx:.2f}" y="{sy1:.2f}" width="{bkw:.2f}" height="{bkh:.2f}" rx="4.6" fill="{bg}"/>'
    '<rect x="{sx0:.2f}" y="{sy0:.2f}" width="{sw:.2f}" height="{sh:.2f}" rx="{sr:.2f}" fill="{fg}"/>'
    '<rect x="{nx:.2f}" y="{sy1b:.2f}" width="{nw:.2f}" height="{nh:.2f}" fill="{fg}"/>'
    '<rect x="{bx:.2f}" y="{by:.2f}" width="{bw:.2f}" height="{bh:.2f}" rx="{br:.2f}" fill="{fg}"/>'
    '<path d="{ptr}" fill="{bg}"/>'
)


def svg(rx, fg="#0b0d10", bg="#ffffff"):
    x0, y0, x1, y1, sr = SCREEN
    bx0, by0, bx1, by1, br = BASE
    ptr = "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in _pointer()) + "z"
    body = SVG_MARK.format(
        cx=RING[0], cy=RING[1], r=RING[2], w=RING[3], dx=DOT[0], dy=DOT[1], dr=DOT[2], fg=fg, bg=bg,
        kx=x0 - GAP, ky=y0 - GAP, kw=x1 - x0 + 2 * GAP, kh=y1 - y0 + 2 * GAP, kr=sr + GAP,
        bkx=bx0 - GAP, sy1=y1, bkw=bx1 - bx0 + 2 * GAP, bkh=by1 + GAP - y1,
        sx0=x0, sy0=y0, sw=x1 - x0, sh=y1 - y0, sr=sr,
        nx=NECK[0], sy1b=y1 - 0.2, nw=NECK[1] - NECK[0], nh=by0 - y1 + 0.4,
        bx=bx0, by=by0, bw=bx1 - bx0, bh=by1 - by0, br=br, ptr=ptr)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
            f'<rect width="100" height="100" rx="{rx}" fill="{bg}"/>{body}</svg>\n')


def mark_mask(size, box):
    """Alpha mask of the mark. `box` = (x0, y0, x1, y1) of the 100-unit canvas shown."""
    n = size * SS
    k = n / (box[2] - box[0])
    px = lambda x: (x - box[0]) * k
    py = lambda y: (y - box[1]) * k
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    cx, cy, r, w = RING
    d.ellipse([px(cx - r - w / 2), py(cy - r - w / 2), px(cx + r + w / 2), py(cy + r + w / 2)], fill=255)
    d.ellipse([px(cx - r + w / 2), py(cy - r + w / 2), px(cx + r - w / 2), py(cy + r - w / 2)], fill=0)
    dx, dy, dr = DOT
    d.ellipse([px(dx - dr), py(dy - dr), px(dx + dr), py(dy + dr)], fill=255)
    x0, y0, x1, y1, sr = SCREEN
    bx0, by0, bx1, by1, br = BASE
    d.rounded_rectangle([px(x0 - GAP), py(y0 - GAP), px(x1 + GAP), py(y1 + GAP)], radius=(sr + GAP) * k, fill=0)
    d.rounded_rectangle([px(bx0 - GAP), py(y1), px(bx1 + GAP), py(by1 + GAP)], radius=(GAP + 2) * k, fill=0)
    d.rounded_rectangle([px(x0), py(y0), px(x1), py(y1)], radius=sr * k, fill=255)
    d.rectangle([px(NECK[0]), py(y1) - 1, px(NECK[1]), py(by0) + 1], fill=255)
    d.rounded_rectangle([px(bx0), py(by0), px(bx1), py(by1)], radius=br * k, fill=255)
    d.polygon([(px(x), py(y)) for x, y in _pointer()], fill=0)
    return m


def glyph(size, box, color=INK):
    n = size * SS
    layer = Image.new("RGBA", (n, n), color)
    layer.putalpha(mark_mask(size, box))
    return layer


def down(img, size):
    return img.resize((size, size), Image.LANCZOS)


def tile(size, radius=0.2, inset=0.0, shape="round-rect", zoom=1.0):
    """White tile with the black mark. inset = transparent margin as a fraction of the canvas."""
    n = size * SS
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    a, b = n * inset, n * (1 - inset)
    if shape == "circle":
        d.ellipse([a, a, b, b], fill=255)
    elif shape == "square":
        d.rectangle([a, a, b, b], fill=255)
    else:
        d.rounded_rectangle([a, a, b, b], radius=(b - a) * radius, fill=255)
    img = Image.new("RGBA", (n, n), PAPER)
    img.putalpha(mask)
    span = 100 * (1 / (1 - 2 * inset)) / zoom
    lo = 50 - span / 2
    img.alpha_composite(glyph(size, (lo, lo, lo + span, lo + span)))
    return down(img, size)


def bare(size, color, pad=3.0):
    """Mark alone, cropped close, for trays and notification icons."""
    lo, hi = 10.9 - pad, 89.1 + pad
    span = hi - lo
    cy = (14.5 + 89.5) / 2
    return down(glyph(size, (lo, cy - span / 2, hi, cy + span / 2), color), size)


def bare_two_tone(size, color, dot_color, pad=1.0):
    """Mark alone with the dot in its own colour, for the warm in-app logo."""
    lo, hi = 10.9 - pad, 89.1 + pad
    span = hi - lo
    cy = (14.5 + 89.5) / 2
    box = (lo, cy - span / 2, hi, cy + span / 2)
    n = size * SS
    k = n / (box[2] - box[0])
    dot = Image.new("L", (n, n), 0)
    dx, dy, dr = DOT
    ImageDraw.Draw(dot).ellipse([(dx - dr - box[0]) * k, (dy - dr - box[1]) * k,
                                 (dx + dr - box[0]) * k, (dy + dr - box[1]) * k], fill=255)
    img = glyph(size, box, color)
    tint = Image.new("RGBA", (n, n), dot_color)
    tint.putalpha(dot)
    img.alpha_composite(tint)
    return down(img, size)


def save(img, rel, **kw):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, **kw)
    print("wrote", rel)


def main():
    master = tile(1024)
    save(master, "res/icon.png")
    for name, s in (("32x32", 32), ("64x64", 64), ("128x128", 128), ("128x128@2x", 256)):
        save(tile(s), f"res/{name}.png")
    ico_sizes = [(s, s) for s in (16, 24, 32, 48, 64, 128, 256)]
    save(master, "res/icon.ico", sizes=ico_sizes)
    save(master, "flutter/windows/runner/resources/app_icon.ico", sizes=ico_sizes)
    save(master, "res/tray-icon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

    mac = tile(1024, radius=0.225, inset=100 / 1024)
    save(mac, "res/mac-icon.png")
    save(mac, "flutter/macos/Runner/AppIcon.icns")
    save(bare(60, (0, 0, 0, 255)), "res/mac-tray-dark-x2.png")
    save(bare(48, (0, 0, 0, 255)), "res/mac-tray-light-x2.png")

    res = "flutter/android/app/src/main/res"
    for dpi, s in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(tile(s, radius=0.22, inset=0.04), f"{res}/mipmap-{dpi}/ic_launcher.png")
        save(tile(s, shape="circle", inset=0.02, zoom=0.86), f"{res}/mipmap-{dpi}/ic_launcher_round.png")
        fg = s * 108 // 48
        save(down(glyph(fg, (50 - 76, 50 - 76, 50 + 76, 50 + 76)), fg), f"{res}/mipmap-{dpi}/ic_launcher_foreground.png")
        save(bare(s // 2, (255, 255, 255, 255)).convert("LA"), f"{res}/mipmap-{dpi}/ic_stat_logo.png")

    (ROOT / "flutter/assets/icon.svg").write_text(svg(20))
    save(bare(256, (255, 255, 255, 255), pad=1.0), "flutter/assets/mark_white.png")
    save(bare_two_tone(256, (245, 239, 234, 255), (242, 140, 107, 255)), "flutter/assets/mark_warm.png")
    print("wrote flutter/assets/icon.svg")

    if len(sys.argv) > 1:
        web = Path(sys.argv[1])
        (web / "icon.svg").write_text(svg(0))
        for s in (180, 192, 512):
            tile(s, shape="square", zoom=0.82).save(web / f"icon-{s}.png")
        print("wrote web icons in", web)


if __name__ == "__main__":
    main()
