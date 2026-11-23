#!/usr/bin/env python3
"""Regenerate every OpenDesk icon from one drawing. Needs Pillow.

    python3 res/yc/gen_icons.py [web-dir]

Run from the repo root. The optional web-dir also refreshes the site icons.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

BG_TOP = (24, 27, 38, 255)
BG_BOT = (9, 10, 15, 255)
PAPER = (244, 246, 255, 255)
STAR_A = (92, 141, 255)
STAR_B = (178, 132, 255)
SS = 4  # supersampling factor
ROOT = Path(__file__).resolve().parents[2]

STAR = (23.6, 9.4)  # centre of the spark, on the 32-unit grid
STAR_R = 5.4

SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
    '<defs><linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#181b26"/>'
    '<stop offset="1" stop-color="#090a0f"/></linearGradient>'
    '<linearGradient id="s" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5c8dff"/>'
    '<stop offset="1" stop-color="#b284ff"/></linearGradient></defs>'
    '<rect width="32" height="32" rx="{rx}" fill="url(#b)"/>'
    '<path d="M16.6 9H9.6A2.6 2.6 0 0 0 7 11.6v8.3a2.6 2.6 0 0 0 2.6 2.6h11.8a2.6 2.6 0 0 0 2.6-2.6v-3.3" '
    'fill="none" stroke="#f4f6ff" stroke-width="2.3" stroke-linecap="round"/>'
    '<path d="M12.4 26h6.2" stroke="#f4f6ff" stroke-width="2.3" stroke-linecap="round"/>'
    '<path d="M23.6 4c.5 3.2 2.2 4.9 5.4 5.4-3.2.5-4.9 2.2-5.4 5.4-.5-3.2-2.2-4.9-5.4-5.4 3.2-.5 4.9-2.2 5.4-5.4z" '
    'fill="url(#s)"/></svg>\n'
)


def _grid(size, box):
    n = size * SS
    k = n / (box[2] - box[0])
    return n, k, (lambda x: (x - box[0]) * k), (lambda y: (y - box[1]) * k)


def screen_mask(size, box):
    """Monitor outline, left open where the spark sits."""
    n, k, px, py = _grid(size, box)
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    w = 1.15
    d.rounded_rectangle([px(7 - w), py(9 - w), px(24 + w), py(22.5 + w)], radius=(2.6 + w) * k, fill=255)
    d.rounded_rectangle([px(7 + w), py(9 + w), px(24 - w), py(22.5 - w)], radius=max(0.1, 2.6 - w) * k, fill=0)
    gap = STAR_R + 1.9
    d.ellipse([px(STAR[0] - gap), py(STAR[1] - gap), px(STAR[0] + gap), py(STAR[1] + gap)], fill=0)
    d.line([px(12.4), py(26), px(18.6), py(26)], fill=255, width=round(2 * w * k))
    for x in (12.4, 18.6):
        d.ellipse([px(x - w), py(26 - w), px(x + w), py(26 + w)], fill=255)
    return m


def star_mask(size, box):
    """Four-point spark with concave sides."""
    import math
    n, k, px, py = _grid(size, box)
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    pts = []
    steps = 24
    for q in range(4):
        a0 = math.pi / 2 * q - math.pi / 2
        a1 = a0 + math.pi / 2
        p0 = (STAR[0] + STAR_R * math.cos(a0), STAR[1] + STAR_R * math.sin(a0))
        p1 = (STAR[0] + STAR_R * math.cos(a1), STAR[1] + STAR_R * math.sin(a1))
        c = (STAR[0] + 0.16 * STAR_R * math.cos((a0 + a1) / 2), STAR[1] + 0.16 * STAR_R * math.sin((a0 + a1) / 2))
        for i in range(steps):
            t = i / steps
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t ** 2 * p1[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t ** 2 * p1[1]
            pts.append((px(x), py(y)))
    d.polygon(pts, fill=255)
    return m


def gradient(n, c0, c1, diagonal=False):
    g = Image.linear_gradient("L").resize((n, n))
    if diagonal:
        g = Image.blend(g, g.rotate(90), 0.5)
    a = Image.new("RGBA", (n, n), tuple(c0[:3]) + (255,))
    b = Image.new("RGBA", (n, n), tuple(c1[:3]) + (255,))
    return Image.composite(b, a, g)


def glyph(size, box, color=None):
    """The mark. `color` paints it flat (trays, notifications); None keeps the two-tone version."""
    n = size * SS
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    paper = Image.new("RGBA", (n, n), color or PAPER)
    paper.putalpha(screen_mask(size, box))
    out.alpha_composite(paper)
    if color:
        star = Image.new("RGBA", (n, n), color)
    else:
        # Fit the gradient to the spark so both of its colours show at any zoom.
        _, k, px, py = _grid(size, box)
        side = max(2, round(2 * STAR_R * k))
        star = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        star.paste(gradient(side, STAR_A, STAR_B, diagonal=True), (round(px(STAR[0] - STAR_R)), round(py(STAR[1] - STAR_R))))
    star.putalpha(star_mask(size, box))
    out.alpha_composite(star)
    return out


def down(img, size):
    return img.resize((size, size), Image.LANCZOS)


def tile(size, radius=9 / 32, inset=0.0, shape="round-rect", zoom=1.0):
    """Dark tile with the mark. inset = transparent margin as a fraction of the canvas."""
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
    img = gradient(n, BG_TOP, BG_BOT)
    img.putalpha(mask)
    span = 32 * (1 / (1 - 2 * inset)) / zoom
    lo = 16 - span / 2
    img.alpha_composite(glyph(size, (lo, lo, lo + span, lo + span)))
    return down(img, size)


def bare(size, color, pad=1.2):
    """Mark alone, cropped close, for trays and notification icons."""
    lo, hi = 5.85 - pad, 29 + pad
    span = hi - lo
    cy = (4 + 27.15) / 2
    return down(glyph(size, (lo, cy - span / 2, hi, cy + span / 2), color), size)


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
        save(down(glyph(fg, (16 - 24, 16 - 24, 16 + 24, 16 + 24)), fg), f"{res}/mipmap-{dpi}/ic_launcher_foreground.png")
        save(bare(s // 2, (255, 255, 255, 255)).convert("LA"), f"{res}/mipmap-{dpi}/ic_stat_logo.png")

    (ROOT / "flutter/assets/icon.svg").write_text(SVG.format(rx=9))
    print("wrote flutter/assets/icon.svg")

    if len(sys.argv) > 1:
        web = Path(sys.argv[1])
        (web / "icon.svg").write_text(SVG.format(rx=0))
        for s in (180, 192, 512):
            tile(s, shape="square", zoom=0.82).save(web / f"icon-{s}.png")
        print("wrote web icons in", web)


if __name__ == "__main__":
    main()
