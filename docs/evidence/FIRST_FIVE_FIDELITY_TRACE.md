# First-Five Runtime Fidelity Trace

This trace is the executable-backed authority for the first-five motion,
projectile, random-number, reward, bonus, lifecycle, and first-shop behavior
audited after the playable remake pass.
It supplements the subsystem traces and records the cross-system ordering that
is easy to lose when each subsystem is considered separately.

The machine-readable companion is `first_five_runtime.json`. Regenerate or
verify it from the Remake root with:

```sh
python3 tools/first_five_runtime_extract.py
python3 tools/first_five_runtime_extract.py --check
```

The checker locates `../Game/warblade.exe`, requires SHA-256
`ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`,
requires the five exact retail LVD hashes, and verifies the bounded instruction
and data regions currently enumerated in the JSON fixture. Addresses are
virtual addresses in that 32-bit PE image. The Warp subsection is an additive
bounded disassembly trace against the same pinned executable and is serialized
into `first_five_runtime.json` together with the verified malfunction LVDs and
voice sample.

## First-five reachability

| Level | Mode | Groups / ordinary enemies | Cohorts | Path opcodes | Reachable special behavior |
| ---: | ---: | ---: | --- | --- | --- |
| 1 | 1 | 2 / 18 | 0 | 0, 1 | state 2 formation, state 3 SWD, state 4 late-tail roaming |
| 2 | 1 | 2 / 22 | 0 | 0, 1 | state 2 formation, state 3 SWD, state 4 late-tail roaming |
| 3 | 1 | 2 / 24 | 0 | 0, 1 | ordinary loop plus one supplemental state-6 enemy |
| 4 | 2 | 25 / 25 | 0, 1, 2, 4, 5 | 0, 6 | state 10 for every ordinary enemy |
| 5 | 1 | 2 / 22 | 0 | 0, 1 | state 2 formation, state 3 SWD, state 4 late-tail roaming |

All active groups use group mode 1. Level 3 supplemental record 0 is exactly
`[1,1,12,1200,25]`; its count and selector make state 6 first-five reachable.
Level 4's terminal opcode 6 and mode 2 reach the state-10 write at
`0x00608caf`.

## Enemy entry, formation, and late-tail roaming

The state-1 integrator and terminal checks are at
`0x006088e0-0x00608a31`. On a mode-1 terminal opcode-1 marker, the branch at
`0x00608a91-0x00608ab0` writes only entity state 2 at `0x00608aa5`. The
equivalent alternate branch writes only state 2 at `0x00608ac9`. Neither
branch writes X, Y, velocity, or acceleration.

Therefore an entry-to-formation position snap is not retail behavior. The
entity keeps the final integrated entry position and state 2 subsequently
applies its proven 1/20 formation easing.

When entry advances to another LVD segment, the store at
`0x006145ee-0x0061461d` resets that segment's elapsed progress to float zero.
It does not start the next segment at one tick. SWD paths use a separate
tick-scale reset and must not share this rule.

Formation itself is not static. Retail initializes the platform oscillator at
`0x0056ad01-0x0056ad72` and advances it at
`0x0060608c-0x006061e8`. Before a state-2 leader begins state 3, the current
platform X/Y drift is baked into its position at
`0x00609990-0x00609ad5`. Recruited followers receive the same treatment at
`0x00609efb-0x00609f71`.

State-3 terminal handling has distinct selector branches beginning at
`0x0060c16c`, `0x0060c595`, and `0x0060c9fa`. State 4 consumes the selected
route at `0x0060cbd4-0x0060dbf3`; a generic direct homing replacement is not
equivalent to these executable branches. The first-five path uses a single
level-wide randomized tail cutoff, dedicated state-4 horizontal velocity and
acceleration, randomized turns, strict horizontal wraps, and downward wrap.
Entry/SWD velocity is retained in its own fields and must not leak into this
roaming vector.

The state-6 direction tables are the 40 float32 X/Y entries at `0x007d0558`
and `0x007d05f8`. Its steering countdown and player/screen-dependent chooser
are in `0x0060f13a-0x0060f8f7`. The exact table hashes, edge branches, strict
timer behavior, and initial level-3 headings 18 through 22 are pinned in the
JSON fixture.

