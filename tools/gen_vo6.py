"""Round-6 VO: SAIGON FM — a Good-Morning-Vietnam-style DJ station in Alex's
voice (station index 2, pool prefix "dj" — audio.gd's TALK_POOLS wires the
whole pool up by name, zero further .gd changes needed).

Reuses gen_vo3's F5-TTS + ffmpeg post chain; rewrites the manifest.

Adds two things the earlier gen_vo*.py rounds lacked (per KB
intelligence/techniques/f5-tts-leading-audio-artifact.md):
  1. a 0.48s leading trim on every raw clip (F5-TTS sometimes leaks the
     reference audio's tail onto the START of generated output — matters
     extra here since radio clips play back-to-back), retried at 0.65s if
  2. ...the transcription check flags residue: every output is re-transcribed
     with the model itself and eyeballed against the expected opening words.

Run: C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo6.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soundfile as sf

from gen_vo3 import post, REF_AUDIO, RAW, OUT

LINES = {
    "dj_1": "Goooood morning, tank commanders! It's oh-six-hundred somewhere, and you are listening to SAIGON FM!",
    "dj_2": "This one goes out to the gunner who forgot to close the breech. We heard it. Everyone heard it.",
    "dj_3": "Traffic report: one tank, several angry planes, and a giant baby. Avoid the nursery.",
    "dj_4": "It's hot! It's loud! It's got treads! You're listening to SAIGON FM. All war, all day.",
    "dj_5": "Weather today: sunny, with a chance of incoming. Keep your hatches closed, people.",
    "dj_6": "A listener asks: can the cabbage man be harmed? Legally? No. Morally? Also no.",
    "dj_7": "Remember troops: the reload lever is red because it misses you.",
    "dj_8": "That was the sound of freedom. This is the sound of a commercial-free half hour on SAIGON FM!",
    "dj_9": "Sports! Someone dunked a basketball with a tank at the gym. That's the whole segment.",
    "dj_10": "A P.S.A. from command: stop honking the horn. I repeat: do NOT stop honking the horn.",
    "dj_11": "If you can hear me, your battery switch is on. Congratulations on completing basic training.",
    "dj_12": "News flash: enemy tanks reported everywhere. In other news, water is wet.",
    "dj_13": "The request line is open! Just kidding, it's a war. Here's more of whatever I want.",
    "dj_14": "SAIGON FM says: check your six, check your fuel, and check on your buddy in the turret.",
    "dj_15": "The moon level is real. We don't talk about how you breathe up there.",
    "dj_16": "And now, a moment of silence for the fourteen trees you flattened getting here. Moving on!",
}

TRIM_S = 0.48
RETRY_TRIM_S = 0.65


def first_words(text: str, n: int = 2) -> str:
    return " ".join(
        "".join(ch for ch in w if ch.isalnum()).lower()
        for w in text.split()[:n]
    )


def main() -> None:
    from f5_tts.api import F5TTS
    tts = F5TTS()
    ref_text = tts.transcribe(REF_AUDIO)
    suspect = []
    for i, (name, text) in enumerate(LINES.items()):
        assert len(text) < 150, f"{name} too long ({len(text)})"
        for attempt, trim_s in enumerate((TRIM_S, RETRY_TRIM_S)):
            wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text,
                                   gen_text=text, seed=660 + i + attempt * 100)
            trim = int(trim_s * sr)
            if len(wav) > trim:
                wav = wav[trim:]
            raw = os.path.join(RAW, name + ".wav")
            sf.write(raw, wav, sr)
            out_path = os.path.join(OUT, name + ".wav")
            post(raw, out_path)
            # verify: the transcript of the OUTPUT should start near the
            # line's own opening words, not with reference-audio residue
            got = tts.transcribe(out_path).strip()
            want = first_words(text)
            got_start = first_words(got)
            ok = want.split()[0] in got_start or got_start.split()[0] in want
            print(f"vo6: {name} attempt {attempt} trim {trim_s}s -> "
                  f"{'OK' if ok else 'SUSPECT'} | got: {got[:70]!r}")
            if ok:
                break
        else:
            suspect.append(name)
    names = sorted(os.path.splitext(f)[0] for f in os.listdir(OUT) if f.endswith(".wav"))
    with open(os.path.join(OUT, "manifest.txt"), "w") as f:
        f.write("\n".join(names))
    print(f"VO6 DONE — {len(names)} total lines in manifest; "
          f"{len(suspect)} suspect: {suspect or 'none'}")


if __name__ == "__main__":
    main()
