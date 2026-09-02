# Hurry-Up Secret Ships Static Trace

This document closes the retail hurry-up system: the per-player deadline, the
spawner and its exact random-draw order, both ship behaviours, their collision
boxes, their death handling, and the found-secret ids they record into the
profile. It is the evidence behind gap `G19`.

`tools/hurry_up_extract.py` regenerates `docs/evidence/hurry_up.json` from the
executable and fails if any pinned instruction byte or constant drifts.

## Evidence identity and confidence

The analyzed `Game/warblade.exe` has SHA-256:

```text
ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef
```

Addresses are 32-bit PE virtual addresses for that executable.

- **Proven** means both the producing assignment and the relevant consumer were traced.
- **Evidence-only** means the exact value is retained without a closed consumer.

Entity fields are given as offsets from the 936-byte entity record whose base is
`0x00849a4c`; the array holds 150 slots per player with a 0x22470-byte player
stride. The behavior state is the dword at `+0xa8` (`0x00849af4`).

## Deadline

`FUN_00552440` arms the deadline and `FUN_00552680` reads it back. Both switch on
the match mode at `0x008f20d8`; mode 2 (Duel) shares the slot-zero pair, and every
other supported mode indexes by the active player.

```text
interval[player] (0x0084898c) = difficulty timed-effect milliseconds (0x008f2090)
deadline[player] (0x00848854) = now (0x00ab27bc) + interval[player]
```

| Difficulty | `0x008f2090` interval | Content field |
| --- | ---: | --- |
| Easy | 50000 ms | `timed_effect_seconds` 50 |
| Normal | 40000 ms | `timed_effect_seconds` 40 |
| Hard | 30000 ms | `timed_effect_seconds` 30 |
| Ace | 20000 ms | `timed_effect_seconds` 20 |

After a hurry-up wave the interval is overwritten with a flat 10000 ms
(`0x0058f048`) and the deadline is pushed to `now + 10000`. The deadline is also
pushed to `now + interval` when the mothership leaves the surface and when it is
destroyed. This is the same difficulty global the timed shop effects use, which
is why the hurry-up cadence tightens with difficulty.

## Spawner

`FUN_0058e350` runs once per frame from the ordinary-level dispatcher at
`0x005b1237`, between the collision/death pass and the motion pass:

```text
FUN_00585840  collision and death dispatcher
FUN_00581250  money-sucker spawner        (state 0xb, not implemented)
FUN_0058e350  hurry-up spawner            (states 9 and 0xc)
FUN_00581990  guard spawner               (state 0x12, not implemented)
FUN_00605fe0  motion dispatcher
```

### Guards

Every guard is evaluated before any random draw, so a suppressed frame consumes
no RNG at all:

| Address | Rule |
| --- | --- |
| `0x0058e386` | `now <= deadline` returns |
| `0x0058e3a2` | the per-player level-complete flag `0x00848928` returns |
| `0x0058e3af` | screen state `0x00a95c20 == 4` returns |
| `0x0058e3bc` | match mode 6 (Time Trial) returns |
| `0x0058e3c9` | screen state `0x00a95c20 == 3` returns |
| `0x0058e3e8` | the 150-slot entity array must have a free slot |

### Random draw order

1. `RngInt(0, 100)` entry-side coin. Below 50 the mothership enters from the
   right at `x = 800` with direction flag 1 and pan `+1.0`; otherwise it enters
   from the left at `x = -288` (the negated sheet width at `0x00d563e8`) with
   direction flag 0 and pan `-1.0`.
2. `RngInt(0, loaded hurry-up clip count)` selects the voice line. Both
   `hurryup1` and `hurryup2` are present in the shipped voice packs, so the draw
   is `RngInt(0, 2)`.
3. `RngInt(128, 672)` once for **each already-visible planet**, re-randomising the
   parallax planet row.
4. `RngFloat(2.0, difficulty special speed maximum)` mothership speed.
5. `RngFloat(2.0, 4.0)` mothership animation interval.
6. Every eighth spawn only, the rare-ship draws listed below.

Between steps 1 and 2 the banner text is written and its deadline set to
`now + 1000` (`0x0058e613`). After step 3 the planet count at `0x007ce91c` grows
by one and is capped at eight; it starts each session at one.

Each ship also opens a looping hum channel on its own entity slot, stopped when
that ship dies or leaves: `mothership` for the mothership (`0x00e116e8`,
`0x00536829`) and `mshiphum` for the money ship (`0x00e116b4`, `0x00536815`).

