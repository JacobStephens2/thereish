# Couch sync stack — realtime plumbing for a three-client household game

Researched 2026-09-01 for the [design brief](../design-brief.md). Method: maintenance status and capabilities checked against primary sources — official docs, changelogs, the npm registry, and repos — on 2026-09-01. Versions and publish dates below come from the npm registry / hexdocs on that day. Community-only claims are labeled.

**Constraints recap.** Three clients in one wifi room: Melissa's Pixel 10 Pro XL (Android Chrome), a second phone (platform unconfirmed — cover iOS Safari), a laptop as shared public screen. Join by short room code. Server-authoritative shared state; turn-based with occasional simultaneous-reveal moments — not latency-critical. Self-hosted on a personal VPS (stephens.page) that also makes streaming LLM calls server-side; dev on a MacBook. Household scale (throughput irrelevant). The one hard requirement: **survive flaky wifi and phone locking — reconnection without losing game state.**

---

## Part A — transport / state options

### Raw WebSocket — the `ws` library (Node)

- **Status:** active. 8.21.3, last publish 2026-08-07 ([npm](https://registry.npmjs.org/ws)); recent releases include security fixes across four maintained major lines ([releases](https://github.com/websockets/ws/releases)). Note Node ≥22 ships a browser-compatible `WebSocket` **client** global (verified on local Node 26.7.0) — servers still need `ws`.
- **Fit:** rooms, room codes, player identity, heartbeats, and reconnect-with-resync are all yours to write. Fine at this scale, but every one of those is exactly the code Socket.IO already ships (below). Client-side, [PartySocket](https://github.com/cloudflare/partykit/blob/main/packages/partysocket/README.md) ("Works everywhere, not just with PartyKit!") is an actively maintained reconnecting client — reconnects on drop, buffers messages while disconnected, standalone `WebSocket` export — 1.3.0, 2026-06-23 (npm). Pairing `ws` + partysocket halves the hand-rolling.
- **Self-host:** trivially — one Node process behind Caddy/nginx.
- **Verdict:** viable minimal path; costs a day of protocol plumbing before the first fun experiment.

### Socket.IO

- **Status:** active. Core 4.8.3 (2025-12-23, npm); companion packages patched July 2026, maintainer responsive ([releases](https://github.com/socketio/socket.io/releases)). MIT.
- **Rooms:** first-class and server-only — `socket.join(code)`, `io.to(code).emit(...)`; "rooms are a **server-only** concept" ([rooms docs](https://socket.io/docs/v4/rooms/)). Membership is cleared on disconnect; rejoin explicitly (or via recovery, below).
- **Reconnect ergonomics — the headline feature set for this game:**
  - Client auto-reconnects by default: infinite attempts, 1s→5s randomized backoff ([client options](https://socket.io/docs/v4/client-options/)).
  - Since v4 the **server** sends the heartbeat PING, so background-tab timer throttling no longer kills the connection by ping timeout (a real v2 failure mode) ([troubleshooting](https://socket.io/docs/v4/troubleshooting-connection-issues/)).
  - **Connection state recovery** (since [4.6.0, Feb 2023](https://github.com/socketio/socket.io/releases/tag/4.6.0)): restores id, rooms, `socket.data`, and missed packets after blips within `maxDisconnectionDuration` (~2 min recommended), flagging `socket.recovered`. The docs are explicit that "the recovery **will not always be successful**" — you still implement full state resync ([CSR docs](https://socket.io/docs/v4/connection-state-recovery)). Works with the in-memory adapter, i.e. no Redis needed at this scale.
- **Transports:** default long-polling → WebSocket upgrade — a free fallback layer ([client options](https://socket.io/docs/v4/client-options/)).
- **Self-host:** one Node process. VPS detail worth knowing: nginx's default `proxy_read_timeout` (60s) must stay above the 45s combined `pingInterval`+`pingTimeout` or the proxy severs idle sockets ([troubleshooting](https://socket.io/docs/v4/troubleshooting-connection-issues/)).
- **Verdict:** rooms + reconnection + fallback are precisely the needed features, all default-on, one language with the LLM-streaming server.

### Server-sent events + POST

- **Status:** platform-native, Baseline since 2020. Auto-reconnect is built into `EventSource`, with server-tunable `retry` and automatic `Last-Event-ID` resume on reconnect — elegant, standards-level resumption ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events)).
- **Limits:** one-directional (inputs go over `fetch` POST), UTF-8 text only, and a hard 6-connections-per-domain cap on HTTP/1.1 — fine on HTTP/2 (~100 streams), which Caddy gives you by default (same MDN page, quoted warning).
- **Fit:** genuinely adequate for turn-based, and the simplest mental model. But rooms/identity/snapshot logic is still all hand-rolled, phones still kill the stream on lock (Part B), and proxy buffering must be disabled — so it saves little over Socket.IO while giving up bidirectional push.
- **Verdict:** honorable fallback; not the pick.

### WebRTC data channels

- **Reality check:** establishing the peer connection requires an out-of-band signaling channel — MDN's own guide: "negotiate the connection out-of-band, using a web server or other means" ([Using data channels](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Using_data_channels)). So you run a server anyway; and this game's server must hold authoritative state *and* make the LLM calls, so P2P moves nothing off the server. Mesh adds ICE/STUN failure modes on flaky wifi for zero benefit at 3 clients / non-twitch latency.
- **Verdict: confirmed overkill.** Its one couch trick (sub-frame latency between phones) isn't needed.

### CRDTs — Yjs, Automerge

- **Status:** both very much alive. Yjs 13.6.32 (2026-08-04) with active providers (y-websocket 3.1.0, 2026-08-06; Hocuspocus, y-sweet) ([repo](https://github.com/yjs/yjs)); Automerge 3.4.1 (2026-08-12), self-hostable sync server included with automerge-repo ([automerge.org](https://automerge.org/)).
- **Shape mismatch:** CRDTs exist to merge concurrent edits without a central authority — "changes are automatically distributed to other peers and merged without merge conflicts" (Yjs README); "local-first sync engine … works offline, prevents conflicts" (automerge.org). This game is the opposite shape: a referee-adjudicated turn machine with **hidden information** (sealed submissions before a reveal). CRDT sync replicates the doc to every client; hiding parts of it and enforcing turn legality means fighting the model. Neither project documents a server-authoritative/hidden-state story.
- **Verdict: confirmed overkill / wrong tool** — for game state. (A CRDT could someday back a *jointly edited Chronicle*, a genuinely collaborative document — parked.)

### PartyKit / partyserver

- **Status:** the original [partykit/partykit](https://github.com/partykit/partykit) README redirects: "Current development of this project is in [cloudflare/partykit](https://github.com/cloudflare/partykit)." The successor packages (PartyServer 0.5.10, 2026-08-03; partysub, partysync…) are built on **Cloudflare Workers + Durable Objects**, flagged "Work in Progress."
- **Self-hostable on a plain VPS?** No — the current stack targets Cloudflare's runtime and Durable Objects; there is no supported plain-Node path ([repo](https://github.com/cloudflare/partykit)). Running it means adopting Cloudflare, not stephens.page.
- **Salvage:** [PartySocket](https://github.com/cloudflare/partykit/blob/main/packages/partysocket/README.md) (the client) is explicitly server-agnostic and pairs well with `ws` (see above).
- **Verdict:** out as a server (fails self-hosting); its client library is the useful export.

### Phoenix (Elixir) — Channels / LiveView

- **Status:** very active. Phoenix 1.8.13 (2026-08-25), LiveView 1.2.11 (2026-08-27) ([changelogs](https://phoenix.hexdocs.pm/changelog.html), [LiveView](https://phoenix-live-view.hexdocs.pm/changelog.html)).
- **Rooms are native:** topics like `"room:lobby"`, broadcast to subscribers, WebSocket with long-poll fallback, Presence built in; a lightweight process per client per topic holds state ([Channels docs](https://phoenix.hexdocs.pm/channels.html)).
- **Reconnect ergonomics:** the JS client reconnects with exponential backoff and "they'll attempt to rejoin the topics they had previously subscribed to"; outbound messages buffer while disconnected. Delivery is at-most-once — "Phoenix won't resend it… doesn't persist messages" — so you implement snapshot-on-rejoin, same as everywhere (Channels docs). LiveView: on a drop "the client gracefully reconnects to the server, calling `mount/3` … again," and socket assigns are lost — so authoritative game state lives in a per-room GenServer/ETS regardless ([LiveView docs](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html)).
- **Telling signal:** Phoenix 1.8.13's changelog: "Workaround issue where Mobile Chrome 149+ would not reconnect after tab is resumed ([#6804](https://github.com/phoenixframework/phoenix/issues/6804))" — the framework actively chases exactly the phone-resume bugs this game will hit.
- **Self-host:** one BEAM release on the VPS; standard.
- **Runtime note:** choosing Phoenix means the realtime layer is largely *solved* by the framework, at the cost of a second language in the stack (client-side custom interactions still end up in JS) and a smaller LLM/tooling ecosystem than TypeScript's. This is where runtime choice most changes realtime ergonomics: Elixir makes rooms/reconnect nearly free; Node makes the *whole* stack (UI experiments + LLM streaming + server) one language.

### Adjacent, checked and noted

- **Colyseus** — the actual "multiplayer game server" framework for Node: self-hosted, MIT, server-authoritative schema with delta patches, active (0.18.5, 2026-08-28) ([docs](https://docs.colyseus.io/)). Its reconnection design is the reference pattern: server calls `allowReconnection(client, seconds | "manual")`, client stores `room.reconnectionToken` and calls `client.reconnect(token)`, `sessionId` and state survive ([reconnection docs](https://docs.colyseus.io/room/reconnection)). Overkill ceremony (schema classes, binary patches) for three clients and JSON-sized turn state — but the fallback if hand-rolled room lifecycle sprawls.
- **boardgame.io** — dormant: last release 0.50.2 on 2022-11-10 (npm). Skip.

---

## Part B — phone-web realities

### Screen Wake Lock (screen must not sleep mid-game)

- Supported where it matters: Chrome/Android since 84 ([Chrome docs](https://developer.chrome.com/docs/capabilities/web-apis/wake-lock)), Safari/iOS since 16.4 (March 2023) ([WebKit release notes](https://webkit.org/blog/13966/webkit-features-in-safari-16-4/)); Baseline cross-browser since March 2025 ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API)).
- HTTPS-only. The lock is **automatically released whenever the page is hidden** (app switch, tab switch) and can be *refused* under low battery / power-save (MDN, Chrome docs). The canonical pattern: request on join, listen for the lock's `release` event, and **re-request on `visibilitychange` → visible** (both sources show this exact code).
- Design consequence: a wake lock is a courtesy, not a guarantee — the game must also be fine with a phone that slept anyway (server holds the seat; see recovery below).

### What backgrounding/locking actually does to sockets

- **Timer throttling (Chrome):** hidden tabs get timers checked ~1/sec; after 5 minutes hidden (with chained timers, no audio/WebRTC) ~1/min ([Chrome 88 blog](https://developer.chrome.com/blog/timer-throttling-in-chrome-88)). Throttling delays *JS-scheduled* work, not WS delivery per se — but any client-side heartbeat stalls. Socket.IO v4 dodged this by making the **server** send PING ([troubleshooting](https://socket.io/docs/v4/troubleshooting-connection-issues/)).
- **Freezing (mobile):** Chrome proactively *freezes* hidden tabs — switching apps or locking the phone — suspending all task queues; Chrome's own guidance is to close WebSockets on `freeze` and reopen on `resume` ([Page Lifecycle API](https://developer.chrome.com/docs/web-platform/page-lifecycle-api)). `freeze`/`resume` are Chromium-only; on iOS rely on `pagehide`/`pageshow` + `visibilitychange`. iOS Safari suspends pages similarly aggressively on lock/app-switch and sockets die with them (long-observed behavior; Apple doesn't document timings — community-documented).
- **bfcache:** close connections on `pagehide`, reopen on `pageshow`; "Chrome (as of 149) and Safari do no[t] block on open WebSockets but other browsers do" ([web.dev bfcache](https://web.dev/articles/bfcache)).
- **2026 field evidence** that resume-reconnect is where the bugs live: Phoenix shipped a workaround for Mobile Chrome 149+ failing to reconnect after tab resume ([1.8.13 changelog](https://phoenix.hexdocs.pm/changelog.html), Aug 2026).
- **Standard recovery pattern** (all stacks converge here): assume the socket is dead every time a phone comes back. On `visibilitychange`→visible / `pageshow`, verify or rebuild the connection; identity = room code + player-slot token in `localStorage`; **every (re)join answers with a full authoritative snapshot**; client sends are idempotent commands. Socket.IO's CSR and Colyseus's `allowReconnection` are conveniences layered on this, never substitutes (their own docs say so).

### PWA install

- **Android Chrome:** installable when the manifest has `name`/`short_name`, 192px+512px icons, `start_url`, `display: standalone|fullscreen|minimal-ui`, served over HTTPS, with a small engagement heuristic (≥30s + a tap). A service worker is **no longer in the criteria list**; "richer install UI" (screenshots/description) is recommended ([web.dev install criteria](https://web.dev/articles/install-criteria), updated 2024-09). Install lives in the browser menu/prompt ([MDN installing guide](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Installing)).
- **iOS Safari:** no install prompt event, ever — manual Share sheet → "Add to Home Screen" (MDN); since 16.4, non-Safari browsers can also install ([WebKit 16.4 notes](https://webkit.org/blog/13966/webkit-features-in-safari-16-4/)).
- **For this game:** a plain browser tab is fully sufficient; standalone install is a nice-to-have (full-screen, no URL bar, a home icon for Melissa). Don't spend prototype time on service workers.

### Text input & viewport quirks (the clue-typing screen)

- **Height:** use `dvh`/`svh` units, not `vh` — the URL-bar-collapse problem is what they exist for ([web.dev viewport units](https://web.dev/blog/viewport-units)).
- **Keyboard:** `interactive-widget=resizes-content` in the viewport meta makes the layout viewport shrink when the keyboard opens — Chrome 108+ and Firefox 132+, **not implemented in Safari** ([MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Guides/Viewport_meta_element), [WebKit bug 259770](https://bugs.webkit.org/show_bug.cgi?id=259770), open). On iOS the keyboard overlays/scrolls instead — position critical UI with the [VisualViewport API](https://developer.mozilla.org/en-US/docs/Web/API/Visual_Viewport_API) or just keep the input in the top half of the screen.
- **iOS zoom-on-focus:** inputs with font-size < 16px trigger auto-zoom (long-standing WebKit behavior, community-documented) — keep inputs ≥ 16px. Don't fix it with `user-scalable=no`: MDN flags that as a WCAG violation, and iOS ignores `maximum-scale` anyway ([MDN viewport](https://developer.mozilla.org/en-US/docs/Web/HTML/Guides/Viewport_meta_element)).
- **Touch feel:** `touch-action: manipulation` (kills double-tap-zoom delay on buttons), `overscroll-behavior-y: contain` (kills pull-to-refresh mid-game), and `enterkeyhint`/`inputmode`/`autocapitalize`/`autocorrect` attributes to make the keyboard behave for word entry (MDN-documented attributes; autocorrect matters in a game about exact words).

---

## Signals for our design — *inference, not sourced fact*

Ranked by iteration-speed-toward-fun + self-hostability + flaky-wifi robustness:

**1. Node/TypeScript monolith with Socket.IO (the pick).** One process on the VPS: static client + Socket.IO rooms + server-side streaming LLM calls relayed as room events; Caddy in front; Vite + `tsx watch` for dev. Room = in-memory object keyed by 4-letter code, snapshotted to a JSON file on mutation so even a server restart mid-game is invisible at household scale. Rooms, default-on infinite reconnect, server-side ping (throttle-proof), polling fallback, and CSR for ≤2-min blips are all free; the one rule we enforce ourselves — **full snapshot on every (re)join, CSR treated as bonus** — is ~20 lines. One language for UI experiments, protocol, and LLM streaming maximizes mechanic-experiments-per-hour, which is the brief's own metric. The laptop "stage" is just a third client with a different view of the same room. Simultaneous reveal = server holds sealed submissions, emits one reveal event — a server decision, not a transport feature.

**2. Phoenix LiveView + Channels (the native-fit contender).** Rooms, presence, auto-rejoin, and fallback are framework features, and Phoenix demonstrably patches phone-resume bugs within weeks. Under the brief's "unfamiliarity doesn't count against it" law this is a legitimate first choice — pick it if the game settles into server-rendered turn flow, because "UI state lives on the server" *is* design-law-grade server authority. It ranks second only on iteration speed: state must live outside the LiveView process anyway (assigns die on reconnect), custom couch-y client interactions still mean JS, and the split-language stack slows the experiment loop the brief prizes.

**3. Bare `ws` + PartySocket client (the minimal path).** Smallest dependency surface, total control; PartySocket covers client reconnect + send-buffering. Costs a day of room/identity/resync protocol before the first fun test, and its failure modes are the ones option 1 has already productized. Choose only if Socket.IO's magic gets in the way — and note the escape hatch is cheap, since the snapshot-on-join contract is transport-agnostic.

**Explicitly out:** PartyKit/partyserver (Cloudflare-bound, fails self-hosting), WebRTC data channels (server exists anyway; P2P buys nothing at 3 clients), CRDTs for game state (wrong shape for refereed hidden-info turns — revisit only for a co-edited Chronicle), boardgame.io (dormant since 2022). **Kept warm:** Colyseus, if hand-rolled room lifecycle ever sprawls — its `reconnectionToken` design is the pattern to imitate regardless.

**Cross-cutting rules the transport doesn't give us** *(inference)*: player identity in `localStorage` (`{roomCode, playerSlot, secret}`) so a locked phone rejoins its own seat; reconnect flow triggered on `visibilitychange`/`pageshow`, with a "reconnecting" veil only after ~2s (app-hopping shouldn't flicker); wake lock acquired on join and re-acquired on visible, but seats never expire at household scale; all state transitions server-side and idempotent, so a double-tapped submit or a replayed packet can't corrupt a board.
