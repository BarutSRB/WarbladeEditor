# Warblade Remake

This is a macOS-first Godot 4 remake of Warblade 1.34. Version 0.1.0 contains
the complete 100-level authored campaign, cadence shops after every fourth
ordinary level through 96, and mode-three post-Warp shops after levels 33, 41,
49, 58, 66, 74, 83, 91, and 99. It includes the retail level-25, level-50,
level-75, and level-100 big bosses, the nine original base
weapons, four difficulty selections, the original solo mode, and
simultaneous two-player couch co-op. The retail alternating and Duel
two-player modes were removed from the product by user decision (2026-08-10);
their full implementation is preserved on the `retail-two-player-modes`
branch of the earlier development history, which is not part of this
repository.

Like retail, the campaign does not end at level 100: the credits roll as an
interstitial and play continues through level after level. Content cycles
through the authored set with the per-hundred horizontal mirror, and the
executable-proven progression step raises difficulty every hundred (enemy
health, alien projectile speed, simulation pace, and firing timers; see
[`docs/evidence/ENDLESS_PROGRESSION.md`](docs/evidence/ENDLESS_PROGRESSION.md)).
The level counter clamps at the retail maximum 3999.

Gameplay runs at a deterministic 60 Hz in a separate authoritative game-server
process, and the client never simulates. Solo, Time Trial, and couch co-op
play through a local server the client spawns on this Mac, so they work
offline. Online co-op is player-hosted: the host's Mac runs the same
authoritative server bound publicly, a second player joins it as seat 1, and
a small Rust lobby server (`lobby-server/`) provides nicknames, the lobby
list, global chat, NAT rendezvous, and talent storage. The lobby server never
relays game traffic. Rendering can run at the display refresh rate or at 60, 120,
144, 165, 240, 360, 480, or unlimited FPS. The logical game field remains
800×600 and is aspect-fitted at larger resolutions without exposing additional
play area.

## Download

