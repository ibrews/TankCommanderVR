# Tank Commander VR — server (Cloudflare Worker)

One Worker, two jobs:

1. **Multiplayer relay** — `wss://tank-commander.<subdomain>.workers.dev/ws`
   (or `/ws/<roomcode>`). Pure broadcast Durable Object, no server authority.
   Default room `main` is the **always-on persistent-host fallback**: when a
   client finds no LAN host, it connects here so a game is always joinable.
2. **Log / session-data sink** — `POST /logs` writes uploaded headset logs to
   a KV namespace so we can pull them from anywhere, no cabling.

Pattern reference:
`knowledge/intelligence/techniques/cloudflare-durable-object-multiplayer-relay-pattern.md`

## Deploy (one-time setup)

```bash
cd multiplayer
npx wrangler login                       # browser OAuth, once per machine
npx wrangler kv namespace create LOGS    # paste the printed id into wrangler.toml
npx wrangler deploy
```

Local dev: `npx wrangler dev` (no login needed to iterate).

## Client protocol (for net.gd — Godot WebSocketPeer)

Connect to `/ws` (or `/ws/<room>`). Messages are JSON.

Server → client lifecycle:
- `{type:'welcome', id, color, host, roster:[{id,color}...]}` — on connect.
- `{type:'join', id, color}` / `{type:'leave', id}`.

Client → server:
- `{type:'state', s:{...}}` — high-freq own state. Relayed to others as
  `{type:'state', id, color, s}` (sender excluded). Put pos/rot/vehicle/seat/
  score/name/team in `s`.
- **Any other type** is stamped `{...msg, byId, byColor, byHost}` and
  broadcast to everyone (set `echo:false` to exclude yourself). Use this for
  round timers, scoring, host map/mode/bot control, hits, seat-switch, etc.
  No Worker redeploy needed to add message types.
- `{type:'analytics', report:{playSeconds, crashed, errors:[...]}}` — server
  aggregates, no broadcast.

## Logs

- Upload (from the game / a headset):
  `POST /logs?device=<name>&kind=<crash|session|manual>` with the log text as
  the body. Add an "Upload Logs" button in the menu that fires this.
- Pull them back (from any machine):
  - `GET /logs/list?token=<LOG_TOKEN>` — list keys + metadata.
  - `GET /logs/get?token=<LOG_TOKEN>&key=<key>` — one log's text.
  - or `npx wrangler kv key list --binding LOGS` / `kv key get <key> --binding LOGS`.

`LOG_TOKEN` is in `wrangler.toml` `[vars]`.
