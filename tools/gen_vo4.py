"""Round-4 VO: endless-tour travel callouts, endless menu reaction, help
toggle. Reuses gen_vo3's F5-TTS + ffmpeg post chain; rewrites the manifest.

Run: C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo4.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soundfile as sf

from gen_vo3 import post, REF_AUDIO, RAW, OUT

LINES = {
    # endless tour: travel between battlefields
    "vo_travel_1": "Pack it up! Next battlefield, straight ahead!",
    "vo_travel_2": "Tour rolls on! I wonder where we're headed.",
    "vo_travel_3": "Movement orders just came in. Hold on to something!",
    "vo_travel_4": "New terrain, same tank. Let's roll!",
    "vo_travel_5": "That's a wrap here. NEXT!",
    # menu: picking ENDLESS TOUR
    "vo_endless_2": "Endless tour! We fight until someone says dinner time.",
    "vo_endless_3": "The world tour! Every battlefield, back to back. I love it.",
    "vo_endless_4": "Endless mode. I never run out of things to say. Probably.",
    # menu: switching help back on
    "vo_help_on_2": "Coaching is back on! I've got your back, commander.",
    "vo_help_on_3": "Help restored. It's okay. Everyone forgets the fuel pump.",
}


def main() -> None:
    from f5_tts.api import F5TTS
    tts = F5TTS()
    ref_text = tts.transcribe(REF_AUDIO)
    for i, (name, text) in enumerate(LINES.items()):
        assert len(text) < 150, f"{name} too long ({len(text)})"
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text,
                               gen_text=text, seed=440 + i)
        raw = os.path.join(RAW, name + ".wav")
        sf.write(raw, wav, sr)
        post(raw, os.path.join(OUT, name + ".wav"))
        print("vo4:", name)
    names = sorted(os.path.splitext(f)[0] for f in os.listdir(OUT) if f.endswith(".wav"))
    with open(os.path.join(OUT, "manifest.txt"), "w") as f:
        f.write("\n".join(names))
    print(f"VO4 DONE — {len(names)} total lines in manifest")


if __name__ == "__main__":
    main()
