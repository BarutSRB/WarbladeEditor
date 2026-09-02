# Warblade 1.34 player weapon and runtime trace

This trace closes implementation-critical player weapon rules that were still
ambiguous after the static content-table extraction. It is derived from direct
data and control-flow in the retail `warblade.exe`, not from screenshots or
timed observation.

The matching executable has SHA-256:

`ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`

The machine-readable result is
[`weapon_runtime.json`](weapon_runtime.json). Regenerate and verify it with:

```sh
python3 tools/weapon_runtime_extract.py
python3 tools/weapon_runtime_test.py
python3 tools/weapon_runtime_extract.py --check
```

## Confidence labels

- **Proven** means direct executable data/control-flow or an explicit statement
  in the bundled 1.34 manual.
- **Supported** means strong bounded evidence exists, but not every caller or
  ordering boundary was closed.
- **Evidence-only** means the trace retains a raw boundary without assigning a
  rule when no finite-product consumer needs one.

## Projectile capacity

**Proven**

The per-player capacity is the word at `0x00848836 + player * 0x4d8`. The
per-player live projectile-object count is the adjacent word at
`0x00848838 + player * 0x4d8`.

The retail rule is object-counting, not trigger-pull or root-volley counting:

1. `0x005e0b71-0x005e0b7b` compares the live object count with capacity once,
   before asking the recursive spawner to create the volley.
2. `0x005df878-0x005df88b` increments the live count on every successful object
   allocation.
3. `0x005df8db-0x005df8df` stores that object's counter contribution.
4. Both child calls at `0x005dfc6a-0x005dfcb2` and
   `0x005dfcc4-0x005dfd0c` inherit the same contribution.

Normal player fire passes contribution `1`, so every root and every recursive
child consumes one capacity unit. Alternate mirrored/self-play calls pass
contribution `0`, so those objects do not affect the player's live count.

The pre-volley gate has an intentional overshoot consequence. If the live count
is four and capacity is five, a legal three-object volley can leave the live
count at seven. Further volleys are blocked until the count falls below five.
Do not truncate a legal recursive volley to the remaining nominal capacity.

All immediate recursive child calls receive the original fire X/Y arguments.
Each prototype's offsets and randomization are independently relative to that
origin; child offsets are not recursively accumulated.

The bundled manual establishes starting capacity `5`. Extra Bullet caps it at
`50` (`0x00563046-0x0056307f`). On player death, a capacity above five loses
exactly one, with a floor of five (`0x00571a0e-0x00571a37`).

## Prototype movement encodings

**Proven**

The secondary-velocity table is at `0x007cd688`. The spawner at `0x005df6e0`
gives two numeric ranges special meanings:

- For `160 < secondary < 170`, let `spread = secondary - 160`.
  `vx = random_float(0, spread) - spread / 2`.
- For `secondary > 170`, let `spread = secondary - 170`.
  Apply one spawn displacement
  `x += (random_float(0, spread) - spread / 2) * tick_scale`, then set `vx = 0`.

The first-five weapon prototypes decode as:

| Weapon | Prototype | Role | Raw secondary | Exact arithmetic range |
|---|---:|---|---:|---:|
| War.I.Plasma | 19 | root | 165 | `vx` from -2.5 to +2.5 |
| War.I.Plasma | 20 | child | 163 | `vx` from -1.5 to +1.5 |
| War.I.Plasma | 21 | child | 163 | `vx` from -1.5 to +1.5 |
| Fireballs | 25 | root | 200 | spawn-X jitter from -15 to +15 |
| Fireballs | 26 | child | 200 | spawn-X jitter from -15 to +15 |
| Fireballs | 30 | child | 190 | spawn-X jitter from -10 to +10 |
| Fireballs | 31 | grandchild | 190 | spawn-X jitter from -10 to +10 |

The generic projectile update multiplies both stored X and Y velocity by
`tick_scale` on every update (`0x006209bd-0x00620a14`). Thus the War.I.Plasma
random X velocity is time-scaled every update. Fireballs instead receive the
one-time, time-scaled spawn-X displacement and then have zero horizontal
velocity. Their normal vertical velocity still uses the generic time scaling.

The float helper consumes one unsigned word in `0..0xffffffff`, multiplies by
exact `2^-32`, and stores the result through float32. The mathematical value is
below the upper argument for the maximum word, but the final float32 store
rounds the spans used here to that argument. Consequently these weapon ranges
can return both displayed endpoints: `[-2.5,+2.5]`, `[-1.5,+1.5]`,
`[-15,+15]`, and `[-10,+10]`. Maximum-word vectors pin this boundary and its
single-draw accounting.

