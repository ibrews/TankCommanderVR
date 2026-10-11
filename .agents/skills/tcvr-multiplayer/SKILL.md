---
name: tcvr-multiplayer
description: Implement or review Tank Commander VR ENet LAN and WebSocket relay gameplay, authority, serialization, reconnects, and seat changes.
---

# Tank Commander VR multiplayer

Read `res://scripts/net.gd`, the affected gameplay code, and
`multiplayer/README.md`. This project has both ENet LAN networking and a JSON
WebSocket relay. The relay broadcasts messages; it is not an authoritative game
simulation. Verify current sender/host checks in the implementation.

- Follow each change through both transport paths. A new RPC does not
  automatically create the corresponding relay message or receiver behavior.
  Keep authority checks equivalent, including metadata supplied by the relay.
- Confirm who owns an action before applying it: driver/gunner input, vehicle
  or enemy snapshots, damage, shots, session changes, and round state have
  different producers. Reject unauthorized senders for privileged actions.
- Keep serialization symmetric. Validate message type, array shape, numeric
  values, and bounds before applying state. Missing peers or malformed JSON
  should not crash the game or create unintended authority.
- Exercise join, leave, reconnect, lobby return, vehicle change, and seat swap.
  Inspect cleanup of peers, relay sockets, cached IDs, and queued state so the
  next session does not inherit the previous one.
- Use local isolated endpoints for tests. CLI multiplayer modes may fall back
  to the deployed relay; inspect them before launching and avoid joining the
  live default room just to test a local change. Cloud deployments and public
  session changes require authorization for that action.

Where applicable, verify co-op and versus with two controlled peers over each
changed transport. Logs should identify host/client, transport, and session.
If a transport has not been exercised, state that limit rather than treating a
single-player smoke check as multiplayer acceptance.

Official reference: [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).
Match the documentation version to the project and adapt examples to the
existing relay protocol rather than replacing it wholesale.
