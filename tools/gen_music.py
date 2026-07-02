# Soundtrack + night-2 SFX for Tank Commander VR. Pure numpy synthesis.
# D minor, 96 BPM. Calm & combat loops share length/harmony so the game can
# crossfade them phase-locked. Run: python tools/gen_music.py
import os, wave, math
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUD = os.path.join(ROOT, "assets", "audio")
os.makedirs(AUD, exist_ok=True)
SR = 22050
BPM = 96.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
rng = np.random.default_rng(11)

def save(name, x, vol=0.85):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) + 1e-9
    data = (x / peak * vol * 32767).astype(np.int16)
    with wave.open(os.path.join(AUD, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wav", name, f"{len(x)/SR:.2f}s")

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y

def n_samp(dur): return int(SR * dur)

def env_adsr(n, a=0.01, d=0.08, s=0.7, r=0.1):
    na, nd, nr = n_samp(a), n_samp(d), n_samp(r)
    ns = max(n - na - nd - nr, 0)
    return np.concatenate([
        np.linspace(0, 1, na), np.linspace(1, s, nd),
        np.full(ns, s), np.linspace(s, 0, nr)])[:n]

def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    p1 = (t * freq) % 1.0
    p2 = (t * freq * (1 + detune)) % 1.0
    p3 = (t * freq * (1 - detune)) % 1.0
    return ((p1 + p2 + p3) * 2 - 3) / 3

def sq(freq, n):
    t = np.arange(n) / SR
    return np.sign(np.sin(2 * np.pi * freq * t))

def sine(freq, n):
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t)

def place(buf, x, at_s):
    i = n_samp(at_s)
    j = min(i + len(x), len(buf))
    if i < len(buf):
        buf[i:j] += x[:j - i]

def loopify(x, fade=0.35):
    n = n_samp(fade)
    y = x[:-n].copy()
    ramp = np.linspace(0, 1, n)
    y[:n] = y[:n] * ramp + x[-n:] * (1 - ramp)
    return y

NOTE = {"D2": 73.42, "F2": 87.31, "G2": 98.0, "A2": 110.0, "Bb2": 116.54, "C3": 130.81,
        "D3": 146.83, "F3": 174.61, "A3": 220.0, "Bb3": 233.08, "C4": 261.63,
        "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.0, "A4": 440.0, "Bb4": 466.16}

CHORDS = [  # 2 bars each -> 8 bars total
    ("Dm", ["D3", "F3", "A3"]), ("Bb", ["Bb2", "D3", "F3"]),
    ("F", ["F2", "A3", "C4"]), ("C", ["C3", "E4", "G4"]),
]

# ---------------------------------------------------------------- drums
def kick(n=None):
    n = n or n_samp(0.16)
    t = np.arange(n) / SR
    f = 90 * np.exp(-t * 22) + 42
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 16)
    x[:n_samp(0.004)] += rng.standard_normal(n_samp(0.004)) * 0.4
    return x * 1.3

def snare():
    n = n_samp(0.16)
    t = np.arange(n) / SR
    return (lowpass(rng.standard_normal(n), 0.5) * 0.8 + np.sin(2 * np.pi * 185 * t) * 0.5) * np.exp(-t * 22)

def hat(open_=False):
    n = n_samp(0.09 if open_ else 0.03)
    x = rng.standard_normal(n)
    x = x - lowpass(x, 0.4)  # crude highpass
    return x * np.exp(-np.arange(n) / SR * (24 if open_ else 90)) * 0.5

def tom(freq):
    n = n_samp(0.2)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * (freq * np.exp(-t * 4)) * t) * np.exp(-t * 14)

# ---------------------------------------------------------------- layers (8 bars)
DUR = 8 * BAR  # 20 s
N = n_samp(DUR)

def pad_layer():
    buf = np.zeros(N)
    for ci, (_, notes) in enumerate(CHORDS):
        at = ci * 2 * BAR
        n = n_samp(2 * BAR)
        chord = np.zeros(n)
        for nm in notes:
            chord += saw(NOTE[nm], n, 0.004)
        chord = lowpass(chord, 0.10)
        chord *= env_adsr(n, 0.8, 0.5, 0.8, 1.2)
        place(buf, chord * 0.5, at)
    # slow shimmer: soft fifth an octave up, entering on chords 2 & 4
    for ci in (1, 3):
        at = ci * 2 * BAR
        n = n_samp(2 * BAR)
        nm = CHORDS[ci][1][0]
        x = sine(NOTE[nm] * 3.0, n) * env_adsr(n, 1.5, 0.5, 0.5, 1.5) * 0.08
        place(buf, x, at)
    return buf

