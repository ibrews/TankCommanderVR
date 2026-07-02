"""Round-5 VO: naval update — gunboat pick, ship kills. Reuses gen_vo3's
F5-TTS + ffmpeg post chain; rewrites the manifest.

Run: C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo5.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soundfile as sf

from gen_vo3 import post, REF_AUDIO, RAW, OUT

LINES = {
    "vo_boat_2": "The gunboat! Now we're a navy. A very small navy.",
    "vo_boat_3": "Boat mode! Remember: the ocean is the road now.",
    "vo_boat_4": "Gunboat selected. Try not to park it on the beach.",
    "vo_sunk_2": "She's going down! Direct hit!",
    "vo_sunk_3": "Enemy ship sunk! The fish send their thanks.",
    "vo_sunk_4": "That one's a submarine now. A bad one.",
    "vo_ship_2": "Warship on the horizon! Watch those big guns.",
    "vo_ship_3": "Enemy ships in the channel! Keep moving!",
}


def main() -> None:
    from f5_tts.api import F5TTS
    tts = F5TTS()
    ref_text = tts.transcribe(REF_AUDIO)
    for i, (name, text) in enumerate(LINES.items()):
        assert len(text) < 150, f"{name} too long ({len(text)})"
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text,
                               gen_text=text, seed=550 + i)
        raw = os.path.join(RAW, name + ".wav")
        sf.write(raw, wav, sr)
        post(raw, os.path.join(OUT, name + ".wav"))
        print("vo5:", name)
    names = sorted(os.path.splitext(f)[0] for f in os.listdir(OUT) if f.endswith(".wav"))
    with open(os.path.join(OUT, "manifest.txt"), "w") as f:
        f.write("\n".join(names))
    print(f"VO5 DONE — {len(names)} total lines in manifest")


if __name__ == "__main__":
    main()
