#!/usr/bin/env python3
"""Regenerate every YC Remote icon from one drawing. Needs Pillow.

    python3 res/yc/gen_icons.py [web-dir]

Run from the repo root. The optional web-dir also refreshes the site icons.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

LIME = (201, 248, 95, 255)
INK = (16, 26, 2, 255)
SS = 4  # supersampling factor
ROOT = Path(__file__).resolve().parents[2]

SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
    '<rect width="32" height="32" rx="{rx}" fill="#c9f85f"/>'
    '<path d="M8 10h16v10H8z" fill="none" stroke="#101a02" stroke-width="2.3" stroke-linejoin="round"/>'
    '<path d="M12.5 24h7M16 20v4" stroke="#101a02" stroke-width="2.3" stroke-linecap="round"/>'
    '<path d="m13 13 5 2-2.2.8L15 18z" fill="#101a02"/></svg>\n'
)


def glyph_mask(size, box):
    """Alpha mask of the monitor glyph. `box` = (x0, y0, x1, y1) of the 32-unit grid shown."""
    n = size * SS
    k = n / (box[2] - box[0])
    px = lambda x: (x - box[0]) * k
    py = lambda y: (y - box[1]) * k
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    w = 1.15
    d.rounded_rectangle([px(8 - w), py(10 - w), px(24 + w), py(20 + w)], radius=w * k, fill=255)
    d.rectangle([px(8 + w), py(10 + w), px(24 - w), py(20 - w)], fill=0)
    for (xa, ya, xb, yb) in ((12.5, 24, 19.5, 24), (16, 20, 16, 24)):
        d.line([px(xa), py(ya), px(xb), py(yb)], fill=255, width=round(2 * w * k))
        for (x, y) in ((xa, ya), (xb, yb)):
            d.ellipse([px(x - w), py(y - w), px(x + w), py(y + w)], fill=255)
    d.polygon([(px(13), py(13)), (px(18), py(15)), (px(15.8), py(15.8)), (px(15), py(18))], fill=255)
    return m


def glyph(size, box, color):
    n = size * SS
    layer = Image.new("RGBA", (n, n), color)
    layer.putalpha(glyph_mask(size, box))
    return layer


def down(img, size):
    return img.resize((size, size), Image.LANCZOS)


def tile(size, radius=9 / 32, inset=0.0, shape="round-rect", zoom=1.0):
    """Lime tile with the glyph. inset = transparent margin as a fraction of the canvas."""
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    a, b = n * inset, n * (1 - inset)
    if shape == "circle":
        d.ellipse([a, a, b, b], fill=LIME)
    elif shape == "square":
        d.rectangle([a, a, b, b], fill=LIME)
    else:
        d.rounded_rectangle([a, a, b, b], radius=(b - a) * radius, fill=LIME)
    span = 32 * (1 / (1 - 2 * inset)) / zoom
    lo = 16 - span / 2
    img.alpha_composite(glyph(size, (lo, lo + 1, lo + span, lo + 1 + span), INK))
    return down(img, size)


def bare(size, color, pad=1.5):
    """Glyph alone, cropped close, for trays and notification icons."""
    lo, hi = 6.85 - pad, 25.15 + pad
    span = hi - lo
    cy = (8.85 + 25.15) / 2
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
        save(down(glyph(fg, (16 - 22, 17 - 22, 16 + 22, 17 + 22), INK), fg), f"{res}/mipmap-{dpi}/ic_launcher_foreground.png")
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
