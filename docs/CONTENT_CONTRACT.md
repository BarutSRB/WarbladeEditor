# Compiled Content Contract

The authoritative server and every client load the same versioned JSON
catalog. Content version 12 requires twelve documents: the eight legacy
documents plus `bosses.json`, `ordnance.json`, `time_trial.json`, and the
remake-original `talents.json`. Files use stable array ordering and
integer/fixed-point gameplay values except where an executable-pinned contract
preserves scalar values directly. Their ordered byte-level SHA-256 is part of
the handshake; a mismatch is rejected before a seat can send gameplay commands.

The 1.0.0 wire/content versions are:

| Contract | Version |
| --- | ---: |
| Transport protocol | 8 |
| Match content | 12 |
| Levels | 10 |
| Sprite frames | 11 |
| Bosses | 5 |
| Ordnance | 1 |
| Time Trial | 1 |
| Talents | 1 |
| Snapshot | 12 |
| Replay | 12 |
| Hash state | 12 |
| Saved game | 1 |
| Profile | 5 |
| Shop | 1 |
| Presentation | 2 |

The catalog reader keeps levels v1–v9, sprite frames v2–v10, and bosses v1–v3
readable for deterministic compatibility. It synthesizes resource slot 1 from
the legacy scalar enemy fields. Explicit compatibility maps retain levels v5
with bosses v2, ordnance v1, and sprite frames v6. The levels-v6 map requires
bosses v3, ordnance v1, and sprite frames v7. The levels-v7 map retains bosses
v3 and ordnance v1 while requiring sprite frames v8. The levels-v8 map requires
bosses v4, ordnance v1, and sprite frames v9. The levels-v9 map retains
ordnance v1 while requiring bosses v5, sprite frames v10, and all 100 levels.
The levels-v10 map retains bosses v5 and ordnance v1 while requiring sprite
frames v11 and `time_trial.json` v1 for retail match mode 6 (Time Trial);
missing or mismatched contracts fail closed. Content v12 additionally requires
`talents.json` v1 (schema `warblade.talents.v1`) — remake-original talent
content, not retail recovery: a validated DAG of purchasable nodes whose
grants stay inside the contract's start-state vocabulary, whose licenses gate
exactly the four migrated shop effects (`enable_autofire`,
`enable_super_autofire`, `rocket_pack`, `enable_alien_lock`), and whose gated
list must equal the match contract's mirror. With `talents_enabled` false the
gated items keep their retail unlock rules byte-for-byte.

## Required files

### `levels.json`

Each of the one hundred level entries retains the source LVD path/hash and an
`authored_lvd` object with schema `warblade.lvd.authored.v2`. That object
contains the executable-backed logical width/mirroring/mode, five raw
supplemental records, all fifty four-word fixed-table records, and ordered
groups with:

- entry origin, activation delay/stagger, initial velocity, cohort, and mode
- every active enemy's formation target, resource, base health, and timer A/B
  initial/step values
- ordered entry-path acceleration, opcode, lossless evidence-only word, and
  strict progress threshold

Schema `warblade.levels.v9` retains the ordered `enemy_resources` entries added
in v3, with
`resource_slot_id`, `raw_name`, `enemy_sheet_id`, and traced `kill_score`.
`enemy_sprite` and `ordinary_kill_score` remain slot-1 aliases. Every authored
enemy and supplemental spawn resolves through its declared resource slot;
missing sheets, masks, or slot-specific scores are rejected. Levels 1–25 select
`stars1`, levels 26–50 select `stars2`, levels 51–75 select `stars3`, levels
76–99 select `stars4`, and level 100 selects `stars1` under the pinned retail
modulo-100 selector. Authored mode 6 is ordinary combat with target-facing
lateral shots. Its direction compares the fighter and alien records' retail
top-left X values, targets the active owner in solo, and consumes exactly one
lateral-speed RNG draw; remake co-op targets the nearest active player. Level 80's group mode 3 and level
94's opcode 2 are accepted only at their pinned locations.

