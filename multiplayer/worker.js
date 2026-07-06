// Tank Commander VR — Cloudflare Worker + Durable Object.
//
// Two jobs in one Worker:
//   1. MULTIPLAYER RELAY (/ws, /ws/<room>) — a pure broadcast relay Durable
//      Object, no server-side game authority. Ported from Swing City's
//      worker.js (see knowledge KB: cloudflare-durable-object-multiplayer-
//      relay-pattern.md). Generalized: instead of hardcoding this game's
//      message types, the DO relays ANY message it doesn't specially handle
//      by stamping the sender id and re-broadcasting — so the game can add
//      round/scoring/host-control/hit message types WITHOUT redeploying.
//   2. LOG / SESSION-DATA SINK (POST /logs) — headsets upload crash logs and
//      session data over the internet into a KV namespace, so we can pull
//      them from any machine (via `wrangler kv key get` or GET /logs/get)
//      without ever plugging a headset in. This is the "grab session data
//      without cabling" requirement.
//
// Uses the WebSocket Hibernation API (state.acceptWebSocket) so idle rooms
// don't pin the Durable Object in memory. Per-socket metadata (id, color)
// rides on tags so it survives hibernation.

const COLORS = [0xff5566, 0x55ddff, 0xffe066, 0x8fff8f, 0xc98fff, 0xff9f4d];

function hslToHex(h, s, l) {
  const k = n => (n + h * 12) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  const toHex = n => Math.round(f(n) * 255);
  return (toHex(0) << 16) | (toHex(8) << 8) | toHex(4);
}

const EST_FMT = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' });
function estDateKey() { return EST_FMT.format(new Date()); }

export class Room {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  // Assign each connected socket a distinct color from the palette; fall back
  // to a generated hue past 6 concurrent players.
  pickUniqueColor() {
    const used = new Set();
    for (const ws of this.state.getWebSockets()) {
      const tags = this.state.getTags(ws);
      used.add(Number(tags[1]));
    }
    const free = COLORS.filter(c => !used.has(c));
    if (free.length) return free[Math.floor(Math.random() * free.length)];
    let hue = Math.random();
    for (let tries = 0; tries < 50; tries++) {
      const hex = hslToHex(hue, 0.65, 0.6);
      if (!used.has(hex)) return hex;
      hue = (hue + 0.17) % 1;
    }
    return COLORS[Math.floor(Math.random() * COLORS.length)];
  }

  // Roster of everyone currently connected (id + color) — sent to a joiner so
  // it can spawn existing avatars immediately, and useful for host UIs.
  roster(exceptWs) {
    const out = [];
    for (const ws of this.state.getWebSockets()) {
      if (ws === exceptWs) continue;
      const [id, colorStr] = this.state.getTags(ws);
      out.push({ id, color: Number(colorStr) });
    }
    return out;
  }

