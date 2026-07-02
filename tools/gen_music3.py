# Per-level soundtrack: unique mood per battlefield, TWO variations each —
# the game crossfades between variations on a randomized timer so nothing
# loops into boredom. Pure numpy.
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUD = os.path.join(ROOT, "assets", "audio")
SR = 22050
rng = np.random.default_rng(77)

def save(name, x, vol=0.62):
    x = np.asarray(x, dtype=np.float64)
    data = (x / (np.max(np.abs(x)) + 1e-9) * vol * 32767).astype(np.int16)
    with wave.open(os.path.join(AUD, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wav", name)

def n(d): return int(SR * d)
def t_axis(d): return np.arange(n(d)) / SR
def env_exp(d, tau): return np.exp(-t_axis(d) / tau)
def noise(d): return rng.standard_normal(n(d))

def lowpass(x, a):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y

def env_adsr(nn, a=0.01, d=0.08, s=0.7, r=0.1):
    na, nd, nr = n(a), n(d), n(r)
    ns = max(nn - na - nd - nr, 0)
    return np.concatenate([np.linspace(0, 1, na), np.linspace(1, s, nd),
        np.full(ns, s), np.linspace(s, 0, nr)])[:nn]

def saw(f, nn, det=0.004):
    t = np.arange(nn) / SR
    return (((t*f) % 1.0) + ((t*f*(1+det)) % 1.0) + ((t*f*(1-det)) % 1.0)) * 2/3 - 1

def sq(f, nn):
    return np.sign(np.sin(2*np.pi*f*np.arange(nn)/SR))

def sine(f, nn):
    return np.sin(2*np.pi*f*np.arange(nn)/SR)

def tri(f, nn):
    t = np.arange(nn)/SR
    return 2*np.abs(2*((t*f) % 1.0)-1)-1

def place(buf, x, at):
    i = n(at); j = min(i+len(x), len(buf))
    if i < len(buf): buf[i:j] += x[:j-i]

def loopify(x, fade=0.3):
    m = n(fade)
    y = x[:-m].copy()
    r = np.linspace(0, 1, m)
    y[:m] = y[:m]*r + x[-m:]*(1-r)
    return y

def kick():
    d=0.15; t=t_axis(d)
    f = 85*np.exp(-t*20)+40
    return np.sin(2*np.pi*np.cumsum(f)/SR)*env_exp(d,0.05)*1.3

def snare():
    d=0.14; t=t_axis(d)
    return (lowpass(noise(d),0.5)*0.8 + sine(190,n(d))*0.4)*env_exp(d,0.03)

def hat():
    d=0.03; x=noise(d); x=x-lowpass(x,0.4)
    return x*env_exp(d,0.008)*0.4

def taiko(f=70):
    d=0.5; t=t_axis(d)
    return np.sin(2*np.pi*(f*np.exp(-t*3))*t)*env_exp(d,0.12)*1.5

NOTE = {}
A4 = 440.0
NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
for octv in range(2, 6):
    for i, nm in enumerate(NAMES):
        NOTE[f"{nm}{octv}"] = A4 * 2 ** ((octv - 4) + (i - 9) / 12.0)

def compose(name, bpm, bars, build):
    beat = 60.0/bpm
    dur = bars*4*beat
    buf = np.zeros(n(dur))
    build(buf, beat, bars)
    save(name, loopify(buf))

# ---------------- CITY: tense minor synth pulse (A minor)
def city(var):
    def b(buf, beat, bars):
        bass = ["A2","A2","C3","G2"] if var==0 else ["A2","E2","F2","G2"]
        for k in range(bars*8):
            nm = bass[(k//8)%4]
            x = sq(NOTE[nm], n(beat*0.45))*0.4
            x = lowpass(x, 0.18)*env_adsr(n(beat*0.45),0.004,0.03,0.6,0.06)
            place(buf, x, k*beat/2)
        for bar in range(bars):
            place(buf, kick(), bar*4*beat)
            place(buf, kick()*0.7, (bar*4+2.5)*beat)
            place(buf, snare()*0.8, (bar*4+2)*beat)
            for e in range(8):
                place(buf, hat()*(0.6 if e%2 else 0.3), (bar*4+e/2)*beat)
        # eerie pad
        for ci,ch in enumerate([["A3","C4","E4"],["F3","A3","C4"]]*(bars//4)):
            at = ci*2*4*beat
            nn = n(8*beat)
            pad = sum(saw(NOTE[x],nn,0.006) for x in ch)
            place(buf, lowpass(pad,0.07)*env_adsr(nn,1.0,0.5,0.7,1.5)*0.28, at)
    return b

# ---------------- TOWN: gentle folk waltz (G major, 3/4 feel via triplet)
def town(var):
    def b(buf, beat, bars):
        prog = [["G3","B3","D4"],["C4","E4","G4"],["D4","F#4","A4"],["G3","B3","D4"]] if var==0 \
          else [["E3","G3","B3"],["C4","E4","G4"],["G3","B3","D4"],["D4","F#4","A4"]]
        for ci in range(bars):
            ch = prog[ci%4]
            root = ch[0]
            at = ci*4*beat
            x = tri(NOTE[root]/2, n(beat*1.4))*env_adsr(n(beat*1.4),0.01,0.1,0.5,0.3)
            place(buf, x*0.5, at)
            for k, third in enumerate([1,2]):
                y = sum(tri(NOTE[q],n(beat*0.8)) for q in ch[1:])
                place(buf, y*env_adsr(n(beat*0.8),0.01,0.08,0.4,0.2)*0.2, at+(1.33+k*1.33)*beat)
        mel = ["B4","A4","G4","A4","B4","D5" if "D5" in NOTE else "D4","B4","G4"]
        for k in range(bars*2):
            nm = mel[k%8]
            x = sine(NOTE.get(nm, 392.0), n(beat*1.8))*env_adsr(n(beat*1.8),0.02,0.2,0.5,0.5)
            place(buf, x*0.3, k*2*beat + (0.5*beat if var else 0))
    return b

# ---------------- MUDPIT: swampy shuffle stomp (E blues)
def mud(var):
    def b(buf, beat, bars):
        riff = ["E2","E2","G2","A2","E2","E2","B2","A2"] if var==0 else ["E2","G2","E2","A2","E2","D3","B2","G2"]
        for k in range(bars*8):
            nm = riff[k%8]
            swing = 0.08*beat if k%2 else 0.0
            x = saw(NOTE[nm],n(beat*0.4),0.01)*0.5
            x = lowpass(x,0.15)*env_adsr(n(beat*0.4),0.005,0.05,0.5,0.08)
            place(buf, x, k*beat/2+swing)
        for bar in range(bars):
            place(buf, kick(), bar*4*beat)
            place(buf, kick()*0.8, (bar*4+1.7)*beat)
            place(buf, snare(), (bar*4+2)*beat)
            place(buf, snare()*0.5, (bar*4+3.7)*beat)
    return b

# ---------------- CASTLE: medieval drums + dorian flute (D dorian)
def castle(var):
    def b(buf, beat, bars):
        for bar in range(bars):
            place(buf, taiko(65), bar*4*beat)
            place(buf, taiko(80)*0.7, (bar*4+1.5)*beat)
            place(buf, taiko(65)*0.8, (bar*4+3)*beat)
            if bar%2==1:
                place(buf, snare()*0.6, (bar*4+3.5)*beat)
        mel = ["D4","F4","G4","A4","C5" if "C5" in NOTE else "C4","A4","G4","F4"] if var==0 \
          else ["A4","G4","F4","D4","F4","G4","A4","D4"]
        for k in range(bars):
            nm = mel[k%8]
            nn = n(beat*3.2)
            x = sq(NOTE.get(nm,293.7),nn)*0.15+sine(NOTE.get(nm,293.7),nn)*0.5
            x = lowpass(x,0.3)*env_adsr(nn,0.05,0.2,0.6,0.6)
            place(buf, x*0.4, k*4*beat+beat)
        # drone
        nn = n(bars*4*beat)
        place(buf, lowpass(saw(NOTE["D2"],nn,0.003),0.06)*0.22, 0)
    return b

# ---------------- GYM: sporty funk (E minor pentatonic clav)
def gym(var):
    def b(buf, beat, bars):
        line = ["E2","E2","G2","E2","A2","E2","B2","D3"] if var==0 else ["E2","G2","A2","E2","E2","D3","B2","A2"]
        for k in range(bars*8):
            nm = line[k%8]
            x = sq(NOTE[nm],n(beat*0.3))*0.35
            x = lowpass(x,0.25)*env_adsr(n(beat*0.3),0.003,0.03,0.5,0.05)
            place(buf, x, k*beat/2)
        for bar in range(bars):
            place(buf, kick(), bar*4*beat)
            place(buf, kick(), (bar*4+2)*beat)
            place(buf, snare(), (bar*4+1)*beat)
            place(buf, snare(), (bar*4+3)*beat)
            for e in range(8):
                place(buf, hat()*0.5, (bar*4+e/2)*beat)
        # crowd stomp-clap every 2 bars (WE WILL rock you energy, but legally distinct)
        for k in range(bars//2):
            at = k*8*beat
            for st in [0, 0.5]:
                place(buf, kick()*1.2, at+st*beat)
            place(buf, snare()*1.4, at+1.0*beat)
    return b

# ---------------- ISLAND: marimba tropical (C major, laid back)
def island(var):
    def b(buf, beat, bars):
        mel = ["C4","E4","G4","E4","A4","G4","E4","D4"] if var==0 else ["E4","G4","C5" if "C5" in NOTE else "C4","G4","A4","E4","G4","C4"]
        for k in range(bars*4):
            nm = mel[k%8]
            nn = n(beat*0.9)
            x = sine(NOTE.get(nm,261.6),nn)+0.4*sine(NOTE.get(nm,261.6)*4,nn)*env_exp(beat*0.9,0.05)
            place(buf, x*env_exp(beat*0.9,0.22)*0.45, k*beat)
        bassline = ["C3","G2","A2","F2"]
        for k in range(bars):
            x = sine(NOTE[bassline[k%4]],n(beat*3.4))*env_adsr(n(beat*3.4),0.02,0.2,0.5,0.6)
            place(buf, x*0.4, k*4*beat)
        for bar in range(bars):
            for e in range(8):
                place(buf, hat()*(0.4 if e%2 else 0.15), (bar*4+e/2)*beat)
    return b

# ---------------- VOLCANO: dark drone + taiko war drums (C minor low)
def volcano(var):
    def b(buf, beat, bars):
        nn = n(bars*4*beat)
        drone = lowpass(saw(NOTE["C2"],nn,0.008),0.05) + lowpass(saw(NOTE["G2"],nn,0.006),0.05)*0.5
        wob = 1.0+0.15*np.sin(2*np.pi*0.23*np.arange(nn)/SR)
        place(buf, drone*wob*0.3, 0)
        pat = [(0,90,1.3),(1,70,0.8),(1.75,70,0.6),(2.5,90,1.1),(3.5,60,0.7)] if var==0 \
          else [(0,90,1.3),(0.75,70,0.7),(2,90,1.2),(3,70,0.9),(3.75,60,0.5)]
        for bar in range(bars):
            for (b8,f,a) in pat:
                place(buf, taiko(f)*a, (bar*4+b8)*beat)
        # rising unease every 4 bars
        for k in range(bars//4):
            nn2 = n(4*beat)
            f = np.linspace(NOTE["C3"], NOTE["D#3"], nn2)
            x = np.sin(2*np.pi*np.cumsum(f)/SR)*env_adsr(nn2,1.5,0.5,0.5,1.0)
            place(buf, lowpass(x,0.2)*0.2, k*16*beat+8*beat)
    return b

print("composing per-level tracks (2 variations each)...")
compose("music_city.wav", 112, 8, city(0));    compose("music_city_b.wav", 112, 8, city(1))
compose("music_town.wav", 92, 8, town(0));     compose("music_town_b.wav", 92, 8, town(1))
compose("music_mudpit.wav", 84, 8, mud(0));    compose("music_mudpit_b.wav", 84, 8, mud(1))
compose("music_castle.wav", 96, 8, castle(0)); compose("music_castle_b.wav", 96, 8, castle(1))
compose("music_gym.wav", 116, 8, gym(0));      compose("music_gym_b.wav", 116, 8, gym(1))
compose("music_island.wav", 96, 8, island(0)); compose("music_island_b.wav", 96, 8, island(1))
compose("music_volcano.wav", 76, 8, volcano(0)); compose("music_volcano_b.wav", 76, 8, volcano(1))
print("MUSIC3 DONE")
