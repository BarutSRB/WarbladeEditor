# Architecture

## Runtime roles

Every session is a client connection to an authoritative game server, and the
client never simulates gameplay. The project exports two roles from one Godot
project:

- `macOS Client` renders, plays audio, reads local input, and sends bounded
  commands.
- `macOS Server` owns the deterministic simulation. Every `--server` process
  is a lobby game server: it binds, authenticates, and waits with no match
  configured; the first authenticated HELLO's match request configures or
  resumes the match, and when the last authenticated peer leaves it returns
  to the idle lobby for the next match.

The client resolves its game server by connection kind: the `--connect`,
`--port`, `--token`, and `--client-seat` command-line override (`direct`); the
match configuration's `server` dictionary (`direct` for CONNECT TO HOST,
`host` for a hosted online game, `join` for a joined one); and otherwise the
local sidecar — the same server binary spawned headless on `127.0.0.1` for
solo, Time Trial, and couch co-op, which therefore work offline. The title
screen footer names the lobby server and whether the player is online.

The local sidecar binds to `127.0.0.1`, authenticates a random per-session
token and the compiled-content SHA-256, and stops when its client heartbeat
disappears. Closing uses a private per-launch heartbeat path as a shutdown
capability instead of signaling a numeric PID. Heartbeat expiry uses changed
payloads and a monotonic callback gap, so a macOS sleep/wake does not look
like a dead parent. The dedicated export enters server mode through its
`server` feature.

A host binds the same sidecar publicly with `--host=* --port=<port>
--token=<token>` (the HOST PORT setting, UDP 42000 by default; a busy port
falls back to the dynamic range and the ready file reports the bound port)
plus `--rendezvous=<ip>:<udp-port> --rendezvous-nonce=<nonce>`, and connects
to it on loopback as seat 0. The joiner dials the host's candidate endpoints
(LAN first behind one router, otherwise the public endpoint) from the local
UDP port its rendezvous probe used, and joins as seat 1 with an empty match
request. A standing server still runs the dedicated export with `--server
--host=<ip-or-*> --port=<port> --token=<token>`; a non-loopback bind requires
the explicit port and token and refuses hostnames. The direct in-client
simulation was removed with local play.

The lobby server (`lobby-server/`, Rust with SQLite) is the only central
service: one WebSocket carrying JSON envelopes (`src/online/lobby_contract.gd`
mirrors `lobby-server/src/protocol.rs`) for identity (a nickname plus the
device key the client generates once at `user://identity.json`), the lobby
list, global chat with stored history, talent storage, self-reported match
records, and pushes; one UDP socket for NAT rendezvous
(`src/shared/rendezvous_codec.gd`); and a loopback-only owner admin page. It
never relays game traffic. The client keeps the last talent state at
`user://talent_cache.json` so grants still apply offline.

## Authority boundary

Accepted client messages are:

- the `HELLO` handshake carrying a bounded JSON match request
- seat-scoped input bitmasks
- sequenced seat-scoped bonus actions (tile selection or kill-time intent)
- shop item intentions
- shop ready state
- seat-zero pause state
- ping protocol messages
- party chat lines (CHAT), relayed by the server to every authenticated peer
- seat-zero hole-punch requests (PUNCH), honoured only on a public bind

The transport v8 match request is the one canonical match identity
(`WBMatchContract.network_contract`): mode, difficulty, co-op balance,
collision mode, string-carried 64-bit seed, level range, starting rockets,
and the normalized per-seat profile inputs — perfect-reward chains, accuracy
history, rank readiness, blue-coin state, secret flags, and the complete
profile-lock start state — plus the numbered resume slot beside the contract.
Both roles run the same normalizer, which is the validation boundary: unknown
fields are dropped before anything can reach the simulation. Seat 0 and couch
clients author the match; a seat-1 client sends an empty request, joins the
authored match, and adopts its contract from the first snapshot. A non-empty
request against a live match must equal the running contract exactly, and a
successful handshake immediately publishes the current authoritative state
behind the WELCOME. This replaced the launch-argument config bridge, which
silently dropped the per-seat start state, and with it the profile locks, from
every networked match.

Positions, velocity, health, damage, lives, score, cash, inventory, RNG,
collisions, spawns, drops, purchases, and phase/level transitions are never
accepted from a client. The server rejects malformed packets, bad tokens,
content mismatches, duplicate/out-of-order sequences, invalid seats, stale or
future input ticks, excessive message rates, commands invalid for the current
phase, resume requests against a live match, and match requests that do not
match the running contract.

