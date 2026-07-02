# Wild-pass assets: beach + toybox music, carpet + wallpaper + lava textures.
import os, wave, math
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUD = os.path.join(ROOT, "assets", "audio")
TEX = os.path.join(ROOT, "assets", "tex")
SR = 22050
rng = np.random.default_rng(31)

def save_wav(name, x, vol=0.8):
    x = np.asarray(x, dtype=np.float64)
    data = (x / (np.max(np.abs(x)) + 1e-9) * vol * 32767).astype(np.int16)
    with wave.open(os.path.join(AUD, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wav", name)

def n_samp(d): return int(SR * d)
def t_axis(d): return np.arange(n_samp(d)) / SR
def env_exp(d, tau): return np.exp(-t_axis(d) / tau)

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y

def loopify(x, fade=0.3):
    n = n_samp(fade)
    y = x[:-n].copy()
    r = np.linspace(0, 1, n)
    y[:n] = y[:n] * r + x[-n:] * (1 - r)
    return y

def place(buf, x, at):
    i = n_samp(at); j = min(i + len(x), len(buf))
    if i < len(buf): buf[i:j] += x[:j - i]

NOTE = {"C3":130.8,"D3":146.8,"E3":164.8,"G3":196.0,"A3":220.0,"C4":261.6,"D4":293.7,
        "E4":329.6,"G4":392.0,"A4":440.0,"C5":523.3,"E5":659.3,"G5":784.0}

# ---- beach: happy sunny calypso-ish loop (C major pentatonic, steel-pan pluck)
BPM = 108.0; BEAT = 60.0 / BPM; BARS = 8
DUR = BARS * BEAT * 4; N = n_samp(DUR)
buf = np.zeros(N)
def pan(freq, d=0.5):
    t = t_axis(d)
    x = np.sin(2*np.pi*freq*t) + 0.6*np.sin(2*np.pi*freq*2.01*t) + 0.25*np.sin(2*np.pi*freq*3.98*t)
    return x * env_exp(d, 0.12)
mel = ["C4","E4","G4","A4","G4","E4","D4","C4","E4","G4","C5","A4","G4","E4","G4","C4"]
for k, nm in enumerate(mel * 2):
    place(buf, pan(NOTE[nm]) * 0.5, k * BEAT)
bass = ["C3","G3","A3","G3"] * (BARS // 2)
for k, nm in enumerate(bass * 2):
    t = t_axis(BEAT * 1.9)
    x = np.sin(2*np.pi*NOTE[nm]*t) * env_exp(BEAT*1.9, 0.4)
    place(buf, x * 0.45, k * BEAT * 2)
# shaker
for k in range(int(DUR / (BEAT/2))):
    d = 0.05
    x = (rng.standard_normal(n_samp(d)) - lowpass(rng.standard_normal(n_samp(d)), 0.5)) * env_exp(d, 0.02)
    place(buf, x * (0.35 if k % 2 else 0.2), k * BEAT / 2)
save_wav("music_beach.wav", loopify(buf), 0.6)

# ---- toybox: music-box lullaby (slow, sine bells)
BPM2 = 76.0; B2 = 60.0 / BPM2
DUR2 = 8 * B2 * 4; N2 = n_samp(DUR2)
buf = np.zeros(N2)
lull = ["E5","C5","G4","C5","E5","G5","E5","C5","D4","G4","E4","G4","C5","E4","G4","C4"]
for k, nm in enumerate(lull * 2):
    d = 1.2
    t = t_axis(d)
    x = np.sin(2*np.pi*NOTE[nm]*2*t) * env_exp(d, 0.35) + 0.3*np.sin(2*np.pi*NOTE[nm]*4*t) * env_exp(d, 0.2)
    place(buf, x * 0.4, k * B2)
save_wav("music_toy.wav", loopify(buf), 0.55)

# ---- lava bubble loop
d = 3.0
x = lowpass(rng.standard_normal(n_samp(d)), 0.04) * 1.2
for i in range(20):
    at = rng.uniform(0, 2.6)
    bd = rng.uniform(0.08, 0.2)
    f = np.linspace(rng.uniform(80, 160), rng.uniform(40, 90), n_samp(bd))
    bub = np.sin(2*np.pi*np.cumsum(f)/SR) * env_exp(bd, bd/2.5)
    place(x, bub * rng.uniform(0.3, 0.7), at)
save_wav("lava_loop.wav", loopify(x), 0.7)

# ---- ocean waves loop
d = 6.0
n = rng.standard_normal(n_samp(d))
x = lowpass(n, 0.08)
swell = 0.4 + 0.6 * (0.5 + 0.5*np.sin(2*np.pi*t_axis(d)/3.0))
save_wav("waves_loop.wav", loopify(x * swell, 0.8), 0.55)

# ---- carpet texture (baby room floor)
S = 512
base = np.full((S, S, 3), (95.0, 130.0, 170.0))
base += rng.normal(0, 9, (S, S, 3))
# fuzzy speckle
sp = rng.random((S, S)) > 0.5
base[sp] += 12
img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")
d2 = ImageDraw.Draw(img)
for i in range(6):  # road-rug roads! every baby room rug has roads
    y = 40 + i * 80
    d2.line([0, y, S, y], fill=(70, 70, 75), width=18)
    for x in range(0, S, 40):
        d2.line([x, y, x + 20, y], fill=(230, 220, 90), width=3)
img.save(os.path.join(TEX, "carpet.png"))
print("tex carpet.png")

# ---- wallpaper (baby room walls): stripes + duckies
img = Image.new("RGB", (256, 256), (235, 228, 205))
d2 = ImageDraw.Draw(img)
for x in range(0, 256, 64):
    d2.rectangle([x, 0, x + 32, 256], fill=(215, 225, 240))
for pos in [(48, 60), (176, 150), (110, 220)]:
    x, y = pos
    d2.ellipse([x, y, x + 26, y + 20], fill=(250, 210, 60))
    d2.ellipse([x + 16, y - 12, x + 34, y + 6], fill=(250, 210, 60))
    d2.polygon([(x + 32, y - 4), (x + 42, y - 1), (x + 32, y + 3)], fill=(240, 130, 50))
img.save(os.path.join(TEX, "wallpaper.png"))
print("tex wallpaper.png")

print("WILD ASSETS DONE")