## Laser

**Proven**

Laser weapon ID `7` starts with prototype/frame `22`, damage `10`, width `16`,
height `100`, and zero X/Y velocity. Frames `22`, `23`, `24`, and `50` all have
the persistent-projectile flag. Their next-frame chain is:

`22 -> 23 -> 24 -> 50 -> -1`

During nonzero gameplay state, the persistent frame advances once per
projectile-update call (`0x00620974-0x00620b21`). Reaching `-1` deactivates the
object. Preserve those four transitions rather than replacing the beam with a
one-tick projectile or inventing a wall-clock duration.

### Spawn and collision geometry

The player X/Y passed into the projectile spawner are the retail ship's stored
sprite-origin coordinates. Generic projectile spawn geometry is:

```text
projectile_left = player_x + 20 - projectile_width / 2 - prototype_x_offset
projectile_top  = player_y - prototype_y_offset
```

Laser prototype `22` has X offset `0` and Y offset `86`. Therefore:

```text
laser_left       = retail_player_x + 12
laser_visual_top = retail_player_y - 86
```

The laser collision rectangle does not use its visual top or height.
`0x00585945-0x00585971` overrides it to:

```text
left   = stored_projectile_x
right  = stored_projectile_x + 16
top    = 0
bottom = owning_player_current_retail_y
```

The horizontal position is latched at fire time and does not follow later
player X movement. The lower collision boundary is different: the collision
routine reads the owning player's live retail Y on every pass, so vertical
player movement changes the column's bottom while it is alive.

For a remake whose ship transform is the sprite center, convert back to the
retail sprite origin before applying that bottom rule. For example, if center Y
`564` represents retail origin Y `550`, the laser collision bottom is `550`,
not `564`.

### Damage behavior

For the ordinary-enemy path at `0x00587465-0x00587487`, a confirmed collision
subtracts the projectile's current stored damage. The persistent flag then
halves that stored damage at `0x005874d1-0x005874ef`. Consecutive collisions in
enemy-array order therefore use:

`10, 5, 2.5, 1.25, ...`

The beam is not removed on its first hit; its frame chain governs lifetime.

**Supported:** at least one special-enemy family uses a separate
divide-by-ten/minimum-one damage path. The ordinary-enemy rule above is the
bounded first-five integration contract.

### The Laser cannot damage a state-13 boss

The same collision routine tests a state-13 boss against the *midpoint* of the
projectile rectangle, not the rectangle itself:

```text
0x00585a65  local_x = (left + right) / 2 - (boss_x - 128)
0x00585aa3  local_y = (top + bottom) / 2 - boss_y
0x00585b74  hit requires 16 < local_x < 240 and 16 < local_y < 112
```

For a Laser the rectangle is the whole column from `top = 0` to the fighter, so
its midpoint sits at roughly half the surface height and never lands inside the
boss's local 16..112 band. The single override that could rescue it is:

```text
0x00585af7  persistent-projectile flag set, and
0x00585b15  boss_y > [0x00778dd8] (0.0), and
0x00585b54  boss_y < [0x007d32fc] (600)
            -> local_y = 60
```

Both constants are read from the shipped image. Every big-boss path hangs above
that band — the level-25 encounter enters at origin Y `-189` and peaks at
`-55.6` — so `boss_y > 0.0` is never satisfied and a fighter holding the Laser
does zero damage to the boss for the whole encounter.

This is retail behaviour, reproduced exactly; it is not a remake defect and
must not be "fixed". It is called out here because it is easy to mistake for
one: the beam visibly covers the boss and still scores nothing. The bounded
campaign driver in `tests/sim/test_campaign_through_thirty.gd` spends a homing
rocket instead when it reaches a boss holding the Laser, which is the only
reason a route whose pickups leave it on weapon 7 can finish.

The authoritative dispatcher resolves player-projectile collisions before
advancing projectiles. A newly fired Laser therefore waits until the next
authoritative tick, then receives one collision pass at each live frame 22,
23, 24, and 50 before the update advances to `-1`. Each pass scans ordinary
enemies in stable array order; a confirmed hit halves damage and does not stop
the Laser scan. This is four collision opportunities per overlapping enemy,
not a wall-clock approximation.

## Manual fire, Auto Fire, and Super Auto Fire

**Proven**

The game does not impose a universal 100 ms weapon cooldown.