Unauthenticated peers have three seconds to complete `HELLO` and are dropped
after four bounded pre-authentication rejections. The per-peer one-second
budget allows the full 120 changing input packets of two 60 Hz couch seats plus
32 control packets.

One authenticated couch peer atomically owns both seats. The two-client harness
authenticates seat 0 and seat 1 independently: seat 0 configures the lobby and
seat 1 joins the running match. Time Trial is single seat like solo; the
seat-count contract keeps a networked Time Trial from waiting for a second
seat.

This is a real process and trust-boundary proof, but hosting is player-owned
and not a trusted service: whoever holds the game token controls the match,
and there is no anti-cheat. The lobby server only introduces players and
stores what they report. Trusted online hosting, matchmaking beyond the lobby
list, and anti-cheat operations remain a separately bounded program that the
product does not pursue (user decision, 2026-09-01).

## Authoritative simulation

The simulation is fixed at 60 authoritative updates per second and has no scene
nodes, render delta, audio clocks, Godot physics bodies, or wall-clock
dependencies. Replays record the input stream, normalized bonus actions, and
authoritative state hashes. Mouse, keyboard, and gamepad selection all become
the same server-validated action; continuous pointer coordinates are never
sent.

The complete one-hundred-level route consumes this executable-backed state flow:

- state 1 consumes authored LVD activation, entry motion, path thresholds, and
  opcodes; terminal transitions preserve the last integrated transform and
  each new LVD segment resets elapsed progress to zero. Nonterminal opcode 1
  is a timed zero-motion point that remains in state 1, including the strict
  equality tick, and advances on `N+1`
- state 2 eases to formation, advances the six-frame loop/bounce producer, and
  uses timer B as its server-owned SWD launch denominator; the fixed-point
  adapter snaps only sub-representable residuals so formation animation cannot
  stall
- state 3 selects from the 14 globally loaded SWDs and runs their `1/256`
  velocity/acceleration explicit-Euler paths with strict truncated-progress
  thresholds
- state 4 uses its own horizontal velocity/acceleration fields, randomized
  turns, strict screen wraps, downward motion, and animation, reached through
  the recovered first-five selector and randomized tail routing
- levels 3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, and 61 use recovered supplemental state-6 spawn,
  fixed-table animation metadata, health divisor, movement/wrap, steering,
  health-scaled animation, and aimed type-6 shot rules
- authored mode-2 levels, including 12, multi-enemy level 20, level 29, level
  54, level 62, 70, 79, 87, and 95, use
  recovered state-10 acceleration, flip interval, motion/deactivation order,
  proximity-adjusted fire, and animation production

Timer A is the projectile-fire denominator in states 1, 3, 4, 6, and 10;
state 2 instead consumes timer B for attack launch. Qualifying kills tighten
both enabled timers after the collision pass. The server owns every RNG draw,
selection, state transition, projectile, collision, and timer reduction.

Authored mode 6 is ordinary campaign combat, not a separate suspended
controller. Levels 63–65, 67–69, 71–73, 76–77, 88–90, and 92–93 use the
retail target-facing lateral projectile component while retaining ordinary
state-2 entry, path termination, scoring, Warp, and final-kill behavior. The
retail comparison uses fighter/alien top-left X rather than their differently
sized runtime centers; solo targets the active owner. Remake-owned simultaneous
co-op retains nearest-active-player targeting. The
late vertical-speed multiplier is not enabled in the finite 1–100 campaign.
Level 80's authored group mode 3 follows ordinary group behavior, while
level 94's authored opcode 2 has its traced no-effect result in the absence of
mode-6 groups.

Authored mode 3 is a recurring server controller. Levels 8, 16, 24, 33, 41,
49, 58, 66, 74, 83, 91, and 99 use the
same per-seat hit ownership, result reveal cadence, strict deadlines, projectile and
drop suppression, and persistent perfect-reward chain; their target totals are
20, 30, 30, 30, 40, 40, 80, 60, 84, 90, 20, and 80 respectively. Snapshots and profiles publish canonical
`mode_three_*` fields while retaining synchronized `level_eight_*` aliases for
existing consumers.