## Level-4 state-10 boundary

The state-10 update's deactivation block is
`0x0060e4de-0x0060e533`. In retail top-left coordinates it performs this
strict test after updating X, horizontal velocity, and Y, but before updating
vertical velocity and acceleration:

```text
if enemy_y + 32 < viewport_top - 100:
    deactivate
```

The global `0x00e113d8` is initialized to zero as the viewport's top at
`0x005a176e`. The same initializer stores viewport bottom 600, left 0, and
right 800 in the neighboring fields. It is not logical height. For the
remake's center-coordinate contract the equivalent default-viewport test is:

```text
center_y + 16 < -100
```

Equality survives. Treating `0x00e113d8` as height causes every level-4 enemy
to satisfy the wrong condition during its first state-10 update, which is the
observed disappearing-kamikaze defect.

## Projectile pool, physics, and order

Ordinary alien shots use the shared 100-slot projectile pool. The allocation
scan at `0x006077d2-0x006077fe` proves a 100-entry limit and 140-byte stride.
The active, animation-phase, and animation-countdown bases are respectively
`0x00af7ea4`, `0x00af7ea8`, and `0x00af7ed0`.

Type-7 spawn initializes the countdown but does not overwrite the slot's
phase, so inactive-slot phase history is observable after reuse. Its stored
coordinates are top-left coordinates:

```text
shot_x = enemy_x + 13
shot_y = enemy_y + 16
shot_vx = 0
shot_vy = difficulty_projectile_speed * tick_scale
```

The X/Y stores are at `0x0060782c-0x00607886`, constants 13 and 16 are the
float64 values at `0x00779c20` and `0x0077d848`, and the zero-X-velocity branch
is `0x006079e0-0x006079eb`. The common update advances phase, then adds
velocity at `0x00602d49-0x00602d9d`. It deactivates only when stored top-left
Y is strictly greater than 600 at `0x00602da3-0x00602de0`; there is no retail
ordinary-shot TTL.

Both type 6 and type 7 subtract the difficulty tick scale from their saved
animation countdown, preserve the current phase at exact zero, and only on
negative underflow reset to 1.0 and decrement/wrap the two-frame phase. Update
and collision scan common slots in ascending order, so reuse of a low slot can
change which overlapping shot is consumed first.

Level 3's state-6 enemy takes a distinct aimed-fire branch beginning at
`0x0060e830`. After the fire roll passes it consumes draws in this order:

1. travel in `[45,55)`, multiplied by Easy `3.0`, Normal `2.2`, Hard `2.0`,
   or Ace `1.8`;
2. target-X jitter in `[-40,40)`;
3. target-Y jitter in `[-40,40)`;
4. only then scan the 100 common slots.

All three post-fire draws occur even when the pool is full. Velocity divides
the vector from the 64×64 enemy's top-left—not the projectile spawn—toward the
jittered fighter top-left by travel, then multiplies by tick scale. Stored
projectile top-left is `(enemy_x+32, enemy_y+25)`. Type 6 renders and samples
the 32×32 HMA cells at `(448, phase×32)`; type 7 uses X=480.

The alien-shot collision loop is `0x0058444f-0x00584a47`. It walks the same
100 slots and consumes each projectile's dimensions and HMA-backed shape.
The original firing-alien frames are 32 by 32; replacing this with a 5-by-10
rectangle changes transparent-pixel and edge behavior.

Retail first applies narrow strict broad metadata and then tests the full
unscaled 32×32 HMA. Type-6 metadata is `[0,1,11,12]`; first-five type-7
metadata is `[0,0,5,13]` on `alien001` and `[0,0,3,11]` on `alien_2`.
The final two values are coordinate extents, preserving retail's off-by-one
broad rectangle rather than scaling the HMA down to that rectangle.

Player projectiles update in `0x0061fff0`. The bounded checks at
`0x006209bd-0x00620b0c` truncate stored float coordinates toward zero. A
coordinate is removed only when it is below `-50`; the horizontal high bound
is removed only above `800 + 50`. The comparisons are strict.

