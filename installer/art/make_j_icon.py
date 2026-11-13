# Amelia Job Search icon: a rainbow pixel J in the same style as the WAOV W (dark rounded tile, white outline).
# Run: python -I make_j_icon.py   (Pillow). Writes amelia.ico, amelia-256.png, amelia-32.png, amelia-preview.png here.
import os
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
J = ["XXXXXX",
     "XXXXXX",
     "...XX.",
     "...XX.",
     "...XX.",
     "XX.XX.",
     "XX.XX.",
     ".XXX.."]
ROW = [(255, 0, 64), (255, 128, 0), (255, 224, 0), (0, 208, 64), (0, 224, 255), (0, 96, 255), (0, 96, 255), (160, 0, 255)]
def icon(size=256):
    s = 256; im = Image.new("RGBA", (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([8, 8, s - 9, s - 9], radius=44, fill=(8, 16, 26, 255))
    c = 24; w = len(J[0]) * c; h = len(J) * c; ox = (s - w) // 2 + 6; oy = (s - h) // 2
    cells = [(x, y) for y, r in enumerate(J) for x, ch in enumerate(r) if ch == "X"]
    for x, y in cells:  # white outline first
        d.rectangle([ox + x * c - 8, oy + y * c - 8, ox + x * c + c + 7, oy + y * c + c + 7], fill=(255, 255, 255, 255))
    for x, y in cells:
        d.rectangle([ox + x * c, oy + y * c, ox + x * c + c - 1, oy + y * c + c - 1], fill=ROW[y] + (255,))
    return im if size == 256 else im.resize((size, size), Image.LANCZOS)
big = icon(256)
big.save(os.path.join(HERE, "amelia-256.png")); icon(32).save(os.path.join(HERE, "amelia-32.png"))
big.save(os.path.join(HERE, "amelia.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
pv = Image.new("RGBA", (256 + 48 + 32 + 16 + 64, 280), (128, 128, 128, 255)); x = 16
for sz in (256, 48, 32, 16):
    pv.alpha_composite(icon(sz), (x, 12)); x += sz + 8
pv.save(os.path.join(HERE, "amelia-preview.png")); print("ok")