The spawner tail also decrements the evidence-only global `0x008f202c` by 8 with a
floor of 40.

## Mothership, behavior state 9

| Property | Value | Source |
| --- | --- | --- |
| Sheet | `mothership2.png`, 288x512 | `0x005a361a` |
| Mask sheet | `mothership2_mask.png` | `0x005a3640` |
| Frame | 96x57, 20 frames | `0x0077dc58` / `0x0077dc40` / `0x0077ad58` |
| Frame layout | source x = `(frame / 8) * 96`, source y = `(frame % 8) * 57` | `0x006115xx` |
| Spawn Y | 20.0 | `0x00779bb4` |
| Speed | `RngFloat(2.0, 0x008f2074)` | `0x0058e684` |
| Kill score | 2500 | `0x0077542b` |
| Health | `trunc(endless ordinary additive) + 0x008f206c` | `0x0058e843` |
| Hitbox | top-left, 96 x 57 | `0x0058716e` |

Difficulty bases: health `0x008f206c` is 10/16/20/25 and speed maximum
`0x008f2074` is 3/4/5/6 for easy/normal/hard/ace. Both now ship as
`special_health_base_a` and `special_speed_maximum` in `content/difficulties.json`.

### Motion, `0x00610b67`

The whole handler is gated on the per-player level-complete flag `0x008487ec`.
Each frame it sweeps the planet row: any planet whose X lies behind the
mothership's direction of travel is cleared to zero and emits one debris burst
with its sound. Then:

```text
direction flag 0:  x += speed * scale ;  x > 800 + 70  removes the ship
direction flag 1:  x -= speed * scale ;  x < -70       removes the ship
```

Removal counts as an escaped level object and re-arms the deadline. The frame
countdown decrements by the simulation scale; on underflow it reloads the
animation interval and steps the frame, wrapping `0..19` forward or backward
depending on the animation-direction field.

### Death, `0x0058a67d`

A 96x57 explosion, the rate-limited explosion sound pair, then — in solo, with a
profile attached, outside attract mode — the per-player flag `0x008489ec` is set
and found-secret **3** is recorded. The deadline is pushed to `now + interval`.

## Rare ship (money ship), behavior state 12

Spawned by the same function on every eighth hurry-up wave, tracked by the
per-player counter at `0x00848864`.

| Property | Value | Source |
| --- | --- | --- |
| Sheet | `moneyship.tga`, 128x1280 | `0x005a3d11` |
| Frame | 128x128, 10 frames stacked vertically | `0x0058eedf` |
| Spawn X | `100 + RngInt(0, 300)` | `0x0058eac9` |
| Spawn Y | -110.0 | `0x0077d834` |
| Kill score | 25000 | `0x0077537a` |
| Health | `trunc(endless ordinary additive) + 0x008f207c` | `0x0058ebff` |
| Hitbox | top-left + (14, 14), 100 x 100 | `0x005870d9` / `0x0058710d` |

Difficulty base `0x008f207c` is 75/100/125/150, shipped as
`special_health_base_c`.

Its spawn draws, in order: `RngInt(0, 300)` X, `RngInt(0, 5) + 18` heading,
`RngFloat(0.0, 100.0) + 50.0` turn countdown, `RngInt(0, 2)` animation direction,
`RngFloat(0.8, 3.0)` speed scalar, `RngInt(0, 3) + 2` heading-step interval, and
`RngFloat(0.0, 8.0) + 3.0` heading-step countdown.

### Motion

The ship drifts along the same 40-entry heading circle supplemental state 6 uses
(`0x007d0558` for X, `0x007d05f8` for Y), scaled by its per-axis scale, its speed
scalar, and the simulation scale. It wraps rather than despawning: past
`surface + 120` it reappears at `-120`, and below `-120` it reappears at
`surface + 110`, on both axes.

On turn-countdown underflow the turn mode resets to 2 with a 30.0 countdown, and
then four edge tests may override it with turn mode 1 or 3 and a
`RngFloat(0.0, 160.0) + 40.0` countdown:

| Edge | Condition (top-left coordinates) | Turn mode |
| --- | --- | --- |
| right | `x > 700` and `heading < 20` | 1 when `heading < 10 or heading > 29`, else 3 |
| left | `x < 36` and `heading >= 20` | 3 when `heading < 10 or heading > 29`, else 1 |
| bottom | `y > 180` and `10 <= heading < 30` | 1 when `heading < 20`, else 3 |
| top | `y < 80` and (`heading < 10 or heading > 29`) | 3 when `heading < 20`, else 1 |

