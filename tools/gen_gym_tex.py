# Gymnasium textures: wood court floor with lines, corrugated cardboard.
import os
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "tex")
rng = np.random.default_rng(9)

# ---- court floor: one giant non-tiling texture mapped across the arena.
# BOLD features only — this is viewed from 100+ m at grazing angles, so
# subtle plank grain mips away. Big bright planks, fat lines.
S = 1024
img = Image.new("RGB", (S, S), (222, 178, 116))
d = ImageDraw.Draw(img)
for y in range(0, S, 26):
    shade = int(rng.uniform(-22, 22))
    d.rectangle([0, y, S, y + 26], fill=(222 + shade, 178 + shade, 116 + shade // 2))
    d.line([0, y, S, y], fill=(170, 128, 74), width=3)
LINE = (255, 255, 255)
RED = (215, 55, 45)
BLUE = (35, 85, 200)
# gym is 236m across in a 512m texture: court occupies the middle ~440px
C0, C1 = S // 2 - 220, S // 2 + 220
d.rectangle([C0, C0, C1, C1], outline=LINE, width=22)
d.line([C0, S // 2, C1, S // 2], fill=LINE, width=22)
d.ellipse([S // 2 - 80, S // 2 - 80, S // 2 + 80, S // 2 + 80], outline=RED, width=22)
d.ellipse([S // 2 - 26, S // 2 - 26, S // 2 + 26, S // 2 + 26], fill=BLUE)
for top in (True, False):
    ky0 = C0 if top else C1 - 130
    ky1 = C0 + 130 if top else C1
    d.rectangle([S // 2 - 70, ky0, S // 2 + 70, ky1], outline=BLUE, width=18)
    cy = ky1 if top else ky0
    d.arc([S // 2 - 70, cy - 70, S // 2 + 70, cy + 70], 0 if top else 180, 180 if top else 360, fill=BLUE, width=18)
img.save(os.path.join(TEX, "court.png"))
print("tex court.png")

# ---- cardboard: corrugated + packing tape
S2 = 256
base = np.full((S2, S2, 3), (185.0, 150.0, 105.0))
for y in range(S2):
    base[y] += np.sin(y * 1.1) * 7  # corrugation ridges
base += rng.normal(0, 5, (S2, S2, 3))
img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")
d = ImageDraw.Draw(img)
d.rectangle([0, 100, S2, 130], fill=(210, 200, 180))       # packing tape
d.rectangle([0, 104, S2, 108], fill=(190, 180, 160))
d.line([40, 0, 40, S2], fill=(120, 95, 65), width=3)        # box edge
d.text((150, 180), "THIS SIDE UP", fill=(90, 70, 50))
d.text((60, 40), ">>", fill=(90, 70, 50))
img.save(os.path.join(TEX, "cardboard.png"))
print("tex cardboard.png")
print("GYM TEX DONE")
