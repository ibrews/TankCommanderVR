"""Round-3 VO: the big batch. ~190 Alex lines in variant pools (F5-TTS) +
character lines via ElevenLabs (cabbage merchant) + a pitched baby voice.
Writes assets/audio/vo/manifest.txt so the game builds variant pools.

Run: ELEVENLABS_API_KEY=... C:/Users/Sam/AppData/Local/Programs/Python/Python312/python.exe tools/gen_vo3.py
"""
import os, subprocess, time, json, urllib.request

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

L = {}
def pool(prefix, lines):
    for i, t in enumerate(lines):
        L[f"{prefix}_{i+2}"] = t   # _1 is the original single, if it exists

# ---- combat pools
pool("vo_wave", [
    "Contacts! Look alive!",
    "Company's coming. Set the table.",
    "Here they come. Try to look intimidating.",
    "Enemies inbound. This is not a drill. Well, it IS a game. But still.",
    "Multiple contacts! Remember your training! Which was that one menu screen!",
    "Incoming! Somebody woke up the whole neighborhood.",
    "They're back. They never learn.",
    "New wave! I'd tell you to be careful but you won't be.",
    "Targets on the horizon. Warm up that breech lever.",
])
pool("vo_wave_clear", [
    "Wave clear! Somebody's getting dessert tonight.",
    "All clear. Stretch your arms. Hydrate. Reload.",
    "Clear! That was honestly pretty impressive.",
    "Wave complete. The tank is very proud of you. I checked.",
    "That's the wave! Take a breath.",
    "Clear! You're making this look easy. It's not. I would know.",
    "Field's clear. For now.",
    "Done and dusted. Mostly dusted.",
])
pool("vo_kill", [
    "Got 'em!",
    "Target down. Beautiful shot.",
    "BOOM. That's going in the highlight reel.",
    "Direct hit! Chef's kiss.",
    "Down! You've done this before, haven't you.",
    "Scratch one! Keep it rolling.",
    "That one's done. Who's next?",
    "Splash one tank. Textbook.",
    "Confirmed kill. The textbook would be jealous.",
    "You got 'em. I felt that from in here.",
    "Another one down. You're on fire. Figuratively. Please check.",
    "Enemy neutralized. Fancy word for KABOOM.",
    "Hit! Right in the sprocket. That's the tank's weak spot. Trust me.",
])
pool("vo_plane_down", [
    "Plane down! That was some shooting.",
    "You hit a MOVING PLANE. From a TANK. Who ARE you?",
    "Splash one aircraft! The sky is a little safer now.",
    "Bird down! Somebody's walking home.",
])
pool("vo_hit", [
    "We're hit! Shake it off!",
    "Taking fire! They found us!",
    "OW. I felt that one in the transmission.",
    "That's gonna leave a dent. Return the favor!",
    "Contact! They're shooting back! Rude!",
    "Armor took it. That's what armor's for. Mostly.",
    "We're okay! We're okay. Probably okay.",
])
pool("vo_hull_low", [
    "Hull's critical! Find cover NOW!",
    "We are one bad decision from a very short walk home. FALL BACK.",
    "Red lights everywhere! That's bad! Red is bad!",
    "Hull integrity is a suggestion at this point. HIDE.",
])
pool("vo_gameover", [
    "Welp. We're done. Pull the yellow handle when you're ready.",
    "That's it. That's the run. Yellow handle when you want revenge.",
    "We gave it everything. Everything wasn't enough. Yellow handle, go again.",
    "Down but not out. Actually pretty out. Yellow handle!",
    "Ouch. On the bright side, great explosion. Yellow handle to retry.",
    "They got us. Write that one down as a learning experience.",
    "Game over, kiddo. The tank forgives you. Yellow handle.",
])
pool("vo_start", [
    "Engine's alive! Let's roll.",
    "She's running! Tillers when you're ready.",
    "That's the sound of freedom. Also diesel. Mostly diesel.",
    "Engine start! Beautiful. Now DRIVE.",
    "We're hot! Gear to D and give 'em trouble.",
])
# ---- flavor pools
pool("vo_idle", [
    "Fun tank fact: this tank has one careful owner. You. Please stay careful.",
    "Remember to blink. VR rules.",
    "I used to be a minivan. Long story.",
    "If you can hear the enemy, the enemy can hear you. Poetry.",
    "Scanning... scanning... nope, just tumbleweeds.",
    "You know what this battlefield needs? A snack bar.",
    "Quiet out there. TOO quiet. Sorry, always wanted to say that.",
    "Pro tip: the horn does not scare tanks. It DOES scare jeeps. Sometimes.",
    "Fuel's fine. Ammo's fine. You're fine. We're all fine here. How are you?",
    "This seat has lumbar support. You're welcome.",
    "Don't make me turn this tank around.",
    "I spy with my little periscope... sand.",
    "Somewhere out there is a tank with your name on it. Rude of them.",
    "Checking the mirrors. We don't have mirrors. Moving on.",
    "If anyone asks, the dent was already there.",
])
pool("vo_fast", [
    "Now THIS is podracing! Wait, wrong franchise.",
    "Whoa! Speed limit is a suggestion out here!",
    "You feel that? That's forty tons having FUN.",
])
pool("vo_mud", [
    "Mud! MUD! We're in the mud!",
    "This is NOT a bath. We talked about this.",
    "The mud pit claims another sock. I mean tank.",
])
pool("vo_ammo_low", [
    "Ammo's getting thin. Make these count.",
    "Running low on shells. Choose your enemies wisely.",
    "Last few rounds! Aim like you mean it.",
])
pool("vo_horn", [
    "HONK. Classic.",
    "Yes! Assert dominance!",
    "The horn changes nothing and yet it changes everything.",
    "Honking will continue until morale improves.",
])
pool("vo_gear_grind", [
    "We're in NEUTRAL, champ. The gear lever. Right pedestal.",
    "Lots of engine, zero motion. Check the gear.",
])
pool("vo_lights", [
    "Lights on! Now they can see us too. Trade-offs!",
    "Let there be light. And also visibility to enemy gunners.",
])
pool("vo_night", [
    "Dark out here. Lights help you see. They also help THEM see YOU.",
    "Night ops. Stay dark, stay quiet, stay sneaky.",
    "Can't see a thing. That's either very good or very bad for us.",
])
pool("vo_spotted", [
    "They see us! So much for sneaky!",
    "Spotted! Kill the lights or start shooting!",
])
# ---- DAD FM expansion
pool("radio_x", [
    "Sports update: the score is tanks, a lot. Everyone else, zero.",
    "This hour of DAD F M is sponsored by Dad's Discount Treads. Treads! For tanks.",
    "We have a caller! Caller, you're on the air. ... They hung up. Tanks are shy.",
    "Now for the news. There is no news. There are only tanks.",
    "Coming up next: two more songs and a weather report I'm going to make up.",
    "If you're just tuning in: WHERE HAVE YOU BEEN.",
    "A listener asks: does the radio work underwater? Kid, NOTHING should work underwater.",
    "Dad joke o'clock: why did the tank break up with the jeep? It needed space. TANK space.",
    "Traffic: one tornado, northbound. Expect delays. Expect flying.",
    "Remember: you can't spell COMMANDER without COMMA. Punctuation matters, kids.",
    "This is the longest anyone has listened to my show. I'm not crying. It's dusty in here.",
    "Requests? We take requests. We only have three songs though.",
    "Breaking: local cabbage merchant reports ANOTHER incident. Investigators baffled.",
    "The gym level is NOT regulation size. We measured. It's fine. Play on.",
    "Weather: a chance of everything, all at once, forever. Back to the tunes.",
    "PSA: the breech lever is the red one. The OTHER red one. You'll figure it out.",
    "Rumor says holding every trigger and A does something. I would NEVER. You didn't hear this.",
    "And now, silence. Radio silence. It's a format experiment. Shhh.",
    "Good morning! Or afternoon. Time is soup in here.",
    "That last song goes out to the mortar crew who keeps missing. Bless your hearts.",
    "Stay hydrated, stay loaded, stay away from the volcano level. DAD F M!",
    "You're not lost. You're EXPLORING. That's the DAD F M promise.",
])
# ---- level intros
pool("vo_beach", [
    "Beach level! Sunscreen on. Turret at the ready.",
    "Smell that? Salt air and diesel. Vacation!",
    "Remember: no running by the pool. Tanks are fine though.",
])
pool("vo_island", [
    "Welcome to the island. Population: us and everyone shooting at us.",
    "One island. One tank. No ferry. Make it count.",
])
pool("vo_volcano", [
    "Volcano bridges. Do NOT look down. Okay, look a LITTLE.",
    "The floor is lava. Not a game this time. Actually lava.",
    "Stay on the bridges. The lava has no customer service department.",
    "Whose idea was a tank battle INSIDE a volcano? Oh right. Mine.",
])
pool("vo_babyroom", [
    "Uh. We appear to be very small. Or everything else is very big.",
    "That's a baby. That's a GIANT BABY. Avoid the baby.",
    "Watch the floor for blocks. And the sky for baby.",
    "New rule: if the ground shakes, MOVE.",
    "Somewhere a toy box is missing its favorite tank. That's us. We're the toy.",
])
pool("vo_hide", [
    "Hide and seek rules: they seek. You hide. Then you SURPRISE them.",
    "Stay low, stay dark. Jump out when it's funny.",
])
# ---- vehicles
pool("vo_heli", [
    "Helicopter mode! Collective on the left. Gentle. GENTLE.",
    "Rotors up! The ground is optional now.",
    "Hovering is just falling with style and a rebuttal.",
])
pool("vo_runner", [
    "No tank. Just you and incredibly fast legs. GO.",
    "You are the fastest thing on this battlefield. Biology is confused.",
    "Cardio mode! The enemy has armor. You have ZOOMIES.",
])
pool("vo_biplane", [
    "Biplane! Twice the wings, twice the style.",
    "This plane is a hundred years old. Treat her nice.",
])
# ---- easter egg reactions
pool("vo_cabbage", [
    "...Did that guy just yell about cabbages?",
    "We are NOT paying for that cabbage stand.",
])
pool("vo_creeper", [
    "Why is that bush hissing. WHY IS THAT BUSH HISSING.",
    "Green thing! Hissing! BACK UP BACK UP BACK UP.",
])
pool("vo_toys", [
    "The little green army men are on OUR side. I checked. Twice.",
    "Careful with the toys. Some of them have feelings. Probably.",
])
pool("vo_eggmisc", [
    "Red five standing by? No? Just me? Okay.",
    "Yer a tank commander, kiddo.",
    "Life is unfair. Reload anyway.",
    "This block placement is very... crafty. Somebody mined it, I guess.",
    "To infinity! And... about two hundred meters. That's the arena limit.",
])

