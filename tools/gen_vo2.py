"""Round-2 VO: DAD FM radio show (Good Morning Vietnam energy), mutator-mode
lines, disaster reactions, gym lines. F5-TTS, chunks < 150 chars, same EQ.
Run: C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo2.py
"""
import os, subprocess, time
import soundfile as sf
import torch
import numpy as np
import torchaudio

def sf_load(filepath, **kwargs):
    data, sr = sf.read(str(filepath), dtype="float32")
    data = data[None, :] if data.ndim == 1 else data.T
    return torch.from_numpy(data), sr
torchaudio.load = sf_load

from f5_tts.api import F5TTS

REF_AUDIO = "D:/magihuman/output/alex_ref_10s.wav"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "tools", "vo_raw")
OUT = os.path.join(ROOT, "assets", "audio", "vo")
os.makedirs(RAW, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

LINES = {
    # DAD FM — the morning zoo
    "radio_1":  "GOOOOOD MORNING, BATTLEFIELD! This is DAD F M, coming to you live from inside your own tank!",
    "radio_2":  "Traffic report: tanks. Tanks everywhere. Avoid the castle, someone keeps blowing holes in it.",
    "radio_3":  "Weather today: sunny, with a chance of mortars. Back to the music!",
    "radio_4":  "A shout out to my two favorite gunners in the whole world. You know who you are. Now reload!",
    "radio_5":  "Remember kids: the tiller is not a snack. This has been a public service announcement.",
    "radio_6":  "You're listening to DAD F M. All dad. All day. There is no escape.",
    "radio_7":  "Breaking news: local tank commander is doing GREAT. Sources say their dad is very proud.",
    "radio_8":  "This next song goes out to anyone currently being chased by a jeep. Stay strong. Drive faster.",
    "radio_9":  "Pro tip from DAD F M: if you hear a whistling sound, drive literally anywhere else.",
    "radio_10": "The mud pit is not a bath. I repeat: NOT a bath. We've lost too many good tanks this way.",
    "radio_11": "It's time for the traffic and weather together on the eights! Just kidding. It's tanks again.",
    "radio_12": "DAD F M! W. D. A. D. If you can hear this, clean your room. Over.",
    # mutators
    "vo_lowg":       "Low gravity mode! Everything bounces. Physics called in sick today.",
    "vo_underwater": "Underwater mode. Glub glub. Don't ask how the engine works down here.",
    "vo_balloon":    "Balloon mode! Everything is a balloon. Try not to hug the enemies.",
    "vo_paintball":  "Paintball mode! Nobody gets hurt, everybody gets messy. Just like the good old days.",
    # disasters
    "vo_tornado":    "Uh oh. TORNADO! That is definitely not in the manual. Hold onto something!",
    "vo_volcano":    "Is that... a volcano?! Who ordered a volcano? Drive! DRIVE!",
    "vo_hurricane":  "Hurricane warning! Batten down the hatches. That's a real thing tank commanders say.",
    # gym
    "vo_gym":        "Welcome to the gymnasium. Everything is cardboard. Please. No running.",
    "vo_gym_wave":   "Recess is over! Here they come!",
}

def main():
    print("Loading F5-TTS...")
    tts = F5TTS()
    ref_text = tts.transcribe(REF_AUDIO)
    for name, text in LINES.items():
        assert len(text) < 150, f"{name} too long ({len(text)})"
        t0 = time.time()
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text, gen_text=text, seed=42)
        raw = os.path.join(RAW, name + ".wav")
        sf.write(raw, wav, sr)
        out = os.path.join(OUT, name + ".wav")
        subprocess.run([
            "ffmpeg", "-y", "-i", raw, "-af",
            "equalizer=f=3500:t=q:w=1.2:g=-4,equalizer=f=7000:t=q:w=1.2:g=-3,"
            "equalizer=f=250:t=q:w=1.0:g=2,"
            "silenceremove=start_periods=1:start_threshold=-45dB,"
            "areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
            "loudnorm=I=-18:TP=-1.5",
            "-ar", "22050", "-ac", "1", out,
        ], check=True, capture_output=True)
        print(f"{name}: {time.time()-t0:.1f}s")
    print("VO2 DONE")

if __name__ == "__main__":
    main()
