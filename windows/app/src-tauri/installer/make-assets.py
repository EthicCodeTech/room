#!/usr/bin/env python3
"""Draws the installer artwork (sidebar.bmp 164x314, header.bmp 150x57) in Room's Cinnabar look.
Needs Pillow and rsvg-convert. Run from this folder: python3 make-assets.py"""
import subprocess, tempfile, os
from PIL import Image, ImageDraw, ImageFont

OBSIDIAN, GRAPHITE, TEXT, MUTED, SINDOOR = (11, 11, 13), (22, 22, 26), (247, 247, 245), (161, 161, 170), (242, 84, 45)
FONTS = os.path.join(os.path.dirname(__file__), "..", "..", "ui", "fonts")
font = lambda name, size: ImageFont.truetype(os.path.join(FONTS, name), size)

def mark(px, color="#F7F7F5"):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="{px}" height="{px}"><path fill="{color}" d="M12 42V10a6 6 0 0 1 6-6h12a6 6 0 0 1 6 6v32h-4V10a2 2 0 0 0-2-2H18a2 2 0 0 0-2 2v32z"/><rect fill="{color}" x="6" y="40" width="36" height="4" rx="2"/><circle cx="28" cy="25" r="3.2" fill="#F2542D"/></svg>'
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f: f.write(svg)
    out = f.name + ".png"
    subprocess.run(["rsvg-convert", "-w", str(px * 4), "-h", str(px * 4), f.name, "-o", out], check=True)
    img = Image.open(out).convert("RGBA").resize((px, px), Image.LANCZOS)
    os.remove(f.name); os.remove(out)
    return img

def sidebar():
    W, H = 164, 314
    img = Image.new("RGB", (W, H), OBSIDIAN)
    d = ImageDraw.Draw(img)
    for y in range(H):                                   # a soft rise from obsidian to graphite
        t = y / H; d.line([(0, y), (W, y)], fill=tuple(int(OBSIDIAN[i] + (GRAPHITE[i] - OBSIDIAN[i]) * t) for i in range(3)))
    d.rectangle([0, 0, 3, H], fill=SINDOOR)              # sindoor edge
    m = mark(84); img.paste(m, ((W - 84) // 2 + 2, 52), m)
    d.text((W // 2 + 2, 160), "Room", font=font("Parkinsans_700Bold.ttf", 30), fill=TEXT, anchor="mm")
    for i, line in enumerate(["Know what it will do", "before it does it."]):
        d.text((W // 2 + 2, 190 + i * 15), line, font=font("Parkinsans_600SemiBold.ttf", 11), fill=MUTED, anchor="mm")
    d.line([(46, 232), (W - 42, 232)], fill=(42, 42, 48), width=1)
    d.text((W // 2 + 2, 290), "EthicCode", font=font("JetBrainsMono_500Medium.ttf", 10), fill=(138, 138, 147), anchor="mm")
    return img

def header():
    W, H = 150, 57
    img = Image.new("RGB", (W, H), OBSIDIAN)
    m = mark(36); img.paste(m, (W - 36 - 12, (H - 36) // 2), m)
    return img

here = os.path.dirname(os.path.abspath(__file__))
sidebar().save(os.path.join(here, "sidebar.bmp"), "BMP")      # 24-bit BMP, as NSIS requires
header().save(os.path.join(here, "header.bmp"), "BMP")
print("wrote sidebar.bmp and header.bmp")