Turn mode 3 increments the heading and turn mode 1 decrements it, wrapping
`0..39`, once per heading-step underflow.

The animation countdown reloads to `(health / (spawn health / 5)) / 4`, so the
money ship visibly speeds up as it takes damage, and its frame ping-pongs across
`0..9`.

### Death, `0x0058a38a`

A 128x128 explosion, then — under the same solo/profile/attract guards — the
per-player flag `0x008489f8` is set and found-secret **6** is recorded. The
deadline is only pushed when another state-12 ship is still active: the predicate
at `0x00585770` scans both players for an active state 12 and, when it finds one,
falls through into the mothership death case.

## Found-secret recording

`FUN_00548e10(profile, id)` records a found secret. The id space is `0..29`, the
same space the shop secret draw (`RngInt(0, 30)`) uses. Three guards apply at
both call sites:

```text
0x007d0f80 != -1        a profile is attached
0x008f20d8 == 0         the match is solo
0x00afbbf4 != 0x52972c  the frame hook is not the attract-mode handler
```

## Hit masks

Retail tests the traced rectangle first and then samples the sprite's hit mask,
and both masks ship with the game:

| Ship | File | Bytes | Layout |
| --- | --- | ---: | --- |
| Mothership | `mothership.hma` | 109440 | one column of twenty 96x57 frames, frame-major |
| Money ship | `moneyship.hma` | 163840 | row-major copy of the 128x1280 sheet |

The money ship's mask mirrors its texture exactly, so one rectangle serves both.
The mothership's does not: the texture packs its twenty frames 3 columns by 8
rows while the mask packs them in a single column, so the mask rectangle is
`(0, frame * 57, 96, 57)` while the texture rectangle stays
`((frame / 8) * 96, (frame % 8) * 57, 96, 57)`. Compared against the sheet alpha
at a 127 threshold the two masks agree on 99.8% and 98.4% of their pixels; the
remainder is antialiasing at the sprite edges.

The money ship is the one ship whose traced rectangle is smaller than its frame,
so the rectangle bounds the sample while the mask itself is read across the full
128x128 frame.

## Shared effect pool

`0x00af7ea4` is a 100-slot array with a 140-byte stride, updated by
`FUN_00601cd0` immediately before the motion dispatcher. It is a hazard pool
rather than a decoration: `FUN_005842c0` lets player fire clear an object out of
the air, and an object that reaches a captive fighter or the fighter itself
destroys it. Allocation scans ascending for the first inactive slot, and a full
pool makes the caller emit nothing and consume none of its random draws.

### Kind 9, the mothership's planet debris

The mothership drops exactly one of these on any frame where its sweep clears a
planet. It draws on the rocket sheet in 24x24 frames, enters at the sweeping
ship's top-left plus `(32, 25)`, and starts on heading 17, straight down.

Its spawn draws, in order: `RngInt(0, 3) + 4` animation interval,
`RngInt(0, 3) + 3` animation countdown, `RngInt(0, 5) + 3` steering reload,
`RngInt(0, difficulty lifetime range) + difficulty lifetime base`, a duel-only
`RngInt(0, 2)` owning seat, and
`RngFloat(difficulty speed minimum, difficulty speed maximum)`.

| Difficulty | lifetime base `0x8f2024` | lifetime range `0x8f2028` | speed `0x8f2030`-`0x8f2034` | steering threshold `0x8f2038` |
| --- | ---: | ---: | --- | ---: |
| Easy | 200 | 200 | 2.4-3.2 | 50 |
| Normal | 200 | 225 | 3.1-3.8 | 40 |
| Hard | 210 | 230 | 3.3-4.3 | 30 |
| Ace | 220 | 235 | 3.5-4.8 | 20 |

All five now ship as `debris_lifetime_base`, `debris_lifetime_range`,
`debris_speed_minimum_milli`, `debris_speed_maximum_milli`, and
`debris_steering_threshold` in `content/difficulties.json`. They were previously
carried as evidence-only rows in `DIFFICULTY_RULES.md`.

It travels on the same 32-direction circle the rockets use (`0x007d0454` for X,
`0x007d04d4` for Y) and steers on its own countdown. One draw decides the mode:

```text
RngInt(0, 101 - per-player field 0x00848770 + 1) < difficulty threshold
    -> wander: RngInt(0,100) < 33 turns one step back
               RngInt(0,100) > 66 turns one step forward
    -> otherwise turn one step along the shorter arc toward the fighter,
       breaking an exact tie with RngInt(0,100) < 50
```