def arp_layer():
    # sparse bell arps for the calm loop
    buf = np.zeros(N)
    for ci, (_, notes) in enumerate(CHORDS):
        seq = [notes[0], notes[2], notes[1], notes[2]]
        for k, nm in enumerate(seq):
            at = ci * 2 * BAR + k * BEAT * 2
            n = n_samp(0.9)
            x = sine(NOTE[nm] * 2, n) * env_adsr(n, 0.005, 0.3, 0.25, 0.5)
            x += sine(NOTE[nm] * 4.02, n) * env_adsr(n, 0.005, 0.15, 0.1, 0.4) * 0.4
            place(buf, x * 0.35, at)
    return buf

def bass_layer():
    buf = np.zeros(N)
    roots = {"Dm": "D2", "Bb": "Bb2", "F": "F2", "C": "C3"}
    for ci, (name, _) in enumerate(CHORDS):
        root = NOTE[roots[name]]
        for eighth in range(16):  # 2 bars of 8ths
            at = ci * 2 * BAR + eighth * BEAT / 2
            accent = eighth % 4 == 0
            fr = root * (2.0 if eighth % 8 == 7 else 1.0)
            n = n_samp(BEAT / 2 * 0.9)
            x = saw(fr, n, 0.002) * 0.6 + sq(fr / 2, n) * 0.25
            x = lowpass(x, 0.22)
            x *= env_adsr(n, 0.004, 0.05, 0.65 if accent else 0.45, 0.05)
            place(buf, x * (1.0 if accent else 0.8), at)
    return buf

def drum_layer():
    buf = np.zeros(N)
    for bar in range(8):
        t0 = bar * BAR
        for b, p in [(0, 1.0), (1.5, 0.7), (2, 1.0), (3.5, 0.5)]:
            place(buf, kick() * p, t0 + b * BEAT)
        for b in (1, 3):
            place(buf, snare(), t0 + b * BEAT)
        for e in range(8):
            place(buf, hat(e == 7), t0 + e * BEAT / 2)
        if bar % 4 == 3:  # military tom fill
            for k, f in enumerate((160, 130, 100, 80)):
                place(buf, tom(f) * 0.8, t0 + 3 * BEAT + k * BEAT / 4)
    return buf

def stab_layer():
    # staccato minor stabs on the & of 2, combat urgency
    buf = np.zeros(N)
    for ci, (_, notes) in enumerate(CHORDS):
        for bar in range(2):
            at = (ci * 2 + bar) * BAR + 2.5 * BEAT
            n = n_samp(0.22)
            x = np.zeros(n)
            for nm in notes:
                x += saw(NOTE[nm] * 2, n, 0.006)
            x = lowpass(x, 0.3) * env_adsr(n, 0.004, 0.08, 0.3, 0.08)
            place(buf, x * 0.35, at)
    return buf

print("rendering layers...")
pad = pad_layer()
calm = pad + arp_layer()
combat = pad * 0.7 + bass_layer() + drum_layer() + stab_layer()
save("music_calm.wav", loopify(calm), 0.62)
save("music_combat.wav", loopify(combat), 0.8)

# menu theme: 4 chords, slower feel — pad + melody line
mel_notes = ["D4", "F4", "E4", "D4", "A4", "G4", "F4", "E4"]
menu = pad_layer() * 0.9
buf = np.zeros(N)
for k, nm in enumerate(mel_notes):
    at = k * BAR
    n = n_samp(BAR * 0.96)
    x = sine(NOTE[nm], n) * 0.5 + saw(NOTE[nm], n, 0.003) * 0.12
    x = lowpass(x, 0.25) * env_adsr(n, 0.15, 0.4, 0.6, 0.8)
    place(buf, x * 0.4, at)
save("music_menu.wav", loopify(menu + buf), 0.6)

# stingers
n = n_samp(2.2)
sting = np.zeros(n)
for k, nm in enumerate(("D3", "F3", "A3", "D4")):
    x = saw(NOTE[nm], n_samp(1.2), 0.005) * env_adsr(n_samp(1.2), 0.01, 0.2, 0.5, 0.6)
    place(sting, lowpass(x, 0.3) * 0.7, k * 0.13)
save("sting_wave.wav", sting, 0.7)
n = n_samp(2.8)
sting = np.zeros(n)
for k, nm in enumerate(("D4", "Bb3", "A3", "D3")):
    x = saw(NOTE[nm], n_samp(1.4), 0.006) * env_adsr(n_samp(1.4), 0.02, 0.3, 0.5, 0.8)
    place(sting, lowpass(x, 0.22) * 0.7, k * 0.3)
save("sting_over.wav", sting, 0.7)

# ---------------------------------------------------------------- night-2 SFX
def t_axis(dur): return np.arange(n_samp(dur)) / SR
def env_exp(dur, tau): return np.exp(-t_axis(dur) / tau)
def noise(dur): return rng.standard_normal(n_samp(dur))

# mortar whistle (incoming!)
dur = 1.6
f = np.linspace(2600, 900, n_samp(dur))
x = np.sin(2 * np.pi * np.cumsum(f) / SR)
x *= np.linspace(0.15, 1.0, n_samp(dur)) ** 1.5
save("mortar_whistle.wav", x, 0.5)