Player shots also occupy a physical 100-record pool, independently of the
weighted weapon-capacity gate. The allocator loop at
`0x005df81c-0x005df86f` scans slots 0 through 99 with a 160-byte stride and
claims the first inactive record. Update (`0x0061fff0`) and collision
(`0x00585840`) use the same ascending order, so an expired low slot is reusable
immediately and can win a collision before an older high-slot object. Mirror
and Scoop-captive graphs contribute zero to the weighted gate but still consume
these records. If no projectile is allocated, retail does not emit its firing
sound. The hidden Scoop selector also contains the otherwise unreachable
fighter-weapon row 9: damage 3.0, root prototype 67, velocity -20, size 26×68.

The gameplay-frame order is:

1. `0x005b122d` dispatches `0x00585840`, resolving existing
   player-projectile/enemy collisions and their death outcomes.
2. `0x005b1267` dispatches `0x0061fff0`, updating existing player projectiles.
3. `0x005b1276` dispatches `0x00601cd0`, updating existing common/alien
   projectiles.
4. `0x005b127b` dispatches `0x00605fe0`, updating enemies and allowing them to
   allocate new alien shots.
5. The later indirect call at `0x005b1865` uses slot `0x008476e8`, installed as
   the `0x00529141` thunk to `0x005842c0`, and resolves alien-shot/player
   collision.

This order makes a newly spawned alien shot eligible for player collision in
the same gameplay frame. It also means player shots collide before their
movement/frame-chain update, which is material to Laser's four live frames.

## Rewards, bonuses, and Scoop

The first word of each LVD tail score array yields ordinary state-4 scores of
`[50,20,50,500,50]` for levels 1–5. First-five ordinary kills grant no cash.
Complete normal groups award 10,000; level 4 instead completes cohorts for
2,000, 4,000, 8,000, 16,000, then 32,000. Kill accounting and completion are
traced through `0x00555c40`, while deactivation/capture accounting remains a
separate path. Only a qualifying final kill grants ten rockets up to 50;
already holding 50 converts that award to `50,000 × score multiplier`.

The falling-bonus producer at `0x0056ff10` uses a 150-slot pool and the complete
37-entry weighted table (total weight 2,252). The drop gate, spawn jitter,
float32 fall speed, animation period, phase, strict bottom expiry, and special
12/13/14 rerolls all consume the shared gameplay RNG in traced order. The
collection dispatcher at `0x00571c60` owns the recovered progression effects,
fallback scores, timed deadlines, bombs, and special-mode boundaries. Freeze
lasts ten seconds plus the strict-equality tick and gates whole active enemy
handlers while delayed activation and the formation platform continue.

The pickup dispatcher is split: collision/application runs before player-shot
collision, while pickup animation and motion run later. A collected record is
therefore inactive soon enough for a gem or ordinary drop created by a later
same-frame kill to reuse its exact low slot; that new object cannot be collected
until the next frame's early pass. Alternating play scans only the active turn.
Retail Duel uses the wrapper at `0x00584070`: one `RngInt(0,2)` yields the
original biased order `[P0,P0]` or `[P1,P0]`. The duplicate P0 scan remains
observable with Mirror because each full scan consumes its own side selector.
The remake-only co-op mode retains a fair two-seat analogue and is not claimed
as retail behavior.

Scoop does not use fighter-body collision. `0x0058d5e5-0x0058d7e0` builds a
strict 90-pixel tractor field above the fighter. For truncated top-left
coordinates:

```text
distance = clamp(player_top - enemy_top, 0, 90)
half_width = 4 + floor(distance / 2)
```

An alien qualifies only when one of its Y edges is strictly inside the beam
band and one of its X edges is strictly inside the tapered horizontal bounds.
The first two pool-order matches become persistent state-8 wingmen. Capture
advances completion as a deactivation but grants no ordinary kill/group/drop
reward. A third match grants `2,500 × multiplier` immediately, consumes float
draws for `vx∈[-4,4)` then `vy∈[-10,-6)`, and remains visible in state 5 until
its 32-pixel sprite top crosses the strict upper bound.

