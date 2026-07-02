# Procedural asset generator for Tank Commander VR.
# Textures (PIL), audio (numpy -> 16-bit WAV), launcher icons.
# Run from project root:  python tools/gen_assets.py
import os, wave, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "tex")
AUD = os.path.join(ROOT, "assets", "audio")
os.makedirs(TEX, exist_ok=True)
os.makedirs(AUD, exist_ok=True)
rng = np.random.default_rng(7)

# ---------------------------------------------------------------- textures
def tileable_noise(size, octaves=4, base=8):
    """Seamless value noise in [0,1]."""
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = base * (2 ** o)
        if cells > size: break
        g = rng.random((cells, cells))
        big = np.array(Image.fromarray((g * 255).astype(np.uint8)).resize(
            (size, size), Image.BILINEAR), dtype=np.float64) / 255.0
        # enforce wrap by blending with rolled copy near edges
        big = (big + np.roll(big, size // 2, 0) + np.roll(big, size // 2, 1)) / 3.0
        out += big * amp
        total += amp
        amp *= 0.5
    out /= total
    out = (out - out.min()) / (np.ptp(out) + 1e-9)
    return out

def save_rgb(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(os.path.join(TEX, name))
    print("tex", name)

def colored_noise(size, c0, c1, octaves=4, base=8):
    n = tileable_noise(size, octaves, base)[..., None]
    c0, c1 = np.array(c0, dtype=np.float64), np.array(c1, dtype=np.float64)
    return c0 + (c1 - c0) * n

# terrain splat layers — high contrast + speckle so ground reads at VR scale
def speckled(size, c0, c1, octaves=5, base=8):
    img = colored_noise(size, c0, c1, octaves, base)
    spec = tileable_noise(size, 6, 32)[..., None]
    img = img * (0.82 + spec * 0.36)
    return img

save_rgb(speckled(256, (196, 164, 104), (240, 216, 158)), "sand.png")
save_rgb(speckled(256, (56, 88, 38), (112, 140, 62)), "grass.png")
save_rgb(speckled(256, (52, 50, 47), (118, 112, 102)), "rock.png")

# tank camo (olive blotches)
n1 = tileable_noise(256, 3, 4)
n2 = tileable_noise(256, 4, 8)
camo = np.zeros((256, 256, 3))
camo[:] = (96, 104, 66)
camo[n1 > 0.55] = (70, 78, 50)
camo[n2 > 0.62] = (120, 112, 76)
camo += (tileable_noise(256, 5, 16)[..., None] - 0.5) * 18
save_rgb(camo, "camo.png")

# cockpit interior metal (pale military green w/ wear)
m = colored_noise(256, (128, 138, 120), (148, 158, 138), 5, 12)
scr = tileable_noise(256, 6, 32)
m[scr > 0.78] *= 0.82
save_rgb(m, "metal.png")

# dark rubber/floor
save_rgb(colored_noise(256, (42, 42, 44), (58, 58, 60), 4, 16), "rubber.png")

# village building wall + roof
wall = colored_noise(256, (208, 196, 172), (232, 222, 200), 4, 8)
img = Image.fromarray(np.clip(wall, 0, 255).astype(np.uint8), "RGB")
d = ImageDraw.Draw(img)
for wy in (70, 160):
    for wx in (40, 120, 200):
        d.rectangle([wx - 18, wy - 24, wx + 18, wy + 24], fill=(52, 58, 70), outline=(90, 82, 66), width=4)
img.save(os.path.join(TEX, "building.png")); print("tex building.png")
save_rgb(colored_noise(256, (140, 78, 56), (168, 98, 70), 4, 10), "roof.png")

def radial(size, inner=1.0, outer=0.0, power=1.6, color=(255, 255, 255)):
    """RGBA radial falloff sprite."""
    y, x = np.mgrid[0:size, 0:size]
    r = np.sqrt((x - size / 2) ** 2 + (y - size / 2) ** 2) / (size / 2)
    a = np.clip(inner + (outer - inner) * np.clip(r, 0, 1) ** power, 0, 1)
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = color
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")

radial(128, 1, 0, 1.4, (235, 235, 235)).save(os.path.join(TEX, "smoke.png"))
radial(128, 1, 0, 0.55, (255, 240, 190)).save(os.path.join(TEX, "flash.png"))
radial(128, 0.75, 0, 2.2, (0, 0, 0)).save(os.path.join(TEX, "blob_shadow.png"))
print("tex smoke/flash/blob_shadow")

# aim reticle (diamond + dot)
ret = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
d = ImageDraw.Draw(ret)
c = 64
d.polygon([(c, 8), (120, c), (c, 120), (8, c)], outline=(255, 90, 40, 255), width=6)
d.ellipse([c - 7, c - 7, c + 7, c + 7], fill=(255, 90, 40, 255))
ret.save(os.path.join(TEX, "reticle.png")); print("tex reticle.png")

# gauge faces (270-degree dial, labeled)
def gauge(name, label, maxval, redline_frac=None):
    s = 256
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, s - 4, s - 4], fill=(24, 26, 24, 255), outline=(180, 185, 175, 255), width=6)
    n_ticks = 9
    for i in range(n_ticks):
        frac = i / (n_ticks - 1)
        ang = math.radians(135 + 270 * frac)
        x0 = s / 2 + math.cos(ang) * 96; y0 = s / 2 + math.sin(ang) * 96
        x1 = s / 2 + math.cos(ang) * 112; y1 = s / 2 + math.sin(ang) * 112
        col = (232, 90, 60, 255) if (redline_frac and frac >= redline_frac) else (220, 224, 214, 255)
        d.line([x0, y0, x1, y1], fill=col, width=7)
        v = int(maxval * frac)
        tx = s / 2 + math.cos(ang) * 74; ty = s / 2 + math.sin(ang) * 74
        d.text((tx, ty), str(v), fill=(200, 204, 194, 255), anchor="mm")
    d.text((s / 2, s * 0.70), label, fill=(190, 195, 185, 255), anchor="mm")
    img.save(os.path.join(TEX, name)); print("tex", name)

gauge("gauge_speed.png", "KM/H", 40)
gauge("gauge_rpm.png", "RPM x100", 32, redline_frac=0.8)
gauge("gauge_temp.png", "TEMP", 120, redline_frac=0.75)
gauge("gauge_fuel.png", "FUEL", 100)

# launcher icons: tank silhouette on olive
def tank_icon(size, pad_frac=0.18, bg=(52, 58, 40)):
    img = Image.new("RGBA", (size, size), bg + (255,))
    d = ImageDraw.Draw(img)
    p = size * pad_frac
    w = size - 2 * p
    # hull
    d.rounded_rectangle([p, size * 0.52, p + w, size * 0.68], radius=size * 0.03, fill=(150, 158, 120, 255))
    # tracks
    d.rounded_rectangle([p - size * 0.02, size * 0.62, p + w + size * 0.02, size * 0.78],
                        radius=size * 0.08, fill=(40, 42, 36, 255), outline=(150, 158, 120, 255), width=max(2, size // 90))
    # turret
    d.ellipse([size * 0.38, size * 0.36, size * 0.62, size * 0.56], fill=(150, 158, 120, 255))
    # barrel
    d.rectangle([size * 0.58, size * 0.42, size * 0.94, size * 0.47], fill=(150, 158, 120, 255))
    # muzzle brake
    d.rectangle([size * 0.88, size * 0.40, size * 0.94, size * 0.49], fill=(200, 120, 60, 255))
    return img

tank_icon(128).convert("RGB").save(os.path.join(ROOT, "icon.png"))
tank_icon(192).convert("RGB").save(os.path.join(ROOT, "icon_192.png"))
fg = tank_icon(432, pad_frac=0.30, bg=(0, 0, 0))
fg_arr = np.array(fg); mask = (fg_arr[..., :3] == np.array((0, 0, 0))).all(-1)
fg_arr[mask, 3] = 0
Image.fromarray(fg_arr, "RGBA").save(os.path.join(ROOT, "icon_fg_432.png"))
Image.new("RGB", (432, 432), (52, 58, 40)).save(os.path.join(ROOT, "icon_bg_432.png"))
print("icons done")

# ---------------------------------------------------------------- audio
SR = 22050

def save_wav(name, x, vol=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) + 1e-9
    x = x / peak * vol
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(AUD, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wav", name, f"{len(x)/SR:.2f}s")

def t_axis(dur): return np.arange(int(SR * dur)) / SR

def env_exp(dur, tau): return np.exp(-t_axis(dur) / tau)

def crossfade_loop(x, fade=0.08):
    # overlap-add the tail into the head so the loop point is continuous
    n = int(SR * fade)
    y = x[:-n].copy()
    ramp = np.linspace(0, 1, n)
    y[:n] = y[:n] * ramp + x[-n:] * (1 - ramp)
    return y

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc); y[i] = acc
    return y

def noise(dur): return rng.standard_normal(int(SR * dur))

# engine idle loop: 55 Hz saw + harmonics + rumble noise, mild wobble
dur = 2.0; t = t_axis(dur)
wob = 1.0 + 0.03 * np.sin(2 * np.pi * 3 * t)
f0 = 55.0
sig = np.zeros_like(t)
for h, a in ((1, 1.0), (2, 0.55), (3, 0.32), (4, 0.18), (6, 0.1)):
    ph = 2 * np.pi * f0 * h * np.cumsum(wob) / SR
    sig += a * ((ph / np.pi) % 2 - 1)  # saw
sig += lowpass(noise(dur), 0.08) * 0.8
save_wav("engine_loop.wav", crossfade_loop(sig), 0.55)

# track clatter loop (played when moving, pitch with speed)
dur = 1.5; t = t_axis(dur)
sig = lowpass(noise(dur), 0.25) * 0.4
for i in range(int(dur * 14)):  # link impacts
    at = int(i / 14 * SR) + rng.integers(0, 300)
    if at + 900 < len(sig):
        ping = np.sin(2 * np.pi * rng.uniform(700, 1400) * t_axis(0.04)) * env_exp(0.04, 0.012)
        sig[at:at + len(ping)] += ping * rng.uniform(0.3, 0.8)
save_wav("tracks_loop.wav", crossfade_loop(sig), 0.5)

# turret motor hum loop
dur = 1.2; t = t_axis(dur)
sig = 0.6 * np.sin(2 * np.pi * 120 * t) + 0.3 * np.sin(2 * np.pi * 243 * t) + lowpass(noise(dur), 0.15) * 0.25
save_wav("turret_loop.wav", crossfade_loop(sig), 0.4)

# cannon: sub thump sweep + brown noise burst
dur = 1.4; t = t_axis(dur)
sweep = np.sin(2 * np.pi * np.cumsum(np.linspace(90, 28, len(t))) / SR) * env_exp(dur, 0.22)
br = np.cumsum(noise(dur)); br /= np.max(np.abs(br) + 1e-9)
sig = sweep * 1.2 + br * env_exp(dur, 0.1) * 0.9 + noise(dur) * env_exp(dur, 0.03) * 0.7
save_wav("cannon.wav", sig, 0.95)

# breech reload: two metal clunks + slide
def clunk(fr):
    d2 = 0.12
    s = np.zeros(int(SR * d2))
    for f, a in ((fr, 1.0), (fr * 2.7, 0.5), (fr * 4.2, 0.25)):
        s += a * np.sin(2 * np.pi * f * t_axis(d2)) * env_exp(d2, 0.02)
    return s
sig = np.zeros(int(SR * 0.7))
c1 = clunk(320); sig[:len(c1)] += c1
slide = lowpass(noise(0.25), 0.3) * env_exp(0.25, 0.1) * 0.5
sig[int(0.18 * SR):int(0.18 * SR) + len(slide)] += slide
c2 = clunk(240); sig[int(0.45 * SR):int(0.45 * SR) + len(c2)] += c2 * 1.2
save_wav("reload.wav", sig, 0.8)

# small UI: click, switch snap
sig = np.sin(2 * np.pi * 1800 * t_axis(0.03)) * env_exp(0.03, 0.006)
save_wav("click.wav", sig, 0.5)
sig = np.zeros(int(SR * 0.09))
a = np.sin(2 * np.pi * 900 * t_axis(0.03)) * env_exp(0.03, 0.008)
b = np.sin(2 * np.pi * 500 * t_axis(0.05)) * env_exp(0.05, 0.01)
sig[:len(a)] += a; sig[int(0.035 * SR):int(0.035 * SR) + len(b)] += b
save_wav("switch.wav", sig, 0.6)

# rocket whoosh
dur = 1.0
n = noise(dur)
bp = lowpass(n, 0.5) - lowpass(n, 0.12)
sig = bp * (0.2 + 0.8 * np.linspace(1, 0, int(SR * dur)) ** 1.5)
sig += np.sin(2 * np.pi * np.cumsum(np.linspace(160, 90, int(SR * dur))) / SR) * env_exp(dur, 0.3) * 0.3
save_wav("rocket.wav", sig, 0.8)

# explosions
for name, dur, tau, v in (("explosion.wav", 1.6, 0.25, 0.95), ("explosion_far.wav", 1.8, 0.4, 0.55)):
    br = np.cumsum(noise(dur)); br /= np.max(np.abs(br) + 1e-9)
    sig = br * env_exp(dur, tau) + lowpass(noise(dur), 0.2) * env_exp(dur, tau * 0.5) * 0.6
    sig += np.sin(2 * np.pi * np.cumsum(np.linspace(70, 24, len(sig))) / SR) * env_exp(dur, tau) * 0.8
    if "far" in name: sig = lowpass(sig, 0.12)
    save_wav(name, sig, v)

# machine gun single shot
sig = noise(0.07) * env_exp(0.07, 0.012) + np.sin(2 * np.pi * 220 * t_axis(0.07)) * env_exp(0.07, 0.02) * 0.5
save_wav("mg.wav", sig, 0.6)

# hull hit + ricochet
sig = clunk(180) * 1.2 + noise(0.12) * env_exp(0.12, 0.03) * 0.6
save_wav("hit.wav", sig, 0.85)
dur = 0.5
f = np.linspace(2400, 700, int(SR * dur))
sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(dur, 0.1)
save_wav("ricochet.wav", sig, 0.45)

# alarm loop (two-tone)
dur = 1.0; t = t_axis(dur)
f = np.where((t % 0.5) < 0.25, 780, 585)
sig = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.6
sig = lowpass(sig, 0.35)
save_wav("alarm.wav", crossfade_loop(sig, 0.02), 0.45)

# wind ambient loop
dur = 4.0
n = noise(dur)
sig = lowpass(n, 0.06) + (lowpass(n, 0.25) - lowpass(n, 0.06)) * 0.3
lfo = 0.6 + 0.4 * np.sin(2 * np.pi * 0.3 * t_axis(dur))
save_wav("wind_loop.wav", crossfade_loop(sig * lfo, 0.3), 0.5)

# plane prop drone loop
dur = 1.6; t = t_axis(dur)
sig = np.zeros_like(t)
for h, a in ((1, 1.0), (2, 0.6), (3, 0.4), (5, 0.2)):
    sig += a * np.sin(2 * np.pi * 108 * h * t + 0.3 * np.sin(2 * np.pi * 7 * t))
sig += lowpass(noise(dur), 0.2) * 0.3
save_wav("plane_loop.wav", crossfade_loop(sig), 0.5)

# starter crank -> engine catch
dur = 1.6; t = t_axis(dur)
crank = np.sign(np.sin(2 * np.pi * np.linspace(9, 14, len(t)) * t)) * 0.3
crank *= lowpass(np.abs(noise(dur)), 0.2) + 0.4
catch = np.zeros_like(t)
ci = int(1.05 * SR)
f0 = 55
ph = 2 * np.pi * f0 * np.cumsum(np.linspace(0.4, 1.0, len(t) - ci)) / SR
catch[ci:] = ((ph / np.pi) % 2 - 1) * np.linspace(0, 1, len(t) - ci)
sig = crank * np.concatenate([np.ones(ci), np.linspace(1, 0, len(t) - ci)]) + catch
save_wav("ignition.wav", sig, 0.7)

# game over + wave fanfare
dur = 1.8; t = t_axis(dur)
sig = np.zeros_like(t)
for i, f in enumerate((392, 330, 262, 196)):
    st = int(i * 0.35 * SR); seg = t_axis(0.5)
    tone = np.sin(2 * np.pi * f * seg) * env_exp(0.5, 0.2)
    sig[st:st + len(tone)] += tone
save_wav("gameover.wav", sig, 0.6)
dur = 1.0
sig = np.zeros(int(SR * dur))
for i, f in enumerate((330, 440, 554)):
    st = int(i * 0.18 * SR); seg = t_axis(0.45)
    tone = np.sin(2 * np.pi * f * seg) * env_exp(0.45, 0.18)
    sig[st:st + len(tone)] += tone
save_wav("wave.wav", sig, 0.55)

print("ALL ASSETS DONE")