Simultaneous co-op with shared-party progression is the intentional remake
modernization and the only two-player mode in the product. The retail
two-player modes (simultaneous Duel and alternating play) were removed by user
decision (2026-08-10) and are preserved on the `retail-two-player-modes`
branch.

The older `waves` objects are predecessor-read compatibility scaffolds. Their
score, cash, projectile, and generic path fields are not evidence for retail
behavior and cannot alter v9 authoritative play. Current combat defaults and
speed are explicit versioned runtime contracts.

### `swd_paths.json`

Schema `warblade.swd.runtime.v1` contains all 14 packaged `attNNN.swd` files in
the executable's compacted global order. Each record preserves its source hash,
active count, `1/256` initial velocity, numeric return selector, and active
points:

```json
{
  "acceleration_x_fixed_256": 0,
  "acceleration_y_fixed_256": 38,
  "opcode": 0,
  "unresolved_word_3": 0,
  "progress_threshold": 21
}
```

The document requires `selection_scope: "global_loaded_catalog"` and
`inactive_runtime_point_policy: "zero_fill"`. The lossless SWD decoder retains
all 150 disk slots separately; this runtime document intentionally contains
only active points.

### `bonuses.json`

Schema `warblade.bonuses.v1` preserves the executable's complete 37-entry
falling-bonus table in logical-type order `0..36`. Every entry carries its
selection weight, stable numeric effect ID, and the proven `20×20`, ten-frame
atlas geometry with source X zero and its exact source-Y row. All 37 entries
carry recovered semantic effect keys consumed by the server's bounded retail
dispatch, including timed effects, sucker completion, bombs, special modes,
Scoop, Freeze, and progression fallbacks.

The spawn contract also records the 150-slot pool, the total selection weight
of 2,252, X jitter, animation period/phase arguments, and the executable call
arguments and strict comparison used to reroll types 12, 13, and 14 against the
active player's current weapon progression.

### `weapons.json`

The top-level `fire_control` object requires edge-latched manual fire, 100 ms
Auto Fire, 25 ms Super Auto Fire, and a strict-greater-than deadline. Each
weapon has a stable ID, 16.16 damage, sound ID, and an ordered flattened
projectile graph:

```json
{
  "prototype_id": 19,
  "offset_x_fp": 0,
  "offset_y_fp": -327680,
  "velocity_x_fp": 0,
  "velocity_y_fp": -1638400,
  "special_secondary_raw": 165,
  "width": 32,
  "height": 78
}
```

`special_secondary_raw` preserves the executable's Fireballs spawn-jitter and
War.I.Plasma velocity-spread encodings. Laser frame continuation
`22 -> 23 -> 24 -> 50` is supplied by the proven sprite/runtime contract, not
modeled as four independent weapon roots.

### `difficulties.json`

The four stable IDs are `easy`, `normal`, `hard`, and `ace`. Each entry stores:

- simulation scale as numerator/denominator (`6/6`, `6/6`, `7/6`, `8/6`)
- timer A and B initial adjustment and floor
- alien-projectile speed numerator/denominator
- player base speed and speed-upgrade numerator/denominator
- timed-effect seconds, bonus-time start/maximum/floor, and the falling-bonus
  drop denominator

The loader derives 16.16 runtime values and the 16-upgrade stored speed ceiling.
These rationals are a deterministic server normalization of proven retail
float32 rules, not a bit-exact claim at floating-point boundaries.

### `sprite_frames.json`

Schema `warblade.sprite-frames.v10` binds levels 1–100 to ordered per-resource
enemy sheets and stores executable-derived source rectangles for:

- 16 directional and six formation/state-10 32×32 enemy frames, including the
  recovered seeded/reversed state-10 frame producer and retained-frame rule
- the seven reachable supplemental 64×64 frames, including level 15 phase 6
- both 11-frame fighter banking sheets
- every projectile reachable from the nine weapons, including all Laser frames