The per-player field at `0x00848770` is zeroed by the new-game reset and only
ever set to 25 by one untraced site, so the remake uses the reset value. The
quadrant target headings come from the table
`[0, 0, 0, 0, 0, 0x15, 0xd, 0, 0, 0x1d, 5]`, indexed by a four-bit code built
from the debris/fighter comparison, so only six entries are reachable.

The object also runs an approach beep whose reload is
`distance / 8 + 2`, so a closing object ticks faster.

### Kind 18, the guard ship's beam

Static 64x70 segments on `beam.tga` with no motion and no random draws. The
guard walks a column from `ship_y + 30` down past the surface in 70-pixel steps
and simply stops when the pool runs dry. Each segment lives 5.0 units.

## Level-liveness timestamp

The render-side liveness pass `FUN_00618560` switches on the same `state - 1`
index through the byte map at `0x0061ac3c`
(`[0,1,0,0,2,3,0,0,4,0,5,6,7,9,9,9,9,8]`). States 9 and 12 resolve to their own
qualifying branches (`0x00619859` and `0x0061954b`), so a hurry-up ship alone on
the surface keeps the timestamp fresh and the level does not force-resolve
underneath it. This matters most for the money ship, which never leaves on its
own.

## Level object accounting

Every spawned hurry-up ship raises the per-player level object total at
`0x00848918` by one, so a level cannot complete while one is still on the
surface. `FUN_00555c40` counts a kill and `FUN_005565b0` counts an escape; both
set the level-complete flag once `killed + escaped >= total`.

## Money sucker, behavior state 11

Two further ships share the death dispatcher switch at `0x005887bc` but have
independent spawners and triggers. Both are gap `G20`, and both are now
implemented.

| Property | Value | Source |
| --- | --- | --- |
| Sheet | `moneysucker2.tga`, 128x561 | `0x005817xx` |
| Frame | 128x51, 11 frames stacked vertically | `0x00612196` (`frame * 51`) |
| Spawn X | `800 + 70` entering left, `-70` entering right | `0x00581412` / `0x0058147a` |
| Spawn Y | `200 + RngInt(0, surface height - 450)` | `0x00581524` |
| Speed | `RngFloat(0.5, 1.5)` | `0x005814d2` |
| Health | `0x008f2070 + 2 * trunc(endless ordinary additive)` | `0x005816b7` |
| Hitbox | top-left, 128 x 50 | `0x00581768` / `0x00581785` |

### Spawner, `FUN_00581250`

Dispatched immediately before the hurry-up spawner. Every guard is evaluated in
this order, so a frame that stops early consumes exactly the draws it reached:

| Address | Rule |
| --- | --- |
| `0x00581286` | screen state `0x00a95c20` is 3 or 4 returns |
| `0x005812b1` | cash `0x00848794` at or below 750 returns |
| `0x005812c9` | the per-player level-complete flag returns |
| `0x005812e3` | `weight = cash / 1340 + RngInt(3, 10)`, and `weight <= 0` returns |
| `0x005812fe` | `RngInt(0, 40000) >= weight` returns |
| `0x00581316` | `simulation scale * 7.0 <= RngFloat(0.0, 200.0)` returns |
| `0x00581347` | `now <= 0x00e11b88` returns |
| `0x0058136a` | any live state-11 entity returns |
| `0x00581396` | `0x00e11b88 = now + 120000`, **before** the free-slot scan |

So a richer fighter is hunted harder, and a full entity array still costs the
whole two-minute cooldown.

### Motion, `0x00611801`

`0x849b14` is the shared direction field: mode 0 travels right, mode 1 travels
left, mode 3 climbs off the top. The ship reverses at `surface + 100` and at
`-100` and re-draws its lane from `200 + RngInt(0, 150)` each time, so it
patrols instead of leaving. Mode 3 deactivates the entity below `-100`; no
traced site puts state 11 into mode 3.

While the ship is inside the visible band it drains cash:

```text
guard:  x + 48 > 50  and  x + 48 < surface width - 50
guard:  simulation scale * 10.0 > RngFloat(0.0, 100.0)
victim: the active player, or RngInt(0, 2) in match mode 2
guard:  victim cash > 0, victim not already suckered, direction != 3
draw:   RngInt(0, range), range = 40, then 68 above 50, 88 above 100,
        100 above 200 cash
tier:   draw <= 40 -> bonus 29, 41..67 -> 30, 68..87 -> 31, above 87 -> 32
amount: the matching money pickup value, __alldiv(coin64, 7)
```

