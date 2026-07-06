#!/bin/bash
# Wireless/USB log gathering for Tank Commander VR. For every device seen by
# `adb devices`, pulls: full logcat (this boot), tombstones (native crashes),
# and the Godot user:// log dir off external storage. Drops everything under
# docs/logs/<timestamp>/<device-serial>/ so gemma/gemini/us can triage later.
#
# Usage: tools/pull_logs.sh
# Requires: ADB_PATH env var or adb on PATH; devices already `adb connect`ed
# (see tools/WIRELESS_ADB.md for one-time pairing).
set -uo pipefail

ADB="${ADB_PATH:-C:/Users/Sam/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
PKG="com.agilelens.tankcommander"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP=$(date -u '+%Y%m%d-%H%M%S')
OUT="$PROJ/docs/logs/$STAMP"
mkdir -p "$OUT"

echo "[pull_logs] output dir: $OUT"

DEVICES=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
if [ -z "$DEVICES" ]; then
	echo "[pull_logs] no devices found (adb devices shows none in 'device' state)"
	exit 1
fi

for SERIAL in $DEVICES; do
	SAFE=$(echo "$SERIAL" | tr ':.' '__')
	DDIR="$OUT/$SAFE"
	mkdir -p "$DDIR"
	echo "[pull_logs] === $SERIAL -> $DDIR ==="
	A="$ADB -s $SERIAL"

	echo "[pull_logs] logcat (full buffer, this boot)..."
	$A logcat -d -v threadtime > "$DDIR/logcat.txt" 2>"$DDIR/logcat.err"
	echo "[pull_logs] logcat filtered to godot/tankcommander..."
	grep -iE "godot|tankcommander|fatal|crash|tombstone" "$DDIR/logcat.txt" > "$DDIR/logcat_filtered.txt" 2>/dev/null

	echo "[pull_logs] tombstones..."
	mkdir -p "$DDIR/tombstones"
	TSTONES=$($A shell su 0 ls /data/tombstones 2>/dev/null || $A shell ls /data/tombstones 2>/dev/null)
	if [ -n "$TSTONES" ]; then
		for T in $TSTONES; do
			$A pull "/data/tombstones/$T" "$DDIR/tombstones/" 2>>"$DDIR/tombstones/pull.err"
		done
	else
		echo "(none readable without root — see pull.err)" > "$DDIR/tombstones/README.txt"
	fi

	echo "[pull_logs] Godot user:// log dir..."
	mkdir -p "$DDIR/godot_user_log"
	$A pull "/sdcard/Android/data/$PKG/files/logs" "$DDIR/godot_user_log/" 2>"$DDIR/godot_user_log/pull.err"

	echo "[pull_logs] app + device info..."
	{
		echo "serial: $SERIAL"
		$A shell getprop ro.product.model
		$A shell getprop ro.build.version.release
		$A shell dumpsys package "$PKG" | grep -E "versionName|versionCode"
	} > "$DDIR/device_info.txt" 2>&1

	echo "[pull_logs] done with $SERIAL"
done

echo "[pull_logs] all devices done. Contents:"
find "$OUT" -type f | sort
