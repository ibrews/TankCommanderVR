# Round-N audio: pickup consumables (coffee sip/steam, energy-drink
# gulp/fizz). numpy synthesis, same idiom as gen_audio2.py — one wav per
# NAMES entry in scripts/audio.gd, no imported samples.
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUD = os.path.join(ROOT, "assets", "audio")
SR = 22050
rng = np.random.default_rng(41)

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

def highpass(x, alpha):
    return x - lowpass(x, alpha)

# ---- gulp: three throat-swallow pulses, descending pitch, dry mouth-cavity
# resonance (narrow bandpass noise) under each pulse.
d = 0.55
sig = np.zeros(n_samp(d))
for i, (at_t, f0, amt) in enumerate([(0.02, 260, 1.0), (0.20, 210, 0.85), (0.38, 175, 0.7)]):
    dd = 0.11
    pulse = np.sin(2 * np.pi * f0 * t_axis(dd)) * env_exp(dd, 0.03)
    gurgle = (lowpass(noise(dd), 0.35) - lowpass(noise(dd), 0.12)) * env_exp(dd, 0.02) * 0.5
    at = n_samp(at_t)
    seg = (pulse + gurgle) * amt
    sig[at:at + len(seg)] += seg[:max(0, len(sig) - at)]
save("gulp.wav", sig, 0.75)

# ---- fizz: bright hiss burst that decays under a soft crackle layer —
# carbonation escaping right after the can cracks open.
d = 0.9
hiss = highpass(noise(d), 0.6) * env_exp(d, 0.35)
crackle = np.zeros(n_samp(d))
for i in range(70):
    at = rng.integers(0, n_samp(d) - 200)
    cd = 0.006
    tick = noise(cd) * env_exp(cd, 0.0015)
    crackle[at:at + len(tick)] += tick * rng.uniform(0.15, 0.6) * (1.0 - at / n_samp(d))
save("fizz.wav", hiss * 0.6 + crackle, 0.55)

# ---- can_crush: crinkling aluminum — dense short metallic ticks over a
# broadband crush noise burst, pitch-random per tick (foil crumple texture).
d = 0.4
crush = lowpass(noise(d), 0.4) * env_exp(d, 0.09) * 0.8
ticks = np.zeros(n_samp(d))
for i in range(50):
    at = rng.integers(0, n_samp(d) - 300)
    td = 0.01
    f = rng.uniform(1200, 3200)
    tick = np.sin(2 * np.pi * f * t_axis(td)) * env_exp(td, 0.003)
    ticks[at:at + len(tick)] += tick * rng.uniform(0.2, 0.5)
save("can_crush.wav", crush + ticks, 0.7)

# ---- sip: single soft coffee-cup sip — shorter and airier than gulp.wav,
# one pulse plus a light lip-smack transient.
d = 0.3
pulse = np.sin(2 * np.pi * 300 * t_axis(0.1)) * env_exp(0.1, 0.025)
gurgle = (lowpass(noise(0.1), 0.4) - lowpass(noise(0.1), 0.15)) * env_exp(0.1, 0.02) * 0.4
smack = noise(0.015) * env_exp(0.015, 0.004) * 1.2
sig = np.zeros(n_samp(d))
sig[:n_samp(0.1)] += pulse + gurgle
at = n_samp(0.09)
sig[at:at + len(smack)] += smack
save("sip.wav", sig, 0.6)

# ---- steam: quick airy hiss puff — coffee's rising steam wisp, brighter
# and shorter than fizz.wav's carbonation hiss (higher cutoff, tighter decay).
d = 0.6
hiss = highpass(noise(d), 0.75) * env_exp(d, 0.18)
save("steam.wav", hiss, 0.4)