It also records all enemy sheets used through level 100, recurring supplemental
linkages, type-6/type-7 per-sheet phase masks, sheet-specific retail broad-phase
bounds, HMA dimensions, occupancy convention, orientation checks, and
executable provenance. Collision consumes the original HMA bytes from the same
source rectangle rather than deriving occupancy from texture alpha.

### `bonus_modes.json`

Schema `warblade.bonus-modes.v1` pins the bounded executable regions and exact
asset hashes for four related retail contracts:

- recurring level-8/16/24/33/41/49/58/66/74/83/91/99 per-owner hit/display/perfect counters, reveal
  rewards, deadlines, shared perfect-chain reset/progression, Warp, and
  recurring-shop handoff; level 33's mode-three shop is independent of the
  ordinary every-fourth-level flag, and the legacy level-8 projection remains
  synchronized
- Memory Station board growth, weighted tile/effect dispatch, score/deadline
  rules, and presentation bindings
- Meteor Storm's 30-slot motion/spawn/collision state, biased bonus draw,
  difficulty growth, score/cash/gem outcomes, and result flow
- exact rank-0 announcement queues and padding for profile ranks 1–20

The whole document participates in the content hash. These controllers suspend
ordinary combat while active and export only bounded semantic actions through
the authoritative protocol.

### `bosses.json`

Schema `warblade.bosses.v4` retains the level-25 and level-50 contracts and adds
the level-75 Big3 and level-100 Big4 state-13 encounters. Each exact
contract pins initialization and RNG order, its ordered six-sheet
stage/animation state, HMA collision parts, health and damage, projectiles,
rewards and rank marks, music ownership, death sequence, and post-boss routing.
The later contracts bind their six ordered sheets, exact health/rewards, path
behavior, HMA parts, and projectile sheets. Level 100 additionally owns both
ordered mode-6 burst groups. Generic
enemy handlers and the liveness watchdog do not own boss completion. Explicit
end-level 25 completes after its traced defeat; longer matches enter Get Ready
26 exactly once. An explicit end-level 50 completes after the second boss;
longer matches enter Get Ready 51 exactly once, and level 75 follows the same
boundary rule for level 76. A bounded match ending exactly at level 100
publishes pending level zero and the terminal result instead of requesting
level 101; an endless match rolls the level-100 credits interstitial and
continues at level 101.

### `ordnance.json`

Schema `warblade.ordnance.v1` is the executable-backed authority for the Rocket
Pack, Alien Lock, and the shared projectile-stat interaction. It participates
in the content hash and is mandatory with levels v3 through v10. Rocket snapshots use the
same canonical projectile metadata required of ordinary player projectiles.

Rocket Pack purchase adds 10 missiles and clamps at 50. A pre-count below 50
is accepted and charged once, including counts 41–49; a pre-count of 50 or more
is rejected without changing cash. Secondary fire is release-armed. A full
shared 100-record player-projectile pool or an empty eligible-target set
consumes the press edge but no ammo, sound, or later-stage RNG. A successful
spawn consumes one weighted target draw, then the two animation draws, charges
one missile, and retains the firing physical seat as owner. The HMA-backed
`768×72` atlas contains 32 headings by three `24×24` animation rows. A missile
deals 200 ordinary damage and 20 state-13 boss damage before the dedicated boss
controller owns terminal behavior.

Alien Lock does not alter rocket targeting, weighting, reservation, or RNG. It
is a one-shot per-seat purchase that preserves the owner's two captured-alien
fields through Warp; ordinary death consumes the lock while preserving Rocket
Pack inventory in every supported match mode. The executable's mode-6
exception applies only while Time Trial is the active match mode and never to
Warp or Warp Malfunction. Any
successful player-projectile allocation, primary or missile, disqualifies the
alien-projectile final-kill reward. Missile shots use
a separate counter, while confirmed missile hits increment the shared hit
numerator; the resulting accuracy percentage is clamped to 100.

### `time_trial.json`