Every fourth completed level enters the recovered Warp/shop boundary. At a
configured terminal shop boundary, pending level ID zero routes ordinary shop
exit or rank-promotion completion into the final campaign result. The default
boundary is level 100 and includes cadence shops through level 96. Every
explicit boundary from 1 through 100 remains valid.
The recurring mode-three contract independently enters a shop after its Warp,
so levels 33, 41, 49, 58, 66, 74, 83, 91, and 99 have bonus-mode shops despite
`shop_after: false`.

Levels 25, 50, 75, and 100 are mode 4 and are owned by level-indexed six-sheet
state-13 contracts, not the generic enemy loop or liveness watchdog. A match configured
to end at 25 completes only after that boss's traced defeat sequence; longer
matches emit exactly one Get Ready transition to level 26. An explicit level-49
match completes after its mode-three result route. Under the default boundary,
the same route enters its post-Warp shop and then Get Ready 50. Level 50 binds
the ordered `alien_big2_*` resources, level 75 binds `alien_big3_*`, and level
100 binds `alien_big4_*`. Level 100 owns both authored burst groups. Explicit
boss boundaries complete after their defeat sequence; longer matches request
the next Get Ready exactly once. Level 100 instead publishes the final terminal
contract with pending level zero and never requests level 101.

The server uses the recovered five-word unsigned PRNG and exact integer/
float32 range wrappers. It serializes all five words and the draw counter in
replays and hashes. Maximum-word float32 endpoints, biased modulo, and the
intentional absence of rejection sampling have pinned deterministic vectors.
Positions remain 16.16 and difficulty scaling uses rational sixth ticks,
preserving traced order without platform
float differences at the network boundary. The deliberate fixed-point
replacement for rare retail float32 comparison edges is versioned through the
replay and hash-state contracts.

## Weapon and collision model

Weapon volleys are recursive prototype graphs. Capacity is checked once before
the volley and counts each live root/child object, so a legal volley may
overshoot the nominal capacity. The capacity upgrade is shared in simultaneous
co-op, but live-object allowance is evaluated independently for each seat.

Manual fire is edge-latched. Auto Fire uses a strict `current_ms > deadline`
test with a 100 ms repeat delay; Super Auto Fire uses 25 ms. An expired Auto
deadline can therefore produce an Auto volley in the same update as the
manual-edge volley.

Fireballs use one-time spawn-X jitter. War.I.Plasma uses a random horizontal
velocity that is scaled on every update. All recursive child offsets are
relative to the original fire origin.

The Laser advances through `22 -> 23 -> 24 -> 50 -> -1`. Its visual rectangle
is separate from a 16-pixel-wide collision column from screen top to the live
owner Y. X is latched at spawn. Each ordinary-enemy hit uses the current damage
and halves it without consuming the beam.

Secondary Rocket Pack fire is independently release-armed and uses the shared
100-record physical player-projectile pool without consuming ordinary live-shot
capacity. After a weighted target draw it consumes two animation draws, then
tracks the selected enemy with the HMA-backed 32-heading, three-row rocket
atlas. Successful fire spends one missile; a full pool or no eligible target
spends neither ammo nor RNG beyond stages already reached. Alien Lock has no
missile-targeting effect: it preserves the owning seat's two captured-alien
records through Warp and clears on ordinary death in every supported match
mode. The executable match-mode value 6 is Time Trial—not a Warp phase—so its
reset exception applies only while Time Trial is the active match mode. This is
distinct from the now-supported authored LVD mode 6 first encountered at level
63. Missile targeting reads
enemy world zero while projectile ownership stays with the firing seat. The
single root match RNG owns every traced gameplay and synchronous-effect draw.

Broad-phase rectangles are followed by HMA occupancy overlap for all enemy
sheets used through level 100, fighters, and reachable projectile frames. The
HMA is headerless row-major 0/1 data sharing the texture's top-left source rectangle;
texture alpha is deliberately not treated as collision truth. The Laser column
uses its recovered rectangle-only override.

Alien shots occupy a 100-slot common pool. Phase survives slot reuse, animation
advances only after strict countdown underflow, and collision resolves in slot
order. Ordinary type 7 uses the x=480 atlas column and vertical velocity;
supplemental state 6 instead aims type 6 with three post-fire RNG draws and the
x=448 atlas column. Both first apply their sheet-specific, phase-independent
retail broad metadata, then
sample the full unscaled 32×32 HMA frame.

Ordinary alien bodies do not damage the fighter in the authored campaign.
Scoop is the body-interaction exception: its strict, tapered 90-pixel tractor
field captures two aliens as persistent wingmen. A third is scored immediately
but remains visible while retail state 5 flings it off the top of the field.

