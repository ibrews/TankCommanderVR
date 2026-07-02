"""Batch-generate Alex-voice VO lines for Tank Commander VR via F5-TTS.

Run with the system Python 3.12 (has f5_tts):
  C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo.py

Per kb magihuman-video-pipeline: keep gen_text < 150 chars, then apply the
anti-harshness EQ (-4dB@3.5kHz, -3dB@7kHz, +2dB@250Hz) with ffmpeg and
resample to 22050 mono to match the game's audio.
"""
import os, subprocess, sys, time

# torchcodec is broken on Windows — route torchaudio.load through soundfile
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
    "vo_title":      "Tank Commander V R. Made for Ani.",
    "vo_welcome":    "Hey kids! It's me, Dad. I'm the tank computer now. Buckle up.",
    "vo_menu_pick":  "Pick a battlefield and a difficulty. Castle is my favorite.",
    "vo_howto1":     "First: flip the battery switch on the left console, then hold the green starter button until the engine catches.",
    "vo_howto2":     "Grab the two floor levers to drive. Push both to go forward, pull one back to turn. Easy.",
    "vo_howto3":     "Grab the stick on your right to aim the turret. The trigger fires the cannon. Pull the red breech lever to reload.",
    "vo_howto4":     "Rockets live under the red safety cover on the left. Flip it open, arm the switch, and smash the big red button.",
    "vo_start":      "Engine running. Grab the tillers and roll out.",
    "vo_wave":       "Heads up! Enemies incoming.",
    "vo_wave2":      "More of them. Stay sharp.",
    "vo_wave_clear": "Wave clear! You're getting good at this.",
    "vo_kill":       "Target destroyed. Nice shot!",
    "vo_plane_down": "Plane down! Great shooting.",
    "vo_hull_low":   "Hull integrity low. I am not kidding. Get out of there!",
    "vo_hit":        "We're hit!",
    "vo_armed":      "Rockets armed. Please don't aim those at your sibling.",
    "vo_gameover":   "Ouch. We're done. Pull the yellow handle on the roof when you're ready to go again.",
    "vo_coop":       "Co-op mode. One of you drives, one of you shoots. Try not to argue.",
    "vo_versus":     "Versus mode. May the best kid win. I love you both equally.",
    "vo_easy":       "Easy mode. A nice Sunday drive.",
    "vo_hard":       "Hard mode. You asked for it.",
    "vo_plane":      "Plane mode! Throttle on the left, stick on the right. Try not to meet the ground.",
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
        # anti-harshness EQ + silence trim + normalize + 22050 mono
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
    print("VO DONE")

if __name__ == "__main__":
    main()