The four coin globals are the same ones the money pickups add at `0x0057abd4`,
so the drained amounts are exactly the retail `money_10`, `money_50`,
`money_100`, and `money_200` values: 10, 50, 100, and 200.

### Death

Killing the money sucker raises the special health base B global `0x008f2070`
by 20, so every later money sucker in the match is tougher. It records no found
secret.

## Guard ship, behavior state 18

| Property | Value | Source |
| --- | --- | --- |
| Sheet | `guard.tga`, 128x640 | `0x00581d47` |
| Frame | 128x64, 10 frames stacked vertically | sheet geometry |
| Spawn X | `800 + 70` entering left, `-70` entering right | `0x00581b3b` / `0x00581ba3` |
| Spawn Y | `200 + RngInt(0, surface height - 450)` | `0x00581c64` |
| Speed | `RngFloat(0.3, 1.0) * simulation scale` | `0x00581c10` |
| Health | `0x008f2078 + 10 * trunc(endless ordinary additive)` | `0x00581dec` |
| Hitbox | top-left, 128 x 64 | sheet geometry |

### Spawner, `FUN_00581990`

Dispatched immediately after the hurry-up spawner:

| Address | Rule |
| --- | --- |
| `0x005819dc` | the per-player level-complete flag returns |
| `0x005819e9` | match mode 6 (Time Trial) returns |
| `0x005819ff` | level `0x008487bc` at or below 15 returns |
| `0x00581a0c` | screen state `0x00a95c20` is 3 or 4 returns |
| `0x00581a2f` | fewer than 10 levels since `0x008f20a8` returns |
| `0x00581a45` | `simulation scale * 20.0 <= RngFloat(0.0, 60000.0)` returns |
| `0x00581a76` | `RngInt(0, 20000) <= 19500` returns |
| `0x00581aa2` | any live state-18 entity returns |
| `0x00581bb9` | `0x008f20a8 = level`, recording the level it appeared on |

### Motion, `0x006123c1`

The guard patrols like the money sucker but leaves at either edge rather than
reversing, and it opens a firing window at random:

```text
RngInt(0, 1000) < 5      -> window 0x00e113f4 = RngInt(50, 150)
window > 0               -> window -= 1
                            RngInt(0, 99) < 10 -> walk one beam column
window >= 1              -> the whole movement block is skipped
```

The column starts at `ship_y + 30`, steps 70 pixels at a time, and stops once it
passes the bottom of the surface or the effect pool runs dry. Each segment is a
kind-18 pool object at `ship_x + 64 - 4`, 64x70, lifetime 5.0 in pool field
`+0x04`, expiring below 1.0 at `0x00602c11`. The window global is not per-entity,
so a guard that leaves mid-window hands the remainder to the next one.

### Death

Killing the guard raises the special health base D global `0x008f2078` by 250.
It records no found secret.

Both health bases now ship as `special_health_base_b` and `special_health_base_d`
in `content/difficulties.json` (v3 to v4).

## Remake deviations

- Retail leaves the mothership's animation frame, countdown, and direction as
  whatever the reused entity slot held; the remake initialises all three to the
  fresh-level values (frame 0, forward, a full interval). The values agree
  whenever the slot has not been used earlier in the level.
- The remake additionally suppresses all three spawners on the mode-3 bonus
  level and the mode-4 big-boss level. Both run their own dispatchers and their
  own completion accounting, and a secret ship added to their object totals
  would have no way to leave them.
- Retail derives the money sucker's sheet offset from a raw frame counter with
  no visible wrap; the remake wraps at each sheet's own frame count so the
  source rectangle and the hit mask stay inside the loaded image.
- Retail folds the simulation scale into the guard's stored speed at spawn time
  and adds it unscaled every frame. The remake keeps the raw draw and applies
  the scale per frame, which is the same product under its fixed timestep.
- Retail's money-sucker cooldown compares against a running wall clock that is
  never zero; the remake's clock starts at zero, so the very first frame of a
  match is suppressed where retail's would not be.
- Retail gates both motion handlers on the shop FREEZE timer at `0x008487ec`,
  which is the same gate the ordinary states use; the remake reuses its existing
  freeze check for all of them.
- The debris spawn's optional trail block is gated on `0x00af7870`, a graphics
  setting, so retail's own stream through that block depends on a user option.
  The remake models only the unconditional draws and treats that as its
  canonical stream.