Builds are published on GitHub Releases
(https://github.com/BarutSRB/Warblade-Enhanced/releases): one archive per
platform plus `SHA256SUMS.txt`. Only the macOS build is tested on real
hardware. The Windows and Linux builds come from the same source and export
pipeline but were not run on Windows or Linux machines before 0.1.0; the
Linux binary is smoke-tested headless in a container.

- macOS (one universal app for Apple silicon and Intel):
  `WarbladeRemake-<version>-macos-universal.zip`. Unzip and move
  `Warblade.app` anywhere. The app is ad-hoc signed and not notarized, so
  macOS blocks the first launch: open System Settings > Privacy & Security,
  find the message about Warblade near the bottom, click Open Anyway, and
  confirm. The Terminal equivalent is
  `xattr -dr com.apple.quarantine /path/to/Warblade.app`.
- Windows 10/11 x86_64: `WarbladeRemake-<version>-windows-x86_64.zip` holds
  a single `Warblade.exe`. It is not code-signed, so SmartScreen shows
  "Windows protected your PC": click More info, then Run anyway. Windows
  Firewall asks for permission the first time you host an online game.
- Linux x86_64 (glibc 2.28 or newer, X11 or Wayland through XWayland, OpenGL
  3.3): `WarbladeRemake-<version>-linux-x86_64.tar.gz` holds a single
  `Warblade.x86_64`. Extract it, `chmod +x Warblade.x86_64` if your extractor
  dropped the bit, and run it.

Saves, profiles, settings, the talent cache, and the device identity live in
`~/Library/Application Support/Warblade Remake` (macOS),
`%APPDATA%\Warblade Remake` (Windows), or `~/.local/share/Warblade Remake`
(Linux). Online play needs outbound TCP 7400 and UDP 7401 to the lobby
server; hosting also needs inbound UDP 42000 (the default HOST PORT), opened
by UPnP or a manual port forward. Release notes live in `CHANGELOG.md`.

## Finite-product fidelity closure

### Executable-backed and implemented

- byte-identical decoding and encoding of all one hundred retail LVD files
- authored group/enemy counts, entry transforms, activation delays/staggers,
  formation targets, base health, path acceleration, explicit-Euler update
  order, zeroed segment transitions, thresholds, and supported retail opcodes
- the complete 14-file SWD catalog, global state-2 path selection, formation
  animation, timer-B launch gate, follower path copying, and the state-3
  fixed-point path integrator, including first-five follower recruitment and
  selector/tail routing
- supplemental state-6 and mode-2 state-10 spawn values, motion, steering, strict
  wrapping/deactivation, timers, firing gates, animation, and the state-6
  aimed type-6 projectile with its distinct atlas/HMA geometry
- state-4's dedicated roaming velocity/acceleration, strict wrap/turn rules,
  and state-1 terminal transitions that preserve integrated position instead
  of snapping or teleporting aliens into formation
- all nine weapon IDs, damage values, recursive projectile graphs, source
  rectangles, spawn offsets, special Fireballs/War.I.Plasma movement, and
  per-player projectile-object capacity
- edge-latched manual fire; strict absolute-deadline Auto Fire at 100 ms and
  Super Auto Fire at 25 ms
- the four-frame persistent Laser, its latched X/live player-Y collision
  column, and ordinary-enemy damage halving after each hit
- executable-backed Rocket Pack purchase/cap, release-armed secondary fire,
  weighted targeting, shared-pool HMA collision, ordinary/boss damage, and
  per-seat inventory; Alien Lock preserves captured aliens through Warp and
  does not change missile targeting
- the retail five-word unsigned PRNG, MSVCRT seed initialization, integer and
  float32 range wrappers, per-slot initialization draws, and serialized replay
  state
- the 100-slot common alien-projectile pool, persistent phase on slot reuse,
  strict countdown/bottom bounds, slot-order collision, type-6/type-7 broad
  metadata, and full 32×32 HMA tests
- exact Easy/Normal/Hard/Ace simulation scales, timer adjustments and floors,
  projectile speeds, player speed rules, and difficulty border selection
- original HMA pixel masks for the alien sheets used through level 100, both
  fighters, and all reachable player-projectile frames; texture alpha is not
  collision authority
- an explicit, collision-safe presentation manifest covering the original
  rasters and raw HMA masks (533 texture-namespace entries spanning every
  `warblade.pac` raster), all 12 extracted MP3 music tracks, 116 compatibility
  SFX entries, and the complete 103-clip rank-0 retail voice pack, with byte
  hashes and exact dimensions validated against the retail sources;
  presentation smoke validates every raw HMA's byte count, binary domain, and
  SHA-256 in source and exported builds; voice pack 2 (36 clips) is extracted
  alongside pack 1 for the user-selectable voice-pack feature
- original fighter/enemy/projectile/background/border/pickup/thrust art in the
  live renderer, original HUD digits and fighter icons, and original title,
  pause, shop, and game-over art at native source geometry; accessible screen
  composition, controls, and timing around those bitmaps are an explicit macOS
  modernization, and primitive gameplay art is no longer a runtime fallback
- executable-recovered alien-shot atlas cells, ten-frame fighter thrust,
  animated money/armour/EXTRA/time pickup rows, and the 13-frame small
  explosion sequence
- authoritative presentation events for firing, hits, destruction, armour,
  pickups, respawns, level flow, and purchases, consumed once by pooled
  effects and positional audio
- fighter banking, three-total-fighter start, five-fighter cap, speed and
  projectile-capacity shop limits, and alien-projectile Armour protection
- executable-backed letter awards: per-collect scoring, the strict
  consecutive E-X-T-R-A and reversed A-R-T-X-E chains with their cap-filling
  and SUPER score variants, and the repeating all-collected award
- the executable-backed end-of-game GAME BONUSES tally (cash, cumulative
  rank bonus, perfects, hit percentage) on every terminal result and the
  pause-menu retire command
- all one hundred LVD scores, executable-backed group/cohort rewards,
  falling-bonus selection/drop physics, all 37 outer bonus dispatches, Freeze,
  the tapered 90-pixel Scoop
  field with two captive wingmen and visible overflow escape, final-kill
  rockets, death/respawn deadlines, and watchdog diagnostics; the explicit
  production-pixel route-assist campaigns prove that no level resolves through
  the watchdog
- Warp progression starting at `3.0 / 8`, the 100+200+100-update mode-13
  sequence, bonus-type-15's four skip passes that stop at special level 4,
  and level-4 completion entering the full Warp before either the first shop
  or level-5 Get Ready
- the first-five mode-16 Warp-malfunction path: four recovered malfunction
  resource files, exact shared-RNG selection/spawn ordering, 64-pixel state-6
  enemies, six-color falling gems, rank-color accumulation, and Super Auto
  Fire completion
- executable-backed Memory Station, Meteor Storm, and terminal Gem Drop controllers, including
  their retail board/slot state, RNG draw order, scoring and reward tables,
  deadlines, success/failure transitions, original art, music, and announcements
- the recurring level-8/16/24/33/41/49/58/66/74/83/91/99 mode-three controller's independent per-player
  hit ownership, reveal rewards, shared perfect-chain progression/reset, result
  timing, Warp, and shop handoff
- exact rank-0 voice composition and padding for profile promotions 1–20
- the executable-backed six-sheet level-25 boss controller, with authoritative
  stage/health/part snapshots, exact HMA collisions, rewards, music ownership,
  defeat sequencing, and a level-26 bridge when the configured boundary extends
  past 25
- the shared executable-backed state-13 controller for the six-sheet level-50,
  level-75, and level-100 encounters, with exact collision, projectile, reward,
  and defeat contracts; level 50 binds its opcode-3 `alien_big2_*` path, level
  75 binds `alien_big3_*`, and mirrored level 100 binds the opcode-6 terminal
  `alien_big4_*` path
- mixed-resource authored groups through level 100, all late supplemental
  animations, authored mode 6, level-80 group mode 3, and level-94 opcode 2;
  the `stars1`/`stars2`/`stars3`/`stars4` retail background selector; cadence
  shops through level 96; boss handoffs at 25, 50, and 75; and the level-100
  ending/credits interstitial with endless continuation past level 100
- shared party progression (lives, score, money, loadout, upgrades) across
  both simultaneous co-op seats
- the first shop's item IDs, names, prices, rejection rules, weapon effects,
  Extra Time overshoot, six-bit Rank Marker reward, and non-upgrade Game
  Secret selection
- inclusive 70/80/90 accuracy gates for shop items 18–20 and profile-v4
  above-level-25 best-hit persistence plus the authoritative best level-100
  score, without fabricating a level-25 sample
- keyboard/controller-focusable shop and pause controls, with authoritative
  purchase rejection feedback and no client-side shop-data fallback
- server-owned movement, collision, damage, lives, score, money, upgrades,
  shop transactions, RNG, pause, and level transitions
- Time Trial (retail match mode 6): its fifteen authored levels in file order
  with wrap, the 181,000 ms clock and the grouped-best 241,000 ms variant, the
  mode-6 rules (single seat, weapon 0, no shop/warp/bonus/rank/credits phase,
  no death loadout reset, no hurry-up ships), and the clock-expiry handoff into
  the ordinary GAME BONUSES tally and Time Trial hall of fame
- retail in-shop saved games in numbered slots, written by whichever side owns
  the authoritative state, restoring a shop boundary that stays bit-identical
  to the run that was never saved
- the hurry-up secret ships: a per-player deadline armed from the difficulty
  timed-effect interval, the state-9 mothership with its banner, voice line,
  hum, and parallax planet sweep, the state-12 money ship on every eighth wave,
  their traced hitboxes and scores, and the found-secrets they record

### Intentional modernization

- authoritative gameplay remains fixed at 60 Hz, while the client interpolates
  complete snapshots at native display refresh or the selected render cap
- original raster art defaults to smooth high-resolution scaling, with an
  optional sharp-pixel mode; effects can use only the recovered core layer or
  restrained additive enhancement without changing authoritative gameplay
- integer fixed-point and rational sixth-tick arithmetic replace retail
  float32 at the network/replay boundary; this is deterministic but may differ
  at rare float32 comparison edges, whose deliberate v9 results are pinned by
  deterministic boundary vectors
- simultaneous couch co-op is a remake mode: both seats play at once with
  shared score, money, fighters, loadout, upgrades, and shop state, while
  keeping separate input, position, invulnerability, and live-projectile
  allowance; there is no friendly fire or player body collision
- `Classic` co-op keeps the authored enemy health; `Balanced` applies exactly
  2× enemy health
- runtime-required SFX retain executable-backed source/event bindings while
  bounded gain, concurrency, priority, loop, and pitch values are an explicit
  deterministic macOS mix policy, not a claim about the retail mixer
- the game server enforces the authoritative client/server contract on
  loopback and public binds alike; hosting is player-owned and the game token
  is not a trusted online service

### Product boundaries

- The retail two-player modes — alternating play and simultaneous Duel — were
  removed from the product by user decision (2026-08-10). Their complete
  traced implementation (independent progression, sequential shops,
  pass-through opponent projectiles, the winner/draw result, and winner
  fireworks) is preserved on the `retail-two-player-modes` branch of the
  earlier development history, outside this repository.
  Simultaneous co-op is the intentional remake modernization and the only
  two-player mode on `main`; ending firework cadence/particle layout remains a
  deterministic presentation modernization.
- Retail cursor/time/UI entropy is replaced by an explicit deterministic match
  seed. Fixed-point authority, server ownership, and high-refresh interpolation
  are preserved modernizations.
- Tracker-module (`.mus`) playback is a permanent product non-goal. The exact
  extracted MP3 set is the final music system; module files are not inspected,
  extracted, converted, emulated, implemented, or scheduled.
- Trusted online hosting remains a separate program rather than a defect in
  the macOS product; online co-op ships player-hosted with the lobby server.
  Cross-platform delivery is partial from 0.1.0: Windows and Linux builds
  ship unsigned and without platform QA on real hardware (row I02). Time
  Trial (retail match mode 6) ships with the game.
- The complete secret-ship family is implemented: the hurry-up mothership and
  money ship (G19) and the money-sucker and guard ships (G20) share the traced
  death dispatcher, and both rows are closed in `docs/GAP_MATRIX.md`.
- Source fields without a reachable runtime consumer remain lossless,
  evidence-only bytes and never receive invented semantics.

The complete six-category closure ledger is in
[`docs/GAP_MATRIX.md`](docs/GAP_MATRIX.md).

## Requirements

- macOS with Godot 4.7.2 stable reachable as `godot` on the PATH
  (`make GODOT=/path/to/godot ...` overrides it) and the official 4.7.2
  export templates for macOS (Universal 2), Windows x86_64, and Linux x86_64
  under `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
  for the export targets (see "Export")
- optional, for `make export-linux-smoke`: Docker through colima with Rosetta
  (`colima start --vz-rosetta`) to run the Linux build headless in a
  linux/amd64 container
- Python 3 for the tooling and tests
- a retail Warblade 1.34 installation at `Game/` (`Game/warblade.exe`,
  `Game/data/warblade.pac`); it is not part of this repository and git
  ignores it. A clone needs it once to rebuild the excluded assets and
  content tables (see "Repository contents and rights"), and the extraction,
  evidence, and fidelity targets read it directly.
- only for deploying the lobby server: rustup's stable toolchain with the
  `x86_64-unknown-linux-musl` target, `cargo-zigbuild`, and zig from Homebrew

## Run

All `make` targets run from the repository root.

```sh
make run
```

Solo, Time Trial, and couch co-op start a local game server — the same
authoritative server binary, headless and bound to `127.0.0.1` — and need no
network. The client sends the HELLO match request plus input/shop/ready/pause
commands and renders authoritative snapshots; it does not advance the
simulation.

### Online co-op

START → HOST 2 PLAYER CO-OP (ONLINE) binds the same server publicly on the
HOST PORT from SETTINGS (UDP 42000 by default), lists the game on the lobby
server, and opens a waiting room with party chat. START → JOIN ONLINE GAME
shows the listed games; joining introduces the two Macs through the lobby
server's UDP rendezvous (hole punching, plus UPnP on the host's router when
available). CONNECT TO HOST joins by address, port, and token instead, for
LAN play or a manually forwarded port. The first online action asks for a
nickname; the lobby address and ports live under SETTINGS → LOBBY SERVER, and
CHAT on the title bar is the global room. macOS may ask once whether the game
may accept incoming connections and find devices on the local network; both
are needed to host.

The lobby server is `lobby-server/` (Rust, SQLite):

```sh
make lobby-run
```

runs it on `127.0.0.1:7400` (WebSocket) and `7401` (UDP) with a local
database; `make run-a` and `make run-b` start two clients with separate
identities on this Mac for a host/join smoke. The game defaults to the live
server at `68.183.194.133:7400` (UDP `7401`); point a profile at a local
server by entering `127.0.0.1` under SETTINGS → LOBBY SERVER.

`make lobby-deploy` cross-builds a static Linux binary on rustup's stable
toolchain (one-time `cargo install --locked cargo-zigbuild` and `rustup
target add x86_64-unknown-linux-musl --toolchain stable`) and installs it on
the droplet as the `warblade-lobby` systemd service (`DROPLET` defaults to
`root@68.183.194.133`). The first deploy writes `/etc/warblade-lobby/env`
with a random admin token; read it with `ssh root@68.183.194.133 cat
/etc/warblade-lobby/env`. Run `lobby-server/deploy/ufw.sh` once on the
droplet to open 7400/tcp and 7401/udp (it only adds rules). Nightly SQLite
backups land in `/var/backups/warblade-lobby` (14 days), and `make
lobby-admin` opens the owner statistics page through an ssh tunnel.

### Identity, data, and privacy

There are no passwords or logins. On first launch the game creates a random
32-byte device key in `user://identity.json`, and the lobby server stores only
its SHA-256 plus the nickname bound to it; deleting that file abandons the
identity, and the owner can reset an account's key from the admin page. The
server keeps nicknames, talent points and purchased nodes, the last public IP
seen per account, the global chat log (pruned hourly to the newest 5000
messages), and the self-reported match records that earn talent credits. It
never sees or relays game traffic: the host's Mac runs the match and relays
party chat. Talents are cached in `user://talent_cache.json` so solo and
couch play work offline, and the `--profile-suffix=<tag>` launch flag keeps
separate identity, cache, and settings files for running two instances on
one Mac (`make run-a`, `make run-b`).

Controls:

- Player 1: `A` / `D`, `Space`
- Player 1 secondary ordnance: `Q`
- Player 2: left / right arrows, `Enter`
- Pause/resume: `P` or `Escape`
- Controllers: first connected controller for player 1, second for player 2

## Verify

```sh
make verify
```

This runs:

- the enhanced parser's lossless LVD tests
- asset/hash/provenance validation
- deterministic presentation-manifest regeneration plus a Godot resource-load
  smoke for every declared raster, music track, and SFX
- all one hundred LVD round-trip tests
- SWD decode/runtime-content round-trip tests
- weapon-runtime evidence regeneration tests
- sprite-atlas/HMA and difficulty-rule extraction tests
- deterministic simulation and pixel-mask collision tests
- executable-contract and deterministic controller tests for levels 6–100,
  all four bosses, Memory Station, Meteor Storm, and the final credits gate
- protocol/authority tests
- the gap-matrix language contract and two-run level-100 frame-hash replay
  matrix for solo and co-op;
  these full-route runs use shipped pixel/HMA collision with an explicit
  bounded combat-resource assist recorded in every replay, while focused tests
  cover production starting loadout, economy, rockets, and fighter depletion
- client/layout tests
- lobby server unit tests, the Python lobby smoke, lobby client and transport
  tests, NAT traversal mechanics, the host/join loopback test, and the
  sidecar/two-client integration tests

Targets that read the retail executable or `warblade.pac` need the `Game/`
installation and fail with a clear message without it; the simulation,
network, lobby, and client suites run standalone.

## Local multiplayer harness

```sh
make harness
```

The harness starts one authoritative co-op server and two independent client
processes, one per seat. Couch co-op in the normal menu instead authenticates
one local peer for both seats.

## Export

```sh
make release-build
```

`release-build` runs the fast release gates (`make release-gates`: version,
contract, gap-language, tool, parse, protocol, client, and packaged-smoke
checks that need no retail installation) and then `make release-artifacts`,
which produces:

- `build/Warblade.app` and `build/WarbladeServer.app` (macOS, Universal 2,
  ad-hoc signed)
- `build/windows/Warblade.exe` (Windows x86_64, PCK embedded, unsigned)
- `build/linux/Warblade.x86_64` (Linux x86_64, PCK embedded)
- `dist/WarbladeRemake-<version>-macos-universal.zip`,
  `dist/WarbladeRemake-<version>-windows-x86_64.zip`,
  `dist/WarbladeRemake-<version>-linux-x86_64.tar.gz`, `dist/SHA256SUMS.txt`,
  and `dist/RELEASE_NOTES.md` (the matching `CHANGELOG.md` section)

The macOS export keeps its gates: both signatures are verified strictly, the
packaged client and server boot against the default endless (retail-clamp
3999) boundary and representative explicit compatibility boundaries, the
packaged client rejects level 4000 before spawning its sidecar, and every
declared presentation resource loads from the exported PCK. The Windows and
Linux binaries are checked by `tools/export_artifact_verify.py` (PE32+/x86_64
or ELF64/x86-64 headers, the embedded Godot 4.7.2 PCK trailer, and the Windows
version resource), and `make export-linux-smoke` runs the Linux binary's
presentation and packaged-client smokes headless in a linux/amd64 Docker
container. Nothing here launches the Windows build; that needs a Windows
machine. `make export-release` is the same artifact chain behind the full
`make verify` gate for a checkout that has the retail `Game/` installation.

Publishing: `make release-publish` tags `v<version>` on the current `main`
commit, pushes it, and creates a draft GitHub pre-release with the four
`dist/` files; `make release-finalize` publishes the draft;
`make release-rollback CONFIRM=yes` deletes the release and the tag again.

## Release boundary

Version 0.1.0 defaults to content version 12 and an endless match bounded only
by the retail level clamp 3999. Any explicit boundary from 1 through 3999
remains supported. Earlier boundaries use the existing generic result flow;
bosses at 25, 50, and 75 continue exactly once when the configured boundary
extends beyond them. On the default route the level-100 boss leads into the
recovered 13-image ending/credits sequence as an interstitial — the
authoritative score is recorded as the profile's level-100 milestone — and
play continues at level 101 with the per-hundred difficulty escalation.
Bounded matches ending exactly at level 100 keep the terminal credits route
with `ALL 100 LEVELS CLEARED`.

Releases are tagged `vX.Y.Z` and published on GitHub Releases with
per-platform archives and SHA-256 sums (see `CHANGELOG.md`); the retail
extraction history and evidence reports remain local.

## Parser and evidence

The primary retail decoder is `Parser/scripts/lvd_lossless.py`; the
presentation inventory and validation parser is
`Parser/scripts/warblade_presentation.py`.

The older parser/editor workflow remains available but its friendly LVD field
names are marked legacy and unverified. Recovered executable addresses, exact
hashes, claim-level confidence, asset provenance, and evidence-only raw fields are under
`docs/evidence`.

## Repository contents and rights

Original work in this repository: `src/`, `scenes/`, `tests/`, `tools/`,
`Parser/scripts/`, `lobby-server/`, `content/talents.json`, the design
documents under `docs/`, and the AI-generated replacement art under
`assets/packs/`.

Retail-derived material is never committed: `assets/original/` (rasters,
music, samples, voice packs, level and path files copied from the retail
`warblade.pac`), `assets/generated/`, the generated `content/*.json` tables
and `content/lvd_decoded/` (decoded from the retail executable and level
files), `Parser/Reports/`, and the machine-readable extraction reports under
`docs/evidence/`. `.gitignore` excludes them, so a clone holds the code, the
design documents, and `content/talents.json` only. Warblade and those assets
remain the property of the original game's author. The compiled builds on
GitHub Releases embed that material under the authorization from the original
author recorded in `export_presets.cfg` (`application/copyright`); it is still
never committed or published as loose files. The rights boundary is spelled
out in [`docs/evidence/README.md`](docs/evidence/README.md) and row N04 of
[`docs/GAP_MATRIX.md`](docs/GAP_MATRIX.md). To run the game from a
clone, place your own retail Warblade 1.34 installation in `Game/` and
rebuild the excluded files with the tools described under "Reproduce and
validate" in [`docs/evidence/README.md`](docs/evidence/README.md):
`tools/extract_original_assets.py` restores `assets/original/` and the
`tools/*_extract.py` scripts regenerate `content/`. The lobby server builds
and runs on its own without any of that.

Nothing in the tree grants access to the lobby server. The admin token exists
only on the droplet in `/etc/warblade-lobby/env` (mode 600), deploy access is
an SSH key in `~/.ssh` on the deploying Mac, and the repository holds only
placeholders: `lobby-server/deploy/env.example` and the loopback-only
development token in the Makefile. The signing and notarization fields in
`export_presets.cfg` are empty. `.gitignore` refuses the retail installation
in `Game/`, `export_credentials.cfg`, and `*.db` files; never commit a filled
env file or SSH keys.

## Trust boundary

The architecture keeps the server-authoritative contract: clients cannot
submit positions, damage, rewards, inventory, or level state, and the match
itself is negotiated through the normalized HELLO contract. Hosting is
player-owned: the host's Mac runs the authoritative server for its party, and
whoever holds the game token controls that match. There is no anti-cheat, and
the lobby server trusts what clients report (match results, talent credits).
The lobby link itself is plain `ws://` in this release, so nicknames, chat,
and the device key travel in cleartext; TLS through a reverse proxy is a
follow-up once the server has a DNS name.
Trusted online hosting remains an independently bounded program.
Cross-platform delivery is partial: 0.1.0 ships Windows and Linux builds,
while signing, input certification, and platform QA on real hardware remain a
separate program; neither is a gap in the supported macOS release.
