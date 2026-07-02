#!/bin/bash
# On-device profiling: install, autostart into a demo scene, sample VrApi,
# screenshot. Usage: profile_device.sh <level> <time 0|1|2> <glow 0|1> <tag>
LEVEL=${1:-beach}
TIME=${2:-1}
GLOW=${3:-1}
FOV=${5:-3}
TAG=${4:-run}
PKG=com.agilelens.tankcommander
FILES=/sdcard/Android/data/$PKG/files

cd /d/Projects/TankCommanderVR

cat > out/autostart.cfg << EOF
[auto]
level="$LEVEL"
vehicle="tank"
mutator=""
time=$TIME
demo=true
delay=6.0
difficulty=1
EOF
cat > out/tuning.cfg << EOF
[tuning]
glow_enabled=$GLOW.0
glow_intensity=0.55
foveation_level=$FOV.0
EOF

adb shell am force-stop $PKG
adb push out/autostart.cfg "/$FILES/autostart.cfg" > /dev/null
adb push out/tuning.cfg "/$FILES/tuning.cfg" > /dev/null
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close > /dev/null
adb logcat -c
adb shell am start -n $PKG/com.godot.game.GodotAppLauncher > /dev/null
echo "[profile] $TAG: launched, warming up 55s..."
sleep 55
# sample 25 s of VrApi
adb logcat -d | grep "VrApi" | grep "FPS=" | tail -25 > out/vrapi_$TAG.txt
echo "[profile] $TAG samples:"
python -c "
import re
txt = open('out/vrapi_$TAG.txt', encoding='utf-8', errors='ignore').read()
fps = [tuple(map(int, m)) for m in re.findall(r'FPS=(\d+)/(\d+)', txt)]
app = [float(m) for m in re.findall(r'App=([\d.]+)ms', txt)]
stale = [int(m) for m in re.findall(r'Stale=(\d+)', txt)]
temps = [float(m) for m in re.findall(r'Temp=([\d.]+)C', txt)]
if app:
    print(f'  samples={len(app)} appFPS min/avg={min(f[0] for f in fps)}/{sum(f[0] for f in fps)/len(fps):.1f}')
    print(f'  App GPU ms min/avg/max={min(app):.2f}/{sum(app)/len(app):.2f}/{max(app):.2f} (budget 13.8)')
    print(f'  stale frames total={sum(stale)}  temp={max(temps) if temps else 0:.1f}C')
else:
    print('  NO VRAPI SAMPLES')
"
echo "[profile] godot errors:"
adb logcat -d | grep -E "SCRIPT ERROR" | head -4
echo "[profile] boot prints:"
adb logcat -d | grep -E "godot.*(\[main\]|\[auto\]|\[tune\]|\[perf\])" | head -6
adb logcat -d | grep -E "godot.*\[perf\]" | tail -3
# screenshot (retry blacks)
for i in 1 2 3 4; do
  adb exec-out screencap -p > out/quest_$TAG.png 2>/dev/null
  s=$(stat -c %s out/quest_$TAG.png 2>/dev/null || echo 0)
  [ "$s" -gt 300000 ] && break
  sleep 3
done
cp out/quest_$TAG.png docs/screenshots/device_$TAG.png 2>/dev/null
echo "[profile] screenshot: $(stat -c %s out/quest_$TAG.png 2>/dev/null) bytes -> docs/screenshots/device_$TAG.png"
