# Switching co-op to room codes over WebRTC

**Read this when the owner says any of:** "switch to WebRTC", "room codes",
"UPnP didn't work", "my friend can't connect", "no port forwarding".

The whole road is already built and tested (commit `74561f9`, 2026-09-09).
Nothing below is design work. It is three steps, then one test run.

## Why it is off

- `Config.NET.broker` is `""`, because there is no broker deployed yet.
- `addons/webrtc/` is gitignored and empty, because the native extension
  is per-platform binaries and a download away.

`WebRtcHub.available()` answers whether the extension is present; the game
checks both conditions itself and says which is missing on the HOST and
JOIN pages.

## The three steps

1. **Fetch the native extension** into the checkout (once per machine):

       tools\fetch-webrtc.cmd          (Windows)
       tools/fetch-webrtc.sh           (Linux/macOS)

   The default URL may 404 — it guesses the release name. If it does, open
   https://github.com/godotengine/webrtc-native/releases, take the URL of
   the `godot-extension-…zip` for the newest release that supports Godot
   4.x, and pass it as the one argument. Restart the editor once so the
   extension registers. Confirm with the test in step 4 or, faster:

       godot --headless --path . --import
       godot --headless --path . -s tests/run.gd -- webrtc_test

   `test_codes_and_ids` asserts `available()` is **false**; once the
   extension is in, flip that assertion to `true` in `tests/webrtc_test.gd`.

2. **Deploy the broker** in `server/` to a public host. `server/README.md`
   has the free-tier options; any Node host that forwards WebSockets works.
   The result is a `wss://…` URL. (Locally: `cd server && npm install &&
   npm start` gives `ws://localhost:8787` for a same-machine check.)

3. **Name the broker** in `src/config.gd`:

       "broker": "wss://<your-app>",

   That is the switch. Commit it.

## Then verify

    tools\test.cmd --all

`webrtc_slow_test` starts the real broker under Node and, now that
`available()` is true, walks a guest over a real WebRTC connection on
localhost. That is the one leg nothing could test before the extension
existed (a GDScript data channel cannot carry bytes — the engine hands it
raw pointers). If it fails, the problem is between `WebRtcHub` and the
native channels, and it is ours.

Then run the game: HOST shows a **ROOM CODE** row beside the port; JOIN
accepts the six-letter code where it accepts an address.

## What to expect in the wild

- Most pairs of home routers connect through STUN alone
  (`Config.NET.stun`, Google's public server).
- A pair that cannot — carrier-grade NAT on both ends, usually — needs a
  TURN relay, which is the only part of this that costs money. That is
  `coturn` on the same small VPS as the broker, or a managed TURN
  provider; add its `turn:` URL with credentials to `Config.NET.stun` (the
  key is a list of ICE servers) and nothing else changes.
- A free-tier broker sleeps when idle: the first join of an evening may
  wait a few seconds. The broker is only needed for the handshake; it can
  go down mid-game with no effect on anyone already playing.
- Both roads run at once while hosting: the UDP port (and UPnP) for LAN
  and forwarded-port friends, the room for everyone else.

## Where the pieces are

| Piece | File |
| --- | --- |
| The hub (rooms, joins, signalling, connection factory) | `src/net/webrtc_hub.gd` |
| The shared `MultiplayerPeer`-behind-`NetLink` base | `src/net/peer_hub.gd` |
| The broker | `server/signal.js`, `server/README.md` |
| The fetch script | `tools/fetch-webrtc.sh` / `.cmd` |
| The switch and the STUN list | `Config.NET.broker`, `Config.NET.stun` in `src/config.gd` |
| Scene wiring (hosting opens a room; joining by code) | `_start_hosting`, `_start_join`, `_join_step` in `scenes/main.gd` |
| Menu rows | `Page.HOST` and `Page.JOIN` in `src/ui/menu_screen.gd` |
| Tests and doubles | `tests/webrtc_test.gd`, `tests/webrtc_slow_test.gd`, `tests/support/fake_rtc.gd`, `tests/support/fake_broker.gd` |
| The decision | PROJECT.md §6, 2026-09-09 rows |