Schema `warblade.time-trial.v1` is the executable-backed authority for retail
match mode 6. It participates in the content hash and is mandatory with levels
v10. Every runtime value is read back from pinned instruction bytes by
`tools/time_trial_extract.py` and republished in
`docs/evidence/TIME_TRIAL.md`.

The `runtime` object carries the match clock (181,000 ms, the grouped-best
"+1 minute" variant at 241,000 ms, and the 10,000 ms clamp used when no level
files resolve), the two match-mode globals, the `timetrial_%02d.lvd` loader
with its sequential selection and wrap, and the mode rules: one seat, starting
weapon 0, no shop, warp, warp-malfunction, bonus-mode, rank, or credits phase,
no hurry-up special ships, no death loadout reset, tally kind `time_trial`, and
hall-of-fame table kind `timetrial`. The grouped-best lock list records which
profile tiers the mode-6 branch of the retail applier consumes, and why its
weapon tiers do not.

The fifteen `levels` entries use the same `warblade.lvd.authored.v2` payload
schema as `levels.json`, with IDs 1 through 15, `shop_after` always false, and
`mirror_x` always false. They carry no predecessor compatibility waves and no
supplemental spawn records. Their enemy resources bind the eighteen additional
sheets that `sprite_frames.json` v11 publishes in `time_trial_level_usage`,
which is a separate namespace from the classic `level_usage` because both
number their levels from one.

### Saved games

Retail writes an in-shop saved game with `FUN_00537c80` and loads it with
`FUN_005384f0`, addressing slots through
`%s\warblade\profiles\profile%03d.svg`. Each file is a compressed raw image
of the 694,296-byte retail state block that begins with the `SDY` signature, so
byte compatibility with the original files is neither reachable nor meaningful
for a different engine. The remake keeps the behavioral contract instead:
saving is offered only from the shop, slots are numbered, and a resumed run
continues exactly where it stopped.

The remake's save (`warblade.shop-save.v1`) carries the match configuration and
the authoritative shop-boundary state — tick, level, progressions, profile
statistics, persistent flags, the RNG position, and the level residue that the
authoritative state hash covers. Restoring reproduces the shop boundary
bit-identically, so a resumed run and a run that was never saved stay on the
same state hash. Retail rebases its absolute timed deadlines against the wall
clock at save and load; the remake derives simulation milliseconds from the
tick counter, so restoring the tick restores every deadline with it.

The authoritative simulation owns the state in both session shapes. A direct
simulation exports the save to the client, which writes the slot; a networked
session sends the protocol `SAVE` command and the authoritative server writes
the slot itself and acknowledges the outcome. A resumed networked run launches
its sidecar with `--resume-slot`, so the server loads the slot rather than
configuring a fresh match.

### `shop.json`

The shop document contains stable item IDs, exact prices, categories, optional
weapon IDs, unlock records, and a bounded effect identifier interpreted only by
the server. The first shop occurs after level 4 and exposes item IDs 1–17.
Server rules reject an already-equipped weapon and capped upgrades, implement
Extra Time's pre-check/no-post-clamp behavior, advance Rank Marker as a six-bit
mask, and make Game Secret select presentation art without granting a gameplay
upgrade. Exiting with a full mask performs the independent multiplied-million
cashout; a below-cap rank enters the recovered four-second-gated mode-20
promotion ceremony before Get Ready, while capped ranks bypass that ceremony. Shop items 18–20 use inclusive active-owner accuracy thresholds
of 70, 80, and 90. Profile v5 stores the monotonic, clamped
`best_hit_percent_above_level_25`; the server samples
`floor(100 * hits / shots)` only when entering a level strictly above 25, so an
explicit level-25 ending never fabricates a sample. Profile v5 also stores the
best authoritative `level_100_score` from a run that crossed level 100. The
default campaign runs cadence shops through level 96, plus recurring mode-three
shops after levels 33, 41, 49, 58, 66, 74, 83, 91, and 99. Bounded matches may
end at level 100; the default route rolls the level-100 credits as an
interstitial and continues endlessly with the per-hundred progression step
(`docs/evidence/ENDLESS_PROGRESSION.md`), cycling the authored content with the
per-hundred mirror up to the retail clamp 3999. Every explicit boundary from 1
through 3999 remains supported; bounded matches below 100 bypass credits.

