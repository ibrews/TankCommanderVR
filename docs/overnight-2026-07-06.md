# Overnight session — 2026-07-06

Running ledger. Morning summary will be written at the top once everything lands.

## Status: IN PROGRESS (session started ~05:45 UTC)

## Deliverable 0 — wireless log gathering
- DONE: `adb tcpip 5555` + `adb connect 192.168.86.142:5555` — Quest 3S now reachable wirelessly (serial `4597C10H3N01KG`, also visible as `192.168.86.142:5555`).
- DONE: [tools/pull_logs.sh](../tools/pull_logs.sh) — pulls logcat (full + filtered), tombstones, Godot user:// log dir, device info for every `adb devices` entry into `docs/logs/<timestamp>/<serial>/`.
- DONE: first pull ran — `docs/logs/20260706-054556/`. No godot/tankcommander logcat lines found (game hasn't been run recently on this boot) and no tombstones. Godot user:// log dir was empty because **file logging wasn't enabled in the project** — fixed: added `[debug]` section to [project.godot](../project.godot) (`file_logging/enable_file_logging=true`, `log_path="user://logs/godot.log"`). This needs a rebuild+reinstall before it takes effect — future runs will have persistent on-device logs even without a live adb session.
- IN PROGRESS: gemini writing `tools/WIRELESS_ADB.md` runbook.
- DONE (free): gemma triage of pre-existing `mp_join.log`/`mp_host.log` (desktop smoke-test logs already in repo root) → `docs/logs/gemma_triage_mp.md`. gemma changelog draft → `docs/logs/gemma_changelog.md`. gemma targeted crash-pattern scan (self-free-during-signal bugs like the energy drink one) → `docs/logs/gemma_crash_scan.md`.
- NOTE: only ONE physical Quest was connected this session — the real two-headset MP join crash could not be live-reproduced. Root-caused via code review instead (see below); needs a real two-headset verification pass.

## Crash fixes
- DONE (me, verified by code reading, not yet on-device tested): **energy drink crash** — [scripts/pickables/energy_drink.gd](../scripts/pickables/energy_drink.gd) `_on_action_pressed` was calling `drop_and_free()` synchronously from inside the `action_pressed` signal handler. `drop_and_free()` → `drop()` → `function_pickup.gd`'s `drop_object()` sets `picked_up_object = null` *before* returning control to `function_pickup.gd`'s `_on_button_pressed()`, which immediately re-reads `picked_up_object.has_method("controller_action")` right after calling `action()` — a null-deref crash on device (addon bug, triggered by any pickable that self-frees synchronously from `action_pressed`). Fixed by deferring: `call_deferred("drop_and_free")`. Flagged this exact pattern to gemma to scan the rest of `scripts/pickables/*.gd` for repeats.
- IN PROGRESS (opus subagent): MP join crash root-cause in `scripts/net.gd` + peer spawn — see task list below.

## Delegated work (background agents, isolated worktrees)
| # | Owner | Task | Status |
|---|---|---|---|
| 2 | opus | MP join crash + MP vehicle-choice-ignored bug | running |
| 5 | opus | Spider-Man: pickup-gated powers + climb-anything | running |
| 6/7/8 | sonnet | energy drink polish (FX/crush-can) + coffee effect + wifi-gate bug | running |
| 9/12/13 | sonnet | lobby diorama fix + weather fog + volcano level + baby boss | running |
| 10/11 | sonnet | vehicle enter/exit + right-trigger-forward + jeep wheel + plane facing + runner turn/sprint | running |
| 16 | sonnet | pre-lobby splash screen | running |
| 17 | fable | 2-3 new procedural weapons | running |
| 18 | fable | store cubemap face fix | running |
| 19 | gemini | Oculus username API research, splash patterns research | running |

**Held back, sequential after #2 lands** (all touch `scripts/net.gd` heavily — running in parallel would guarantee merge conflicts):
- #3: round timer/scoring, host god-mode (map/mode/difficulty/bots), co-op seat-switch hotkey — folding in player display names (self-reported at connect) + pause-menu player/score display + team color/team mode/avatar four-arms clarity fix, since those all touch net.gd/game.gd too.
- #4: Cloudflare Durable Object persistent-host fallback — needs #2 and #3's net.gd state as a base. gemini will review the integration plan against `C:\Users\Sam\knowledge\intelligence\techniques\cloudflare-durable-object-multiplayer-relay-pattern.md` before implementation starts.

## Merge/build plan
Each agent commits in its own isolated worktree (no version bump — that's centralized here to avoid every agent racing on `build_info.gd`/`export_presets.cfg`). As each lands: review diff → merge into this branch → batch up a few landed features → bump version (`export_presets.cfg` + `build_info.gd` via `tools/build_apk.sh`'s existing stamp step) → build APK → install+launch on the connected Quest → smoke-test → commit.

## IMPORTANT: agent worktree staleness bug (confirmed persistent, not a race)

**Every** `isolation:"worktree"` agent this session branches from `4f19e66` — a fixed commit that was already 51+ commits behind master when the session started, and now even further behind as master advances. Confirmed by checking a freshly-launched agent's worktree base immediately after creation (still `4f19e66`, not current tip) — this rules out a launch-order race; it looks like the harness snapshots one base ref for the whole session's worktree-isolation feature rather than reading live HEAD each time. **Standing workflow going forward: every agent branch gets `git rebase --onto master 4f19e66 <branch>` before merging, no exceptions**, resolving conflicts by hand, then `git merge --no-ff`. Successfully done for: splash screen (1 conflict in main.gd), Spider-Man rework (3 conflicts — terrain.gd/world_dressing.gd/xr_rig.gd all had *independently converged* on nearly the same "make the world climbable" idea as a commit already on master, since the agent's stale base predated that commit; reconciled by hand), coffee/energy-drink/wifi (1 conflict, plus had to un-stage `docs/logs/` and a stray store-art jpg that `git add -A` swept in during conflict resolution — watch for that every time), MP join-crash fix (0 conflicts, clean).

## Live Cloudflare Worker (deployed by a parallel session, not me)

Alex/a parallel session already deployed the persistent-host relay + log sink: **`https://tank-commander.alexcoulombe.workers.dev`**
- Relay: `wss://tank-commander.alexcoulombe.workers.dev/ws` (or `/ws/<roomcode>`) — default room `main` is the always-on fallback when no LAN host is found. First socket into a fresh room gets `host:true` — feeds host-god-mode.
- Log upload (no auth): `POST .../logs?device=<name>&kind=<crash|session|manual>`, raw log text body.
- Log retrieval (token-gated): `GET .../logs/list?token=tc-fort-logs-8b41c2a9`, `GET .../logs/get?token=...&key=<key>`.
- Source of truth: `multiplayer/worker.js` / `multiplayer/README.md` in this repo. **I do not need to run `wrangler deploy` myself** — just build the Godot `WebSocketPeer` client + reconnect/backoff, and add an "Upload Logs" menu button that POSTs to `/logs` (this is now the PRIMARY log-gathering path for headsets that aren't on-site/on the same LAN — wireless-adb via `tools/pull_logs.sh` is the secondary/local-network path). This unblocks Task #4 fully.

## Discoveries worth flagging

- **`multiplayer/` Cloudflare Worker scaffold already exists, untracked, uncommitted.** Someone (a prior session, per KB `intelligence/techniques/cloudflare-durable-object-multiplayer-relay-pattern.md`) already built [multiplayer/worker.js](../multiplayer/worker.js) + [wrangler.toml](../multiplayer/wrangler.toml): a generalized Durable-Object relay (`/ws[/room]`, generic message stamping instead of hardcoded attacker/victim types — cleaner than the KB reference) **plus a log-upload/download sink** (`POST /logs`, `GET /logs/list`, `GET /logs/get`) that would let headsets ship crash/session logs over the internet with zero cabling — directly serves the "future headsets don't need plugging in" goal. `wrangler` CLI is installed and already authenticated (`npx wrangler whoami` succeeds) on this machine. wrangler.toml already has a real KV namespace id + a `LOG_TOKEN` filled in (not a placeholder) — unclear if this was ever actually deployed; needs checking. This massively narrows Task #4's scope down to: Godot `WebSocketPeer` client + reconnect/backoff (client-side, doesn't exist yet) + wiring the fallback into `NetManager.search()`, and optionally wiring the `/logs` upload endpoint into the game as a "always available" log channel. **I (orchestrator) will do the actual `wrangler deploy` myself** rather than delegate it — it's the one truly external, hard-to-reverse action in this whole session (creates a public internet-reachable endpoint under Alex's Cloudflare account). Will call it out clearly here once done so Alex can rotate the token or tear it down if unwanted.
- **"Four arms" avatar bug — likely root cause found.** [scripts/controller_visual.gd](../scripts/controller_visual.gd) attaches a realistic MIT-licensed Touch-Plus controller **glb model** (imported asset — this one pre-existing exception predates this session, not something I added) directly to each hand's XR transform. [scripts/avatar_rig.gd](../scripts/avatar_rig.gd) *separately* builds a full procedural arm+forearm+hand per side reaching for that same hand position. Nothing found so far hides one when the other is showing for the on-foot local player — likely both render simultaneously, reading as "four arms" (two controller models + two procedural arm/hand meshes, all near the same points). Queued for the next work round (task 14) once the current xr_rig.gd-touching agents (Spider-Man, vehicle/runner) land, to avoid stacking a third concurrent editor on that file.

## Blocked / needs Alex
- **Store cubemap**: `docs/store-art/cubestrip_12288x2048.jpg` was regenerated with the fixed face orientation (root cause: `tools/cubestrip_capture.gd` treated GL cubemap slot names literally instead of per the actual sampling convention — see commit history). Needs a manual re-upload to the Meta Quest Developer Dashboard store listing; I can't do that step. Also worth deciding whether to delete the now-superseded `cubestrip_alt*.jpg` variants in `docs/store-art/` (all share the same wrong-orientation root cause).
