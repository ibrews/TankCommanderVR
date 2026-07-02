#!/bin/bash
# Export the Quest APK headless, with the Godot hang-on-exit guard
# (kb: godot-metahuman-quest-standalone — Godot often hangs after writing the
# APK, holding the gradle lock; poll for a stable APK then kill leftovers).
GODOT="/d/Projects/godot-rtx-demos/godot-4.7/Godot_v4.7-beta3_win64_console.exe"
PROJ=/d/Projects/TankCommanderVR
APK="$PROJ/out/TankCommanderVR.apk"

cd "$PROJ" || exit 1
mkdir -p out
rm -f "$APK"
echo "[build] exporting..."
"$GODOT" --headless --path . --export-release "Meta Quest" "$APK" > export.log 2>&1 &

ok=0
for i in $(seq 1 200); do
	sleep 5
	if [ -f "$APK" ]; then
		sz1=$(stat -c %s "$APK" 2>/dev/null || echo 0)
		sleep 6
		sz2=$(stat -c %s "$APK" 2>/dev/null || echo 0)
		if [ "$sz1" = "$sz2" ] && [ "$sz1" -gt 10000000 ]; then
			ok=1
			echo "[build] APK stable at $sz2 bytes"
			break
		fi
	fi
	if grep -q "BUILD FAILED" export.log 2>/dev/null; then
		echo "[build] GRADLE BUILD FAILED"
		break
	fi
done

# hang-on-exit guard: kill leftover godot + gradle daemons holding the lock
taskkill //F //IM Godot_v4.7-beta3_win64_console.exe 2>/dev/null
taskkill //F //IM Godot_v4.7-beta3_win64.exe 2>/dev/null
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='java.exe'\" | Where-Object { \$_.CommandLine -match 'gradle' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" 2>/dev/null

echo "[build] --- last log lines:"
tail -8 export.log
if [ "$ok" = "1" ]; then
	ls -la "$APK"
	echo "[build] SUCCESS"
else
	echo "[build] FAILED — see export.log"
	grep -E "ERROR|error:|FAILED" export.log | head -20
	exit 1
fi
