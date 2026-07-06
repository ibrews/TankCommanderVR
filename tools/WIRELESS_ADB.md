# Wireless ADB for Meta Quest

Setting up and managing wireless ADB to Quest headsets from this dev machine
(bash/git-bash conventions, matching [tools/pull_logs.sh](pull_logs.sh)).

## 1. One-time per-boot pairing

The Quest has no persistent wireless-ADB toggle — you need USB once per
headset **boot session** (not per `adb connect`).

1. Plug the headset in via USB, put on the headset and accept the "Allow USB
   debugging?" prompt if it appears.
2. Confirm the machine and headset are on the same LAN/subnet.
3. Switch that device to TCP/IP mode:
   ```
   $ADB_PATH tcpip 5555
   ```
4. Find its Wi-Fi IP:
   ```
   $ADB_PATH shell ip route   # look for the wlan0 line's "src <ip>"
   ```
5. Connect wirelessly and unplug the cable:
   ```
   $ADB_PATH connect <ip>:5555
   ```

`ADB_PATH` in this repo's tooling defaults to
`C:/Users/Sam/AppData/Local/Android/Sdk/platform-tools/adb.exe` (see
`tools/pull_logs.sh`'s `ADB_PATH` env var) — export it once per shell if
that's not already your default `adb`.

## 2. Durability across reboots

Wi-Fi debugging resets to USB-only on every headset reboot — repeat step 1's
USB round-trip once per boot, then wireless `connect` works until the
headset reboots or its Wi-Fi radio drops.

## 3. Different networks (Tailscale)

Quest doesn't run Tailscale itself, so this only helps if there's already a
Tailscale subnet router advertising the headset's LAN — point `adb connect`
at the headset's LAN IP through that route. If there's no subnet router on
the headset's network, there's no way around being on the same LAN/Wi-Fi.

## 4. Multi-headset workflow

```
$ADB_PATH devices -l                 # list everything (USB + wireless)
$ADB_PATH -s <serial-or-ip:5555> ... # target one explicitly
bash tools/pull_logs.sh              # loops every `adb devices` entry automatically
```

## 5. Common gotchas

- **`adb.exe: more than one device/emulator`** — you ran a command with no
  `-s <serial>` while 2+ devices are attached (common right after `connect`,
  since the USB entry often stays listed alongside the new wireless one).
  Always pass `-s`, or `adb disconnect` the USB path once wireless is up.
- **Connection silently drops** — the headset's Wi-Fi radio sleeps on
  standby. Wake the headset, then `adb connect <ip>:5555` again (no cable
  needed unless it actually rebooted).
- **`failed to connect: Connection refused`** — TCP/IP mode didn't survive a
  reboot; redo the USB round-trip (step 1).

## 6. Troubleshooting checklist

- [ ] Headset awake (not in sleep/standby)?
- [ ] Headset and dev machine on the same Wi-Fi network/subnet?
- [ ] Did the headset reboot since the last `tcpip 5555`? → redo USB step.
- [ ] `adb devices` shows it as `device`, not `unauthorized`/`offline`?
- [ ] Router/firewall not blocking port 5555 on the LAN?