  async fetch(request) {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('expected websocket', { status: 426 });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    const id = crypto.randomUUID();
    const color = this.pickUniqueColor();
    // First socket to connect to a fresh room is flagged host=1 in a third
    // tag, so the game can grant "host is god" powers to whoever opened the
    // room. If the host leaves, the game may promote via its own message.
    const isHost = this.state.getWebSockets().length === 0 ? '1' : '0';
    this.state.acceptWebSocket(server, [id, String(color), isHost]);

    server.send(JSON.stringify({ type: 'welcome', id, color, host: isHost === '1', roster: this.roster(server) }));

    // Announce the newcomer to everyone already here.
    for (const ws of this.state.getWebSockets()) {
      if (ws === server) continue;
      ws.send(JSON.stringify({ type: 'join', id, color }));
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    let msg;
    try { msg = JSON.parse(message); } catch { return; }
    const [id, colorStr, hostFlag] = this.state.getTags(ws);

    if (msg.type === 'state') {
      // High-frequency per-player state (pos/rot/vehicle/seat/score/name/etc).
      // Relayed verbatim to everyone EXCEPT the sender; the DO keeps no
      // authority over it. Whatever fields the game puts in `s` pass through.
      this.broadcast({ type: 'state', id, color: Number(colorStr), s: msg.s }, ws);
      return;
    }

    if (msg.type === 'analytics' && msg.report && typeof msg.report === 'object') {
      // Server-side only; small day-keyed aggregate. Bulk log text goes
      // through POST /logs (KV), not here.
      await this.recordAnalytics(msg.report);
      return;
    }

    // GENERIC RELAY: any other message type is stamped with the sender's id
    // (as `byId`) and re-broadcast. Set msg.echo === false to exclude the
    // sender (for effects the sender already applied locally); default
    // includes the sender so world/host/round events apply from one code
    // path on every client. This is what lets the game add round timers,
    // scoring, host map/mode/bot control, hit resolution, seat-switching,
    // etc. without changing this Worker.
    const out = { ...msg, byId: id, byColor: Number(colorStr), byHost: hostFlag === '1' };
    this.broadcast(out, msg.echo === false ? ws : undefined);
  }

  async recordAnalytics(report) {
    const key = 'analytics:' + estDateKey();
    const agg = (await this.state.storage.get(key)) || { reportCount: 0, totalPlaySeconds: 0, crashCount: 0, errorSamples: [] };
    agg.reportCount++;
    agg.totalPlaySeconds += typeof report.playSeconds === 'number' ? Math.max(0, report.playSeconds) : 0;
    if (report.crashed) agg.crashCount++;
    if (Array.isArray(report.errors)) {
      for (const e of report.errors) if (agg.errorSamples.length < 30) agg.errorSamples.push(String(e).slice(0, 300));
    }
    await this.state.storage.put(key, agg);
  }

  async webSocketClose(ws) {
    const [id] = this.state.getTags(ws);
    this.broadcast({ type: 'leave', id }, ws);
  }
  async webSocketError(ws) {
    const [id] = this.state.getTags(ws);
    this.broadcast({ type: 'leave', id }, ws);
  }

  broadcast(obj, exclude) {
    const json = JSON.stringify(obj);
    for (const ws of this.state.getWebSockets()) {
      if (ws === exclude) continue;
      try { ws.send(json); } catch { /* socket gone; hibernation cleans up */ }
    }
  }
}

// ---- Log sink (KV) ----------------------------------------------------------

function cors(extra = {}) {
  return { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': '*', ...extra };
}

async function handleLogUpload(request, env, url) {
  // POST /logs?device=<name>&kind=<crash|session|manual>  body: raw log text
  // (or JSON). No auth on upload (low-stakes crash text from our own app);
  // reads ARE token-gated. Stored in KV under log:<date>/<device>/<ts>.
  const device = (url.searchParams.get('device') || 'unknown').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 48);
  const kind = (url.searchParams.get('kind') || 'session').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 24);
  const body = await request.text();
  if (!body) return new Response(JSON.stringify({ ok: false, error: 'empty body' }), { status: 400, headers: cors({ 'Content-Type': 'application/json' }) });
  const dateKey = estDateKey();
  // Milliseconds-since-epoch for ordering; request time is fine here.
  const ts = Date.parse(request.headers.get('date') || '') || 0;
  const key = `log:${dateKey}/${device}/${kind}-${ts}-${crypto.randomUUID().slice(0, 8)}`;
  await env.LOGS.put(key, body, {
    expirationTtl: 60 * 60 * 24 * 30, // keep 30 days
    metadata: { device, kind, dateKey, bytes: body.length },
  });
  return new Response(JSON.stringify({ ok: true, key }), { status: 200, headers: cors({ 'Content-Type': 'application/json' }) });
}

async function handleLogList(env, url) {
  if (url.searchParams.get('token') !== env.LOG_TOKEN) return new Response('forbidden', { status: 403, headers: cors() });
  const prefix = url.searchParams.get('prefix') || 'log:';
  const list = await env.LOGS.list({ prefix, limit: 1000 });
  const items = list.keys.map(k => ({ key: k.name, ...(k.metadata || {}) }));
  return new Response(JSON.stringify({ ok: true, count: items.length, items }), { status: 200, headers: cors({ 'Content-Type': 'application/json' }) });
}

async function handleLogGet(env, url) {
  if (url.searchParams.get('token') !== env.LOG_TOKEN) return new Response('forbidden', { status: 403, headers: cors() });
  const key = url.searchParams.get('key');
  if (!key) return new Response('missing key', { status: 400, headers: cors() });
  const val = await env.LOGS.get(key);
  if (val === null) return new Response('not found', { status: 404, headers: cors() });
  return new Response(val, { status: 200, headers: cors({ 'Content-Type': 'text/plain' }) });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors() });

    // WebSocket relay: /ws or /ws/<roomcode>. Default room 'main' is the
    // always-on public game used as the persistent-host fallback.
    if (url.pathname === '/ws' || url.pathname.startsWith('/ws/')) {
      const room = url.pathname === '/ws' ? 'main' : url.pathname.slice('/ws/'.length) || 'main';
      const id = env.ROOM.idFromName(room);
      return env.ROOM.get(id).fetch(request);
    }

    if (url.pathname === '/logs' && request.method === 'POST') return handleLogUpload(request, env, url);
    if (url.pathname === '/logs/list') return handleLogList(env, url);
    if (url.pathname === '/logs/get') return handleLogGet(env, url);

    return new Response('Tank Commander VR server — /ws[/room] (multiplayer), POST /logs (session data)', { status: 200, headers: cors() });
  },
};
