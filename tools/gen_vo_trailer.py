"""Trailer narration VO (Meta Quest App Lab store trailer, energetic
announcer tone). Same F5-TTS pattern as gen_vo.py -- see that file's header
for the torchaudio/soundfile monkeypatch rationale (torchcodec broken on
Windows) and the anti-harshness EQ. Output goes to tools/vo_trailer/, NOT
assets/audio/vo/ (this is marketing narration, not in-game VO).
Run with the system Python 3.12 (has f5_tts):
  C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo_trailer.py
"""
import os, subprocess, time

import soundfile as sf
import torch
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
OUT = os.path.join(ROOT, "tools", "vo_trailer")
os.makedirs(RAW, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

LINES = {
    "trailer_01_hook":     "Strap in, Commander. This is Tank Commander V R.",
    "trailer_02_cockpit":  "Flip the battery, hit the starter, and take the seat of a real working tank cockpit.",
    "trailer_03_vehicles": "Roll out in the tank. Take to the sky in the plane, the biplane, or the attack helicopter.",
    "trailer_04_boat":     "Or hit the water in the gunboat. Every vehicle, fully playable, right here on Quest.",
    "trailer_05_combat":   "Waves of enemy tanks, jeeps, and planes are coming. Fire the cannon. Launch the rockets. Bring the boom.",
    "trailer_06_coop":     "Play solo, go co-op, or battle a friend versus. On Quest 3 and Quest 3 S.",
    "trailer_07_cta":      "Tank Commander V R. Available now on the Meta Horizon Store. Get in. Roll out.",
}

def main():
    print("Loading F5-TTS...")
    tts = F5TTS()
    print("Transcribing reference...")
    ref_text = tts.transcribe(REF_AUDIO)
    print(f"ref_text: {ref_text[:120]}")
    for name, text in LINES.items():
        assert len(text) < 150, f"{name} too long ({len(text)})"
        t0 = time.time()
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text, gen_text=text, seed=42)
        raw_path = os.path.join(RAW, name + ".wav")
        sf.write(raw_path, wav, sr)
        out_path = os.path.join(OUT, name + ".wav")
        subprocess.run([
            "ffmpeg", "-y", "-i", raw_path,
            "-af",
            "equalizer=f=3500:t=q:w=1.2:g=-4,"
            "equalizer=f=7000:t=q:w=1.2:g=-3,"
            "equalizer=f=250:t=q:w=1.0:g=2,"
            "silenceremove=start_periods=1:start_threshold=-45dB,"
            "areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
            "loudnorm=I=-18:TP=-1.5",
            "-ar", "22050", "-ac", "1", out_path,
        ], check=True, capture_output=True)
        print(f"{name}: {time.time()-t0:.1f}s -> {out_path}")
    print("TRAILER VO DONE")

if __name__ == "__main__":
    main()