def eleven(voice_id, text, out_raw, key):
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
        data=json.dumps({"text": text, "model_id": "eleven_turbo_v2_5",
            "voice_settings": {"stability": 0.35, "similarity_boost": 0.7, "style": 0.6}}).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        open(out_raw, "wb").write(r.read())

def post(raw, out, extra_af=""):
    af = ("equalizer=f=3500:t=q:w=1.2:g=-4,equalizer=f=7000:t=q:w=1.2:g=-3,"
          "equalizer=f=250:t=q:w=1.0:g=2,"
          "silenceremove=start_periods=1:start_threshold=-45dB,"
          "areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
          "loudnorm=I=-18:TP=-1.5")
    if extra_af:
        af = extra_af + "," + af
    subprocess.run(["ffmpeg", "-y", "-i", raw, "-af", af, "-ar", "22050", "-ac", "1", out],
        check=True, capture_output=True)

def main():
    print(f"Generating {len(L)} Alex lines...")
    tts = F5TTS()
    ref_text = tts.transcribe(REF_AUDIO)
    done = 0
    for name, text in L.items():
        assert len(text) < 150, f"{name} too long ({len(text)})"
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text, gen_text=text, seed=42 + done)
        raw = os.path.join(RAW, name + ".wav")
        sf.write(raw, wav, sr)
        post(raw, os.path.join(OUT, name + ".wav"))
        done += 1
        if done % 20 == 0:
            print(f"  {done}/{len(L)}")
    # ---- characters (ElevenLabs George = the cabbage merchant)
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    char_lines = {
        "char_cabbage_1": "MY CABBAGES!!",
        "char_cabbage_2": "No! No no no! Not the cabbages!",
        "char_cabbage_3": "WHY?! What did the cabbages ever do to you?!",
        "char_cabbage_hello": "Cabbages! Fresh cabbages! Very sturdy! Please do not test that!",
    }
    if key:
        for name, text in char_lines.items():
            try:
                raw = os.path.join(RAW, name + ".mp3")
                eleven("JBFqnCBsd6RMkjVDRZzb", text, raw, key)
                post(raw, os.path.join(OUT, name + ".wav"))
                print("11L:", name)
            except Exception as e:
                print("11L FAILED", name, e)
    # ---- giant baby = Alex pitched way up (funnier than any TTS)
    baby_lines = {
        "char_baby_1": "Goo goo. Ga ga. BOOM boom!",
        "char_baby_2": "Tiny tank! Tiny tiny tank!",
        "char_baby_3": "Hee hee hee hee!",
    }
    for name, text in baby_lines.items():
        wav, sr, _ = tts.infer(ref_file=REF_AUDIO, ref_text=ref_text, gen_text=text, seed=7)
        raw = os.path.join(RAW, name + ".wav")
        sf.write(raw, wav, sr)
        post(raw, os.path.join(OUT, name + ".wav"),
            extra_af="asetrate=22050*1.45,aresample=22050,atempo=0.8")
        print("baby:", name)
    # ---- manifest of every vo file
    names = sorted(os.path.splitext(f)[0] for f in os.listdir(OUT) if f.endswith(".wav"))
    with open(os.path.join(OUT, "manifest.txt"), "w") as f:
        f.write("\n".join(names))
    print(f"VO3 DONE — {len(names)} total lines in manifest")

if __name__ == "__main__":
    main()