Memory Station (bonus type 6, retail mode 11) and Meteor Storm (bonus type 20,
retail mode 10) are dedicated game modes, not ordinary timed overlays. The
remake now runs each through a dedicated deterministic controller owned by the
authoritative simulation. Ordinary level time, player movement/fire,
projectile work, and enemy work remain completely suspended until the selected
mode reaches its recovered terminal transition. Memory Station owns its board,
selection/reveal clock, tile-effect dispatch, progression, and restoration;
Meteor Storm owns its 30-slot pool, ship physics, mask collisions, pickups,
Drunk variant, meters, multipliers, and reward tiers. The client renders and
scores neither mode independently.

## Warp and mode-16 malfunction

Fresh progression starts with Warp scalar `3.0` and companion value `8`.
Gameplay startup consumes `RngInt(0,8000)` to seed the first malfunction
denominator as `19000 + draw`; this happens before the common-projectile and
ordinary-entity initialization draws. An uninterrupted Warp is retail mode 13
and advances through exactly `100 + 200 + 100` subsystem updates. Update 399
remains in its third stage; update 400 finalizes it.

Bonus type 15 raises the scalar by `0.5` up to 8, raises the companion value by
2 up to 75, and owns four level-skip passes. Each ordinary skipped-level load
reinitializes the common projectile records and available non-captive enemy
slots, including their shared-RNG consumption. Retail special level modes 2,
3, and 4 are barriers rather than ordinary skip targets. In the first-five
route, using type 15 on levels 1–3 therefore stops on level 4; it does not skip
the authored kamikaze level. Existing falling pickups are not cleared merely
because this owned Warp starts.

Ordinary level-4 completion takes a different path. It raises the same scalar
by `0.5` up to 8 and the companion value by 2 up to 60, then enters a full
non-owned mode-13 Warp before deciding whether to open the shop. After update
400, money of at least 50 enters shop mode with level 4 still current and level
5 pending. Money below 50 proceeds directly to level-5 Get Ready. The shop
path owns a 500-millisecond input/fade guard, and equality with its deadline
still blocks readiness and purchases.

In retail Duel, type 15 raises and arms both session records regardless of
which fighter collected it. Session zero owns the shared mode-13/mode-16 Warp
fields. At finalization, shop eligibility is tested for P0 first and then P1;
the first session with at least 50 money and at least one remaining fighter
becomes the sole shop participant. If P0 shops first, exiting hands the same
shop directly to eligible P1 without another 500-millisecond guard only when
no below-cap promotion intervenes. A promoted P0 first enters retail mode 20;
P1 eligibility is re-tested when that ceremony ends, and the existing shop is
then handed over without a new guard. A capped full-mask cashout retains the
immediate route. P1's exit then ends the shop. Purchases and exit input from
the inactive Duel seat are ignored.

The malfunction gate is checked before every mode-13 subsystem update. It
first consumes `RngInt(0,current_denominator)` even while the Warp visual scale
is at or below 120. A value below 4 plus scale above 120 triggers the remaining
draws: reset-class `RngInt(0,100)`, a replacement denominator from either
`6000 + RngInt(0,12000)` or `20000 + RngInt(0,8000)`, and presentation pitch
`10000 + RngInt(0,4000)`. Mode 16 then selects one of the four recovered
`malfunction_01.lvd` through `malfunction_04.lvd` resource cases. Their live
sprite choices are:

| File case | Sprite resources |
| ---: | --- |
| 1 | `malfunction1`, `malfunction4` |
| 2 | `malfunction3` |
| 3 | `malfunction4` |
| 4 | `alien_malfold_blue`, `alien_malfold_green` |

File selection and the Warp-scaled enemy-budget draw precede entity creation.
Every entity consumes a resource-selector draw even for a one-resource case,
then draws spawn X, initial heading 18–22, health from the live companion
value, timer-A probe (and its conditional second timer draw), steering
countdown, animation interval/direction, speed, steering mode, and heading-step
countdown. On the Normal first-five path this is 12 shared-RNG draws per
spawned enemy after the file and budget draws. The result is a 64×64 state-6
enemy using the recovered state-6 steering and aimed-fire handler, including
the malfunction travel range `[30,60)`. Existing state-8 Scoop wingmen survive
the handoff; other live aliens are removed.

