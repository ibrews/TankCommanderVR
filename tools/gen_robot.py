"""Robot character voices with ZERO API cost: F5-TTS speaks the line, then an
ffmpeg chain robotizes it (pitch flatten + ring-mod tremolo + bitcrush +
chorus). Use for announcers, drones, computers — saves ElevenLabs quota for
characters that need warmth.

Run: C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_robot.py
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

# the tank's ONBOARD COMPUTER — a second personality for variety
LINES = {
    "robot_online":   "Tank systems online. All switches where you left them.",
    "robot_versus_1": "Duel mode engaged. Combatants, to your tanks.",
    "robot_versus_2": "Round begin. Fight!",
    "robot_victory":  "Victory. Recalibrating smugness levels.",
    "robot_lowammo":  "Ammunition low. Suggest enthusiasm as substitute.",
    "robot_repair":   "Hull regenerating. Please avoid additional holes.",
}

ROBOT_AF = (
    "asetrate=22050*0.92,aresample=22050,"      # slight pitch down
    "acrusher=bits=9:mode=log:aa=0.6,"          # digital grit
    "tremolo=f=42:d=0.55,"                      # ring-mod flavor
    "chorus=0.6:0.9:40:0.35:0.25:1.5,"          # metallic doubling
    "equalizer=f=300:t=q:w=1.0:g=3,equalizer=f=2600:t=q:w=1.2:g=4,"
    "silenceremove=start_periods=1:start_threshold=-45dB,"
    "areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
    "loudnorm=I=-17:TP=-1.5"
)

def main():
    tts = F5TTS()
    ref_text = tts.transcribe(REF_AUDIO)
    for name, text in LINES.items():
        t0 = time.time()
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text, gen_text=text, seed=99)
        raw = os.path.join(RAW, name + ".wav")
        sf.write(raw, wav, sr)
        subprocess.run(["ffmpeg", "-y", "-i", raw, "-af", ROBOT_AF,
            "-ar", "22050", "-ac", "1", os.path.join(OUT, name + ".wav")],
            check=True, capture_output=True)
        print(f"{name}: {time.time()-t0:.1f}s")
    names = sorted(os.path.splitext(f)[0] for f in os.listdir(OUT) if f.endswith(".wav"))
    open(os.path.join(OUT, "manifest.txt"), "w").write("\n".join(names))
    print(f"ROBOT DONE — manifest {len(names)}")

if __name__ == "__main__":
    main()