Manual fire is edge-latched through `0x00848994 + player * 0x4d8`
(`0x005ec5fb-0x005ec75f`). An armed press fires immediately, a held press
disarms the edge, and release rearms it.

Auto Fire uses:

- enable flag `0x00848768 + player * 0x4d8`
- next absolute deadline `0x0084881c + player * 0x4d8`
- repeat delay `0x00848820 + player * 0x4d8`

The default delay is `100` ms. Super Auto Fire sets the delay to `25` ms and
also enables Auto Fire (`0x00561eee-0x00561f3b`).

The exact repeat condition is strict:

```text
if current_ms > next_deadline:
    fire()
    next_deadline = current_ms + delay_ms
```

The timer is a millisecond QPC conversion with a `timeGetTime` fallback
(`0x00628cd0-0x00628d82`).

Gameplay start/resume seeds the deadline to the current time. The Auto Fire
bonus path also seeds the deadline before enabling. The shop Auto Fire purchase
only enables the flag and leaves the existing deadline untouched.

The manual-edge path does not reschedule the Auto deadline and then falls
through to the Auto path. Consequently, if Auto Fire is enabled and its old
deadline is already expired, one player update can emit the immediate
manual-edge volley and a second Auto volley. If the deadline is not expired,
that update emits only the manual-edge volley.

## Fighter banking

**Proven**

The per-player banking phase starts at `5.0` and changes by `0.5` per player
update.

- Left subtracts `0.5` and clamps negative results to `0`.
- Right adds `0.5`. An aligned phase can reach `10.5`; the next step reaches
  threshold `11` and resets to `10`.
- With no horizontal input, phase moves toward neutral `5` by `0.5` without
  overshooting.
- Rendering truncates the phase toward zero and takes `% 11`.

The raw right endpoint therefore alternates between `10` and `10.5` under
sustained input, while both values render frame `10`. This is a harmless retail
state quirk but should not be mistaken for a smooth clamp at raw `10`.

## Extra Speed and Less Speed

**Proven**

The bootstrap speed pair `4.0 / 0.75` is not the live Normal rule. Difficulty
selection overwrites the base and increment before player initialization:

| Difficulty | Base | Increment | Stored shop ceiling |
|---|---:|---:|---:|
| Easy | 4.199999809265137 | 0.800000011920929 | 17.0 |
| Normal | 4.0 | 0.699999988079071 | 15.199999809265137 |
| Hard | 3.5 | 0.6000000238418579 | 13.100000381469727 |
| Ace | 3.0 | 0.5 | 11.0 |

Extra Speed computes `base + increment * 16`. If current stored speed is below
that value, it adds one live difficulty increment and clamps any overshoot to
the ceiling (`0x005630d3-0x005631be`).

Less Speed checks current speed against the live difficulty base and subtracts
one live increment only when above it (`0x00562f35-0x00562fc1`). There is no
post-subtraction clamp; valid retail upgrade-lattice values land exactly on the
base.

Movement consumes stored speed as:

```text
movement_delta = min(stored_speed * normal_movement_scale, 14) * tick_scale
```

The cap is applied before `tick_scale`, so the stored shop ceiling and the
per-update movement cap are separate concepts.

## Extra Life

**Proven**

The per-player field is `0x00848750 + player * 0x4d8`. Its default record uses
base `26`, step `4`, initial offset `12`, and maximum offset `20`.

This encodes:

- three total starting fighters
- one additional total fighter per purchase
- five total fighters maximum

Death subtracts one encoded step first and respawns only while the result is
above the base (`0x005ecfbe-0x005ed084`). Thus the third death from the initial
three-fighter state is terminal. The manual's sidebar description is
consistent: one active fighter plus two displayed reserves.

## Armour

**Proven for alien-projectile hits**

The per-player armour field is `0x008487e8 + player * 0x4d8`. Its default
record uses base `123`, step `5`, and maximum offset `10`, encoding:

- zero starting charges
- one charge per purchase
- two charges maximum

The alien-projectile collision path begins at `0x005842c0`. With at least one
charge, the protected branch avoids player death, consumes one encoded armour
step, and sets:

```text
shield_expiry = now_ms + (duration_field / 5) * 1000
```

The default duration field is `20`, yielding `4000` ms. Alien-projectile
collision work is skipped while the shield-expiry field is nonzero.

**Supported:** several other damage routines read the shield timer, but this
bounded trace does not claim that every non-projectile hazard consumes Armour
identically.