Mode 13 still runs the shared fighter callback: movement, animation, death
deadlines, and respawn continue, but firing is gated off. If the malfunction
gate changes the global mode before that callback, the entry frame is already
mode 16 and can fire. Malfunction entry sets the Warp visual tuple to stage
count 0, scale 0, velocity -5, effect 0, and offset 0; the same frame's visual
callback is a no-op. Natural return rearms the first 100-update stage without
resetting that tuple, so the following mode-13 frame advances from it.

The recovered mode-16 dispatcher order is pickup collision, player-shot
collision, player-shot update, visual no-op, pickup motion, common-shot update,
enemy update, fighter callback/respawn, completion/watchdog work, then the final
enemy-shot collision tail. Its inherited watchdog tests strictly more than 45
seconds since the last qualifying alien render. It arms the normal three-second
resolution without killing or counting live enemies. The render callback runs
after that poll and refreshes the timestamp only for a qualifying alien whose
truncated rectangle strictly intersects `[0,800)×[0,600)`; frozen aliens still
qualify, delayed state 1 and captured state 8 do not.

Malfunction entry immediately queues `alienshoot15` centered at a retail
random playback frequency in the half-open range `[10000, 14000)` Hz (the
sample source is 32000 Hz). It also arms one voice cue for 300 ms. Equality
survives; after the strict deadline, the next
millisecond queues `warpmalfunction` once at its original pitch, centered
and full volume, then rearms a dormant 1.6-second timer after the one-shot count
reaches zero. The executable loads that handle at `0x005358a3` from the string
at `0x007793ac`. The exact source MP3 is copied under the asset allowlist and
hash-pinned in both provenance and runtime evidence.

A mode-16 kill awards `5,000 × score multiplier` and, if the 150-slot pickup
pool has room, consumes one `RngInt(0,6)` color draw to create a 20×20 falling
gem from the matching `marks` row. Collection awards another multiplied 5,000,
sets that color's bit in the six-bit Rank Marker mask, increments the gem
counter, and consumes its presentation-pitch draw. Collecting all six colors
enables Super Auto Fire at the recovered 25-millisecond repeat delay. Once all
malfunction enemies are killed or missed, mode 16 observes the strict
three-second resolution deadline and one final complete mode-16 update before
restarting mode 13 from its first 100-update stage.

## Death, level flow, and first shop

Fighter loss is charged at the strict three-second respawn deadline, not at
the collision frame. A surviving fighter respawns with the recovered
invulnerability deadline; Armour consumes a charge and suppresses repeated
projectile hits for its own strict four-second window.

Counter resolution is polled at `0x005566f0` and transitions through
`0x005568f0`. Completion waits three seconds with strict equality, does not wait
for falling pickups, and includes the 45-second render-liveness watchdog. The
remake's separate bounded state-liveness guard is confined to ordinary level
mode and cannot mutate Warp/malfunction counters. After level 4, the full
400-update mode-13 Warp described
above runs before the money-gated shop decision. The shop retains logical level
4 with level 5 pending, then exits into the level-5 Get Ready phase after its
500-millisecond input guard.

First-shop cases are pinned at Extra Time `0x005621b1`, Rank Marker
`0x0056223d`, and Game Secret `0x00562741`. Extra Time accepts only while the
stored duration is below 45 and adds five without post-clamping. Rank Marker
adds the highest missing bit from `0x20` through `0x01`; a later full-mask
purchase awards one multiplied million once per level without clearing the
mask. Shop exit independently recognizes mask `0x3f`, clears it, awards another
`1,000,000 × score multiplier`, and increments rank below the default cap of
20 while maintaining the session's highest rank. Current and highest rank both
start at zero; the cap is explicit profile state whose first-five default is
20. A real promotion does not immediately continue to P1 or Get Ready. It
enters mode 20 (`0x005b1c8b`) with held fire locked for 4,000 ms and a safety
timeout of 1,200,000 ms. Equality opens the fire gate or triggers the timeout;
a button held across the four-second boundary dismisses immediately. After the
gate, `PRESS FIRE TO CONTINUE` blinks every 400 ms.