## Validation and confidence

The catalog rejects unsupported versions/schemas, missing files or fields,
duplicate/noncontiguous IDs, invalid numeric values or prototype closures, an
incomplete 14-path SWD catalog, and a handshake hash mismatch.

Evidence status belongs to individual source contracts:

- **Proven exact:** decoded source bytes, authored LVD/SWD ordering and values,
  traced one-hundred-level state/weapon/difficulty/projectile/reward/bonus/shop
  rules, recovered presentation contracts, bonus-mode controllers, rank-0
  speech queues, the five-word PRNG and wrappers, and sprite/HMA rectangles
- **Evidence-only:** source fields with no reachable finite-product consumer
  remain lossless raw values without invented semantic names
- **Deterministic modernization:** match-start seeding, integer/rational
  coordinate arithmetic, simultaneous shared-party co-op, high-refresh
  interpolation, ending firework cadence/particle layout, and the bounded
  runtime SFX mix policy, plus accessible composition/timing around native
  retail screen bitmaps
- **Non-goal/separate program:** `.mus`, redistribution, trusted hosting, and
  cross-platform delivery do not create runtime obligations for this contract;
  Time Trial does, through `time_trial.json`

The machine-readable values do not turn an evidence-only field into recovered
retail behavior. `docs/GAP_MATRIX.md` is the complete classification ledger.

## Client presentation manifest

`presentation.json` schema `warblade.presentation.v2` is separate from the ten
authoritative gameplay documents and is not accepted as client gameplay state.
It declares exact, namespaced paths and source hashes for 313 loadable rasters,
96 raw HMA records, 10 MP3 music tracks, 116 compatibility SFX entries, and 31
rank-0 voices. Its generator revalidates the pinned retail PAC, external audio,
extraction provenance, output hashes, texture dimensions, and HMA geometry.
The client retains presentation v1 read compatibility; only v2 carries the
closed sequencing, background, bitmap-font, source-geometry, effect, and audio
contracts used by current exports. Accessible composition and timing around
the native title, pause, shop, and game-over bitmaps are an intentional macOS
modernization where no exact executable contract is proved.
For 38 runtime-consumed SFX, source identity and event binding are
evidence-backed while gain, concurrency, priority, loop, and pitch are an
intentional deterministic macOS mix policy. The other 78 entries are packaged
evidence with no runtime tuning consumer.

The presentation smoke path additionally opens all 96 raw HMA files and checks
their declared dimensions, byte counts, binary value domains, and SHA-256; the
export presets explicitly package those non-resource files.

The top-level `ending` object is client-only presentation data. It pins the 13
ordered `ending_*` textures and their 15-second slide durations, the exact
executable text split into story and credits, a 30-pixel/second scroll rate,
the 8× held-right-mouse multiplier, held-left-mouse text pause, endgame music,
an eight-second control reminder, and per-mode ending copy. Slides hold on
the final image while the exact source text independently loops. Mode metadata
is never concatenated into those recovered display bytes. The authoritative
terminal payload supplies ending mode, winner seat, and final score. The client
also duplicates the existing snapshot-v9 RNG/tick into its local firework
controller; it never accepts presentation state back into authority.

Every binding carries an evidence confidence. Missing required presentation
resources fail normal client startup; release smoke loads every declared
Texture2D and AudioStream from the exported PCK. HMA records are validated as
raw top-left row-major 0/1 occupancy and are never sent through Texture2D
loading.

Tracker-module (`.mus`) playback is a permanent product non-goal. The extracted
MP3 set is the final music system; module data is never investigated, extracted,
converted, emulated, implemented, or scheduled by the content pipeline.
