# Round-3 audio: weather, silly-mode SFX, radio static. numpy synthesis.
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUD = os.path.join(ROOT, "assets", "audio")
SR = 22050
rng = np.random.default_rng(23)

def save(name, x, vol=0.85):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) + 1e-9
    data = (x / peak * vol * 32767).astype(np.int16)
    with wave.open(os.path.join(AUD, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wav", name, f"{len(x)/SR:.2f}s")

def n_samp(d): return int(SR * d)
def t_axis(d): return np.arange(n_samp(d)) / SR
def env_exp(d, tau): return np.exp(-t_axis(d) / tau)
def noise(d): return rng.standard_normal(n_samp(d))

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y

def loopify(x, fade=0.25):
    n = n_samp(fade)
    y = x[:-n].copy()
    r = np.linspace(0, 1, n)
    y[:n] = y[:n] * r + x[-n:] * (1 - r)
    return y

# rain loop (dense high patter + low wash)
d = 4.0
x = (noise(d) - lowpass(noise(d), 0.5)) * 0.5 + lowpass(noise(d), 0.10) * 0.8
drops = np.zeros(n_samp(d))
for i in range(240):
    at = rng.integers(0, n_samp(d) - 400)
    dd = 0.008
    tick = noise(dd) * env_exp(dd, 0.002)
    drops[at:at + len(tick)] += tick * rng.uniform(0.2, 0.9)
save("rain_loop.wav", loopify(x * 0.7 + drops), 0.55)

# thunder x2
for i, nm in enumerate(["thunder1.wav", "thunder2.wav"]):
    d = 3.2
    br = np.cumsum(noise(d)); br /= np.max(np.abs(br) + 1e-9)
    x = br * env_exp(d, 0.7 + i * 0.3)
    x += lowpass(noise(d), 0.05) * env_exp(d, 0.9) * 1.2
    crack = noise(0.25) * env_exp(0.25, 0.03)
    x[: len(crack)] += crack * (1.4 - i * 0.6)
    save(nm, lowpass(x, 0.35), 0.9)

# wind gust
d = 3.0
n = noise(d)
x = (lowpass(n, 0.12) - lowpass(n, 0.03))
g = np.sin(np.linspace(0, np.pi, n_samp(d))) ** 2
save("wind_gust.wav", x * g, 0.6)

# tornado roar loop
d = 3.0
n = noise(d)
x = lowpass(n, 0.06) * 1.4 + (lowpass(n, 0.3) - lowpass(n, 0.1)) * 0.7
w = 1.0 + 0.4 * np.sin(2 * np.pi * 0.7 * t_axis(d)) + 0.2 * np.sin(2 * np.pi * 2.3 * t_axis(d))
save("tornado_loop.wav", loopify(x * w), 0.85)

# volcano rumble loop + eruption blast
d = 3.0
x = lowpass(noise(d), 0.04) * 1.5
x += np.sin(2 * np.pi * 31 * t_axis(d)) * 0.5 * (1 + 0.4 * np.sin(2 * np.pi * 0.5 * t_axis(d)))
save("volcano_loop.wav", loopify(x), 0.85)
d = 2.5
br = np.cumsum(noise(d)); br /= np.max(np.abs(br) + 1e-9)
x = br * env_exp(d, 0.5) + lowpass(noise(d), 0.15) * env_exp(d, 0.4)
save("eruption.wav", x, 0.95)

# underwater bubbles loop + muffled ambience
d = 3.5
x = lowpass(noise(d), 0.05) * 0.7
for i in range(40):
    at = rng.integers(0, n_samp(d) - 2000)
    bd = rng.uniform(0.03, 0.09)
    f = np.linspace(rng.uniform(300, 700), rng.uniform(800, 1600), n_samp(bd))
    bub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(bd, bd / 3)
    x[at:at + len(bub)] += bub * rng.uniform(0.1, 0.35)
save("bubbles_loop.wav", loopify(x), 0.5)

# balloon squeak + pop-confetti
d = 0.5
f = 900 + 500 * np.sin(2 * np.pi * 9 * t_axis(d)) * np.linspace(1, 0.3, n_samp(d))
x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(d, 0.18)
save("squeak.wav", x, 0.5)
d = 0.6
x = noise(0.02) * 3.0
x = np.concatenate([x, noise(d - 0.02) * env_exp(d - 0.02, 0.05) * 0.6])
save("pop.wav", x, 0.8)

# paint splat
d = 0.35
x = lowpass(noise(d), 0.4) * env_exp(d, 0.05)
x += np.sin(2 * np.pi * np.linspace(160, 60, n_samp(d)) * t_axis(d)) * env_exp(d, 0.06) * 0.7
save("splat.wav", x, 0.7)

# radio static loop + tuning blip
d = 1.6
x = noise(d) * 0.5 + (noise(d) - lowpass(noise(d), 0.6)) * 0.3
crackle = np.zeros(n_samp(d))
for i in range(14):
    at = rng.integers(0, n_samp(d) - 900)
    cd = 0.02
    c = noise(cd) * env_exp(cd, 0.004)
    crackle[at:at + len(c)] += c * rng.uniform(0.5, 1.5)
save("static_loop.wav", loopify(x * 0.5 + crackle), 0.4)

# referee whistle (gym!) + sneaker squeak + boing (low-g)
d = 0.7
f = 2800 + 60 * np.sign(np.sin(2 * np.pi * 38 * t_axis(d)))
x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(t_axis(d) * 30, 1.0) * env_exp(d, 0.4)
save("whistle.wav", x, 0.6)
d = 0.3
f = np.linspace(1400, 2600, n_samp(d))
x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(d, 0.1) * (1 + 0.5 * np.sin(2 * np.pi * 40 * t_axis(d)))
save("sneaker.wav", x, 0.45)
d = 0.5
f = 130 * np.exp(-t_axis(d) * 3.0) + 60
x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_exp(d, 0.14)
x += np.sin(2 * np.pi * np.cumsum(f * 2.02) / SR) * env_exp(d, 0.1) * 0.4
save("boing.wav", x, 0.7)

# bounce thud for low-g tank landings
d = 0.3
x = np.sin(2 * np.pi * np.linspace(90, 45, n_samp(d)) * t_axis(d)) * env_exp(d, 0.07)
save("thud.wav", x, 0.7)

# DAD FM jingle bed (bright major stinger, C major — distinct from the Dm score)
NOTE = {"C3": 130.81, "E3": 164.81, "G3": 196.0, "C4": 261.63, "E4": 329.63, "G4": 392.0}
d = 2.4
x = np.zeros(n_samp(d))
for k, nm in enumerate(["C3", "E3", "G3", "C4", "E4", "G4"]):
    nd = 1.4
    tone = np.sin(2 * np.pi * NOTE[nm] * t_axis(nd)) * env_exp(nd, 0.4)
    at = n_samp(k * 0.1)
    x[at:at + len(tone)] += tone * 0.5
save("jingle.wav", x, 0.6)

print("AUDIO2 DONE")