Every mode-20 update consumes `RngInt(0,100)` before polling its deadlines,
including the exiting update. A result below 2 enters the sparkle constructor
at `0x005547d0`: for primary particle count `N` in `[10,50)`, that triggered
update consumes `10 + 6×N`, plus ten more draws when its secondary selector is
below 2. The sparkle uses `explo3`; an eligible P1 handoff then consumes the
seven-way shop-voice selector. This is authoritative shared RNG state, not
client-only noise.

The ceremony presents `C O N G R A T U L A T I O N S`, `YOU ARE HEREBY
PROMOTED TO`, the recovered rank name, and the 64×13 `ranks2` badge row. It
uses the recovered source-Y table at `0x007d0f98` rather than assuming every
rank owns a unique row; the 23 inline rank names start at `0x007d10a8`. It loops
`promoted` music. The default first promotion queues the executable-proven
loose voice-pack-1 clips `congratulations`, `lieutenant`, and `rank` using the
recovered 100/50-ms queue padding; those arguments are padding, not volume.
Their source paths and hashes are pinned in provenance and runtime evidence.
This exit cashout belongs only to the active Duel profile before any P0-to-P1
handoff. Game Secret draws from
30 art IDs with the recovered eligibility/retry loop (or fixed ID 30 for its
special profile branch), updates seen/last IDs, and grants no gameplay upgrade.

## Retail random generator

The raw RNG thunk `0x0052856b` reaches the five-word unsigned core at
`0x0052f750`. The authoritative words are:

| Word | Address |
| --- | --- |
| X | `0x00d6250c` |
| Y | `0x00b0855c` |
| Z | `0x00b04210` |
| W | `0x00d59f58` |
| C | `0x009efd70` |

Startup calls the initializer at `0x0052ea50` through `0x0059f580`. It seeds
the bundled MSVCRT-compatible state, whose `rand` implementation at
`0x006fbf80` is:

```text
state = state * 214013 + 2531011       modulo 2^32
rand  = (state >> 16) & 0x7fff
```

Three `rand` calls initialize `X = r1`, `Y = r2 * X`, and
`Z = r3 * X + Y`, with unsigned wrap. Startup-zero W and C complete the state.
Each raw draw then performs:

```text
C -= X ^ (X << 11)
X, Y, Z = Y, Z, W
W = (W ^ (W >> 19)) ^ (C ^ (C >> 8))
return W
```

Every operation wraps modulo 2^32. The integer wrapper at `0x0052f6e0`
returns zero for a zero-width range; otherwise it returns
`raw_u32 % (max-min) + min`. The float wrapper at `0x0052f800` returns the
float32 boundary of `(max-min) * unsigned_raw_u32 * 2^-32 + min`; the exact
float64 unit scale at `0x00778e90` is `2^-32`.

The fixture includes initialization and eight-output vectors for seeds 0, 1,
`0xffffffff`, and `0x12345678`, so code can be tested without executing the
Windows binary.

The remake preserves gameplay-owned draw ordering: 100 common-slot phase
draws, three draws for each of 150 ordinary entity slots, the non-co-op tail
draw, level-3 supplemental draws, firing/selection/drop draws, and draw-before-
allocation behavior. Snapshots, state hashes, and replays retain X/Y/Z/W/C plus
a monotonic draw count. The intentional lifecycle boundary is deterministic
match-start seeding; retail instead seeded once per process from cursor/time
state and allowed menu/presentation activity to consume the same stream.

## Evidence and modernization boundary

The checker proves executable identity, bytes, constants, control-flow edges,
and first-five content reachability. Human names describe only traced
producers and consumers. Presentation-only interpolation and simultaneous
co-op are preserved intentional modernizations; they must not feed coordinates,
timers, pool state, or RNG back into authoritative simulation.