# mortar launch thoonk
dur = 0.5
x = np.sin(2 * np.pi * np.cumsum(np.linspace(140, 60, n_samp(dur))) / SR) * env_exp(dur, 0.09)
x += lowpass(noise(dur), 0.2) * env_exp(dur, 0.05) * 0.5
save("mortar_launch.wav", x, 0.7)

# jeep engine loop (smaller, angrier)
dur = 1.4
t = t_axis(dur)
wob = 1.0 + 0.05 * np.sin(2 * np.pi * 5 * t)
x = np.zeros_like(t)
for h, a in ((1, 1.0), (2, 0.5), (3, 0.4), (5, 0.15)):
    ph = 2 * np.pi * 92 * h * np.cumsum(wob) / SR
    x += a * ((ph / np.pi) % 2 - 1)
x += lowpass(noise(dur), 0.15) * 0.5
fade = n_samp(0.08); ramp = np.linspace(0, 1, fade)
y = x[:-fade].copy(); y[:fade] = y[:fade] * ramp + x[-fade:] * (1 - ramp)
save("jeep_loop.wav", y, 0.5)

# rifle crack
dur = 0.14
x = noise(dur) * env_exp(dur, 0.015)
x += np.sin(2 * np.pi * 320 * t_axis(dur)) * env_exp(dur, 0.03) * 0.4
save("rifle.wav", x, 0.6)

# rubble / debris clatter
dur = 1.1
x = np.zeros(n_samp(dur))
for i in range(26):
    at = int(rng.uniform(0, 0.8) * SR)
    d2 = 0.06
    hit = np.sin(2 * np.pi * rng.uniform(200, 900) * t_axis(d2)) * env_exp(d2, 0.012)
    j = min(at + len(hit), len(x))
    x[at:j] += hit[:j - at] * rng.uniform(0.3, 1.0)
x += lowpass(noise(dur), 0.15) * env_exp(dur, 0.3) * 0.6
save("debris.wav", x, 0.7)

# stone wall collapse
dur = 2.2
br = np.cumsum(noise(dur)); br /= np.max(np.abs(br) + 1e-9)
x = br * env_exp(dur, 0.5) + lowpass(noise(dur), 0.08) * env_exp(dur, 0.6) * 0.9
for i in range(14):
    at = int(rng.uniform(0.1, 1.6) * SR)
    d2 = 0.09
    hit = np.sin(2 * np.pi * rng.uniform(120, 420) * t_axis(d2)) * env_exp(d2, 0.02)
    j = min(at + len(hit), len(x))
    x[at:j] += hit[:j - at] * rng.uniform(0.4, 1.0)
save("wall_crumble.wav", x, 0.85)

# tank horn (kids requirement, unofficial)
dur = 0.9
x = sq(311, n_samp(dur)) * 0.5 + sq(233, n_samp(dur)) * 0.5
x = lowpass(x, 0.18) * env_adsr(n_samp(dur), 0.02, 0.1, 0.9, 0.15)
save("horn.wav", x, 0.75)

# bomb drop whistle + gear shifter clunk + plane crash
dur = 1.8
f = np.linspace(1800, 500, n_samp(dur))
x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.linspace(0.1, 1.0, n_samp(dur))
save("bomb_whistle.wav", x, 0.5)
dur = 0.28
x = np.zeros(n_samp(dur))
for f0, at in ((260, 0.0), (180, 0.09)):
    d2 = 0.1
    c = (np.sin(2 * np.pi * f0 * t_axis(d2)) + 0.4 * np.sin(2 * np.pi * f0 * 2.6 * t_axis(d2))) * env_exp(d2, 0.02)
    i = n_samp(at); j = min(i + len(c), len(x)); x[i:j] += c[:j - i]
save("shifter.wav", x, 0.7)
dur = 2.0
br = np.cumsum(noise(dur)); br /= np.max(np.abs(br) + 1e-9)
x = br * env_exp(dur, 0.3) + noise(dur) * env_exp(dur, 0.08)
for i in range(10):
    at = int(rng.uniform(0, 0.9) * SR)
    d2 = 0.12
    hit = np.sin(2 * np.pi * rng.uniform(150, 700) * t_axis(d2)) * env_exp(d2, 0.03)
    j = min(at + len(hit), len(x))
    x[at:j] += hit[:j - at]
save("crash.wav", x, 0.9)

# menu select blip + knob tick
x = sine(660, n_samp(0.09)) * env_exp(0.09, 0.03) + sine(880, n_samp(0.09)) * env_exp(0.09, 0.02) * 0.5
save("ui_select.wav", x, 0.5)
x = sine(1200, n_samp(0.025)) * env_exp(0.025, 0.006)
save("knob.wav", x, 0.4)

print("MUSIC+SFX DONE")
