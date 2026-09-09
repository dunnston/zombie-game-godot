# The broker

`signal.js` is DEADLINE's room-code broker: the host registers and gets a
six-letter code, a guest joins with the code, and the broker relays the
WebRTC offer, answer and ICE candidates between them until the two
machines are talking directly. Then it is out of the loop. It holds no game
state, no passwords and no accounts, and it can go down mid-game with no
effect on anyone already playing.

It is the prototype's `server/signal.js`, unchanged: the wire is documented
at the top of the file, and `WebRtcHub` in the game speaks it.

## Run it locally

    cd server
    npm install
    npm start            # ws://localhost:8787
    PORT=9000 npm start

## Put it on the internet (free tier)

The game needs it at a public `wss://` address in `Config.NET.broker`. Any
host that runs Node and forwards WebSockets works; these are the
zero-dollar ones at the time of writing:

- **Fly.io**: `fly launch` in this folder (it detects Node), accept the
  defaults, `fly deploy`. The app URL is `wss://<app>.fly.dev`. The free
  allowance covers one tiny machine; it may stop when idle and take a
  second to wake on the first join.
- **Render** or **Railway**: new web service from this folder, build
  `npm install`, start `npm start`. Both hand you an `https://` URL; use it
  with `wss://`. Free instances sleep when idle.

The broker reads `PORT` from the environment, which every one of these sets.

## Then, in the game

1. `tools/fetch-webrtc` once per checkout, for the native extension.
2. `Config.NET.broker = "wss://<your-app>"`.
3. HOST shows a ROOM CODE beside the port; friends type the code into JOIN.

STUN is `Config.NET.stun` (Google's public server by default). If a pair of
friends still cannot connect — carrier-grade NAT on both ends, usually —
the missing piece is a TURN relay, which is the one part of this that is
not free. See PROJECT.md §6.