## Multiplayer ownership

Simultaneous couch co-op is not a recovered retail mode. Its shared
authoritative state contains score, money, total fighters, weapon/loadout,
upgrades, Armour, and shop purchases. Each seat retains its own position, input
latch, invulnerability, animation, and live-projectile count. Friendly fire
and player body collision are disabled.

Solo uses one progression record, and simultaneous co-op routes both seats to
the shared party record. The retail alternating and Duel modes — which kept
independent per-seat progression — were removed from the product by user
decision (2026-08-10) and are preserved on the `retail-two-player-modes`
branch.

Time Trial is retail match mode 6 and is single seat, like solo. It plays its
own fifteen authored levels (`content/time_trial.json`) in file order, wrapping
after the last, against a 181,000 ms clock. It has no shop, warp, warp
malfunction, bonus mode, rank promotion, or credits phase; it always starts on
weapon 0 because the retail lock applier gates its weapon tiers on match mode
!= 6; and it skips the death loadout reset. Clock expiry ends the run through
the ordinary game-over path, so the GAME BONUSES tally and the hall-of-fame
handoff are unchanged.

A run can be saved only from the shop, matching retail. The authoritative
game server owns the saved state: the client sends the protocol `SAVE`
command and the server writes the numbered slot itself. Resuming sends the
slot beside the match request in `HELLO`, the server restores its own slot,
and the restored contract must equal the requested one. Restoring reproduces
the shop boundary bit-identically, so a resumed run and a run that was never
saved stay on the same authoritative state hash. The client's LOAD SAVED GAME
list reads this machine's slot files, which are the local sidecar's slots
exactly; hosted online matches are not saved or resumed.

Only simultaneous same-team co-op is a remake modernization; the retail
two-player modes (simultaneous Duel and alternating play) are no longer part
of the product and live on the `retail-two-player-modes` branch.

`Classic` leaves authored enemy health unchanged. `Balanced` applies exactly
2× health to ordinary and supplemental enemies. No other hidden co-op scaling
is applied.

## Presentation

The server publishes reliable snapshots every three simulation ticks. Gameplay
events produced by all three ticks are accumulated into that snapshot so audio
and presentation do not lose 60 Hz events. The client interpolates entity
positions across the complete snapshot interval while rendering at the chosen
display rate.

The canonical coordinate field is always 800×600. Presentation aspect-fits the
entire field, including the original 64-pixel side rails, into the output
window. Larger or wider displays cannot reveal additional gameplay area.

Snapshot schema version 12 carries monotonically increasing authoritative event
IDs, server ticks, fixed-point positions, and the entity/weapon/source IDs
needed by client-only presentation. The server accumulates simulation-step and
command-generated events until the next reliable snapshot. Renderer, effects,
and audio consumers independently deduplicate those IDs. Every projectile also
publishes canonical `projectile_kind`, `sprite_sheet_id`, and `source_rect`
fields, and the always-present boss object exposes bounded state, stage, health,
sheet, and part data.

The renderer resolves original assets by exact keys from
`content/presentation.json`; it does not enumerate directories at runtime and
does not substitute triangles, circles, procedural stars, or primitive shots.
Original-only and enhanced effect modes share the same original core atlases.
Smooth filtering is the default for high-resolution output, with nearest-neighbor
sharp scaling available as a setting. Neither option affects simulation state.
The pinned retail background selector resolves `stars1` for levels 1–25,
`stars2` for levels 26–50, `stars3` for levels 51–75, `stars4` for levels
76–99, and `stars1` again for level 100. Presentation manifest v2 maps the
whole 1024×1024 atlas through two 672×600 quads spanning logical X 64–736.
The authoritative 60 Hz simulation captures the retail pre-update background
draw offset and applies every float32 Warp `scale / 20` update with 0/600 wrap.
Snapshots publish both draw and post-draw offsets; the client performs wrapped
high-refresh interpolation between authoritative draw offsets.

Audio uses separate music/SFX buses, runtime-looped title/game/shop/promotion/endgame MP3 streams,
bounded positional voices, per-sample concurrency, priority-based stealing, and
event-ID deduplication. Game-music position is retained across recurring shops.
The 38 consumed SFX have evidence-backed source/event bindings; their gain,
concurrency, priority, loop, and pitch values are an intentional deterministic
macOS mix policy, not a reconstructed retail mixer contract. The other 78 SFX
records are packaged evidence without a runtime tuning consumer.
The executable-referenced rank-0 promotion and bonus announcements are included;
alternative profile voice packs remain outside the finite product.
Tracker-module (`.mus`) playback is a permanent product non-goal: the extracted
MP3 soundtrack is final, and module files are not investigated, extracted,
converted, emulated, implemented, or scheduled.

The authoritative server ends the full route in phase `complete` with a
`result.campaign_terminal` object. Only `kind: "level_100"` with both
`full_campaign_completed` and `credits_required` enters the client-local ending.
The client transactionally publishes that result through a flushed sibling
temporary before presentation. A failed publication preserves the prior profile
file and exact terminal payload, blocks exit/credits, and exposes an explicit
retry; only a successful acknowledgement plays `endgame`, advances the 13
manifest-ordered images on their independent clock, and scrolls the recovered
story/credits text until Escape, Space, or Fire. Left
mouse pauses only the text while held; right mouse applies the traced text-speed
multiplier while held, and the control reminder clears after eight seconds.
A client-local
duplicate of the terminal snapshot RNG/tick fixes the modernized firework
cadence and particle layout independently of render refresh without changing
snapshot v9;
those visual details are not claimed as retail recovery. Mode metadata is never
concatenated into the exact retail story/credits scroll. Earlier configured
boundaries bypass credits and retain the
ordinary results/save-on-exit flow.

## Content boundary

Both roles load and validate the same integer-only compiled content. Content
version 12 hashes twelve ordered documents: `weapons.json`, `bonuses.json`,
`levels.json`, `shop.json`, `difficulties.json`, `sprite_frames.json`,
`swd_paths.json`, `bonus_modes.json`, `bosses.json`, `ordnance.json`,
`time_trial.json`, and `talents.json`.
The handshake fails before seat ownership if their byte-level SHA-256 differs.

Missing required content fails closed. The compact fallback catalog can be
loaded only through an explicit development opt-in and is never enabled by the
client or authoritative server exports.

All one hundred retail LVDs are also preserved verbatim. Their lossless decoder and
encoded JSON evidence are separate from the runtime's narrow normalized view:

- the raw LVD/base64 blob is the round-trip authority
- executable-proven aliases feed authored runtime data
- evidence-only words remain raw and lossless
- the 14 SWDs are preserved as lossless evidence and compiled separately into
  their compacted retail runtime order
- predecessor compatibility wave fields are decoding scaffolds only; v9
  authoritative play reads explicit runtime contracts instead
- authored LVD tail scores and recovered group/cohort rewards are authoritative
  only at executable-proven consumers

Original assets are copied only through a fixed allowlist after source PAC
hash validation. The provenance manifest closes over every copied asset and
its output hash.

The client-only presentation manifest v2 is generated from a parser inventory of
the pinned PAC and external audio directories plus that extraction provenance.
It keeps texture, music, SFX, and voice namespaces separate, preserves underscores,
records exact dimensions/hashes, and names explicit `res://` resources so Godot
exports cannot depend on directory enumeration. Normal startup validates the
runtime-required closure; packaged release smoke validates all 313 rasters, all
96 raw HMA files, all 10 MP3 tracks, all 116 compatibility SFX entries, and all
31 rank-0 voices. HMA entries remain raw collision data and are not misloaded
as Texture2D resources.

## Product and evidence boundaries

The six-category closure ledger is `docs/GAP_MATRIX.md`. Runtime gaps for the
finite levels 1–100 macOS product are closed. The following boundaries are
deliberate and do not create implicit implementation work:

- deterministic match seeding, fixed-point/rational simulation, server
  authority, simultaneous co-op, high-refresh interpolation, and ending
  firework cadence/particle layout are preserved modernizations; the bounded
  SFX mix values and accessible composition/timing around native screen
  bitmaps are likewise explicit macOS policies rather than retail claims
- source bytes without a reachable supported-runtime consumer remain lossless
  evidence without invented semantic names
- `.mus` playback, play beyond level 100, unrelated assets, and loose-file
  retail-asset redistribution are explicit non-goals
- online co-op is player-hosted with the lobby server; trusted online hosting
  is a separate program, and cross-platform delivery is limited to the
  unsigned Windows and Linux builds shipped from 0.1.0; Time Trial is
  implemented as retail match mode 6
