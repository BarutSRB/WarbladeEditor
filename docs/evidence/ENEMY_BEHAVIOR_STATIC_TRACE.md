# First-Five Enemy Behavior Static Trace

This document closes the ordinary post-entry attack loop, timer-B role,
state-10 motion, and supplemental state-6 behavior used through level 100. It
supersedes and reconciles the older timer and supplemental-field hypotheses in
`LVD_STATIC_TRACE.md` and `LVD_FIRST_FIVE.md`.

## Evidence identity and confidence

The analyzed `Game/warblade.exe` has SHA-256:

```text
ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef
```

Addresses are 32-bit PE virtual addresses for that executable.

- **Proven** means both the producing assignment and relevant consumer were traced.
- **Supported** means the bounded branch is clear but a complete human gameplay label is not.
- **Evidence-only** means exact fields are retained without invented semantic
  names when no reachable finite-product consumer exists.

## State dispatch

The entity state is the signed word at runtime entity offset `+0xa4`. The main switch is at `0x00606600`, using table `0x00614a10`.

| State | Proven first-five role | Main branch |
| ---: | --- | --- |
| 1 | authored LVD entry path | `0x00607725` |
| 2 | formation tracking and attack-launch gate | `0x00608e4f` |
| 3 | selected global SWD attack path | `0x0060af05` |
| 4 | return/relocation routing | `0x0060cbd4` |
| 6 | supplemental free-moving enemy | `0x0060e830` |
| 10 | level-4 randomized motion | `0x0060dbf8` |

Mode-1 terminal LVD opcode 1 sends ordinary enemies to state 2. Level 4 uses mode 2; terminal LVD opcode 6 sends its enemies to state 10 at `0x00608caf`.

## Retail random helpers

The integer wrapper at `0x005295dd` calls `0x0052f6e0`. For a nonempty range:

```text
RNG_int(min, max) = unsigned_raw_rng % (max - min) + min
```

The result is half-open, `[min,max)`, and retains modulo bias. A zero-width range returns zero.

The float wrapper at `0x00529623` calls `0x0052f800`:

```text
RNG_float(min, max) =
    float32((max - min) * unsigned_raw_rng * 2^-32 + min)
```

Its ideal interval is `[min,max)`, with the executable's float32 return boundary. The shared float-to-int helper `0x00526ae0` jumps to `0x006fc630` and uses `cvttsd2si`: it truncates toward zero, not mathematical floor.

## Timer initialization and kill-driven tightening

The LVD enemy words at `+0x10/+0x14` are timer A initial/step. Words at `+0x18/+0x1c` are timer B initial/step. Initialization is at `0x0056d160`–`0x0056d379`:

```text
timer_A = max(authored_A_initial + difficulty_A_adjustment,
              difficulty_A_floor)
A_step = authored_A_step

if authored_B_initial == 0 and authored_B_step == 0:
    timer_B = 0
else:
    timer_B = max(authored_B_initial + difficulty_B_adjustment,
                  difficulty_B_floor)
B_step = authored_B_step

if authored_B_initial == 3500:
    timer_B = 35000
```

The collision/death pass maintains a local qualifying-destruction count `K`. Its six increment sites are `0x00587ef6`, `0x005881c0`, `0x00588b30`, `0x0058954a`, `0x00589ee3`, and `0x0058b1e9`. When `K != 0`, the loop at `0x0058b8e5` updates every active entity whose state is not 8 and whose timer B is nonzero:

```text
timer_B = max(timer_B - K * B_step, difficulty_B_floor)
timer_A = max(timer_A - K * A_step, difficulty_A_floor)
```

This is not a per-tick decrement and does not multiply by simulation scale. A disabled zero timer B also excludes that entity from both kill-driven reductions.

The authored first-five values are:

| Level | Timer A initial/step | Timer B initial/step |
| ---: | --- | --- |
| 1 | `2400 / 100` | `2400 / 100` |
| 2 | `2400 / 85` | `2400 / 85` |
| 3 | `2400 / 75` | `2400 / 80` |
| 4 | `1500 / 44` | `0 / 20` |
| 5 | `2394 / 85` | `2906 / 105` |

`DIFFICULTY_RULES.md` records the exact per-difficulty adjustments, floors, and resulting first-five spawn values.

## Timer A: projectile-fire denominator

The common eligible draw is:

```text
draw = RNG_float(0, effective_timer_A)
fire when draw < 2 * tick_scale
```

The comparison is strict. State 1 uses timer A directly after its common session/projectile gates and requires entity Y greater than `-10.0` at `0x00607767`–`0x006077bf`. State 2 has no ordinary timer-A firing branch.

States 3, 4, and 10 first call the proximity helper at `0x00605ef0`. With:

```text
shot_x = trunc_toward_zero(entity_x + 13)
d = abs(trunc_toward_zero(player_x) - shot_x)
```

the helper normally returns `A`. If `d < 50` and `(raw_rng & 0x7f) < 10`, let `q = trunc_toward_zero(A / 4)` and return:

| Distance | Effective A |
| --- | --- |
| `d < 10` | `A - 3*q` |
| `10 <= d < 30` | `A - 2*q` |
| `30 <= d < 50` | `A - q` |

State 6 uses timer A directly and does not call this proximity helper.

## State 2: formation and attack launch

The state-2 formation update uses:

```text
x -= ((x - target_x) / 20.0) * tick_scale
y -= ((y - target_y) / 20.0) * tick_scale
```

If `x > logical_width + 150` or `x < -150`, both strict, the relocation branch assigns:

```text
x = RNG_float(0, logical_width)
y = -RNG_float(50, 100)
state = 4
```

The timer-B consumer is at `0x006099e5`–`0x00609a30`:

```text
if timer_B == 0:
    remain in state 2
else if RNG_int(0, timer_B) == 1:
    launch
```

For `timer_B > 1`, the ideal probability is `1/timer_B` per eligible authoritative update, subject to modulo bias. `timer_B == 1` can never launch because `[0,1)` contains only zero.

On launch the entity:

1. adds the current group/platform drift to its position;
2. changes to state 3;
3. draws one SWD runtime index from `[0, loaded_swd_count)`;
4. initializes velocity, acceleration, progress, point index, and return selector from that SWD.

The SWD details and first-five global pool are in `SWD_ATTACK_BEHAVIOR.md`.

The launch branch can recruit nearby eligible state-2 followers. The bounded spatial checks are strict:

```text
16 < follower_center_y - leader_center_y < 60
-60 < follower_center_x - leader_center_x < 60
```

Followers copy the leader's SWD index and initialized motion/progress/return
fields; they do not consume independent SWD-selection draws. The first-five
eligibility checks and otherwise-unreachable second-pass draw are preserved in
the authoritative integration.

### State-2 animation

Entity-slot initialization loops over all 150 slots before ordinary LVD spawning at `0x0056a8f6`. It seeds:

```text
phase = RNG_int(0, 6)
animation_interval = 4.0
animation_countdown = 4.0
direction = RNG_int(0, 2)
animation_step = RNG_float(0.3, 2.0) / 5
```

Ordinary spawn does not reseed these fields, and entering state 2 does not reseed them. In the state-2 stationary branch, when both target deltas compare exactly equal to zero, phase selects:

```text
phase 0 -> source (512,  0)
phase 1 -> source (512, 32)
phase 2 -> source (512, 64)
phase 3 -> source (544,  0)
phase 4 -> source (544, 32)
phase 5 -> source (544, 64)
```

Each update subtracts `tick_scale` from the countdown. Exact zero survives; on
`countdown < 0`, it resets to `4.0` and advances once. Here `direction == 0`
decrements and nonzero direction increments.

The animation metadata flag is runtime entity offset `+0x210`. Ordinary spawn copies it from LVD fixed-table record 0 word 1: loader `0x0055985a`, ordinary copy `0x0056cf8f`. The exact first-five values are:

| Level | Fixed record 0 | Animation flag | Result |
| ---: | --- | ---: | --- |
| 1 | `[1,0,0,0]` | 0 | loop |
| 2 | `[1,0,0,0]` | 0 | loop |
| 3 | `[4,1,0,0]` | 1 | bounce |
| 4 | `[1,0,0,0]` | 0 | loop |
| 5 | `[1,0,0,0]` | 0 | loop |

Flag 0 wraps `0 -> 5` while decrementing and `5 -> 0` while incrementing. Flag nonzero bounces with the executable's asymmetric endpoint handling:

- decrement underflow from phase 0 sets phase 1 and toggles to increment, so phase 0 is not repeated;
- increment overflow from phase 5 sets phase 5 and toggles to decrement, so phase 5 is held for the following interval.

## State 3: SWD attack

The server-owned state-3 fields are:

```text
swd_runtime_index
swd_point_index
swd_progress
position
velocity
acceleration
swd_return_selector
```

The exact fixed-point load, explicit-Euler update order, strict truncated-progress comparison, terminal zero sentinel, and selector branches are documented in `SWD_ATTACK_BEHAVIOR.md`. State 3 also performs the proximity-adjusted timer-A fire test before continuing its path update.

## State 4: return/relocation

State 4 is entered by state-2 relocation and the recovered late-tail subset of
state-3 terminal-selector routes. It performs proximity-adjusted timer-A
firing, uses dedicated horizontal velocity/acceleration, random turns, strict
screen wraps, and downward roaming. Other selector outcomes return directly to
state 2 with their recovered coordinate/flag writes.

## Level 4 state 10

Level 4's mode-2 terminal opcode 6 initializes:

```text
vertical_velocity = 0.0
vertical_acceleration = RNG_float(0.2, 0.4)
horizontal_velocity = 0.0
horizontal_acceleration = RNG_float(-0.1, 0.1)
horizontal_flip_interval = RNG_int(0, 5) + 10
horizontal_flip_countdown = horizontal_flip_interval
state = 10
```

Thus the interval is an integer 10 through 14. The state-10 update at `0x0060e2e7` performs proximity-adjusted timer-A firing, then:

```text
horizontal_flip_countdown -= tick_scale
if horizontal_flip_countdown <= 0:
    horizontal_flip_countdown = horizontal_flip_interval
    horizontal_acceleration = -horizontal_acceleration

x += horizontal_velocity * tick_scale
horizontal_velocity += horizontal_acceleration * tick_scale
y -= vertical_velocity * tick_scale

if y + 32 < viewport_top - 100:
    deactivate

vertical_velocity += vertical_acceleration * tick_scale
vertical_acceleration /= 1 + tick_scale * 0.05
```

`0x00e113d8` is the viewport-top boundary initialized at `0x005a176e`; it is not the logical height. At the normal first-five viewport it is zero, so the top-left-coordinate rule is `y + 32 < -100`. In the remake's center-coordinate contract the equivalent rule is `center_y + 16 < -100`. The order and strict deactivation comparison are significant. Timer B is initialized for level 4 because its authored step is nonzero, but state 10 has no timer-B launch consumer.

State 10 uses the same six 32x32 source cells listed for state 2. It inherits the common pre-spawn phase `RNG_int(0,6)`, 4-tick interval/countdown, and direction `RNG_int(0,2)`. Its local producer interprets direction oppositely from state 2: nonzero decrements, zero increments. It always wraps `0 <-> 5`; the LVD bounce flag is not consulted in this producer.

The title `K A M I K A Z E` supports “kamikaze” as the level label. The equations above, rather than that label, are the authoritative behavior contract.

## Level 3 supplemental record 0

The LVD physically stores five supplemental records, but the spawner loop at `0x0056d468` dispatches indices 0 through 3 only. Record 4 is not reached by this spawner. Level 3 record 0 is:

```text
[1, 1, 12, 1200, 25]
```

Its exact first-five contract is:

| Word | Proven use |
| ---: | --- |
| 0 | spawn count: one entity |
| 1 | selector 1: first LVD bitmap resource, `ALIEN001.bmp` |
| 2 | base health: 12 before the progression modifier |
| 3 | timer-A authored initial: 1200 |
| 4 | timer-A authored step: 25 |

The generic selector-1 spawn initializes:

```text
x = logical_width / 4 + RNG_int(0, logical_width / 2)
y = -110.0
state = 6
heading = RNG_int(0, 5) + 18
x_scale = 1.0
y_scale = 1.0
speed = 1.0
```

At the first-five logical width 800, X is an integer 200 through 599. Heading is 18 through 22. The corresponding exact direction-table values are:

| Heading | dir X | dir Y |
| ---: | ---: | ---: |
| 18 | 0.309017 | 0.951057 |
| 19 | 0.156434 | 0.987688 |
| 20 | 0 | 1 |
| 21 | -0.156435 | 0.987688 |
| 22 | -0.309017 | 0.951057 |

State-6 movement is:

```text
x += x_scale * dir_x[heading] * speed * tick_scale
y += y_scale * dir_y[heading] * speed * tick_scale
```

It wraps both axes with strict tests:

```text
if x > width + 120: x = -120
if x < -120:        x = width + 110
if y > height + 120: y = -120
if y < -120:         y = height + 110
```

The initial steering countdown is `RNG_float(0,200) + 200`, or `[200,400)`.
Heading steering increments/decrements and wraps over 40 table entries,
`0..39`; the first-five screen-edge chooser, strict countdowns, and draw order
are implemented directly from its numeric branches.

Health initialization is:

```text
current_health = maximum_health =
    12 + trunc_toward_zero(supplemental_health_progression_modifier)
base_health_divisor = 12 / 10.0
```

For the first five levels that progression modifier is zero. Timer A uses the normal difficulty adjustment/floor with authored `1200/25`. State 6 also receives generated timer B:

```text
timer_B = max(100 + difficulty_B_adjustment, difficulty_B_floor)
B_step = 10
```

State 6 does not consume timer B as an attack-launch gate. It fires directly from timer A using the strict common draw.

The supplemental animation initializes phase 0, direction 0, source `(0,0)`, and interval/countdown `RNG_int(2,5)`, so the initial value is 2, 3, or 4. LVD fixed-table record 0 supplies maximum phase `word0 - 1 = 3` and bounce flag word 1 = 1. Source X is `trunc_toward_zero(phase) * 64`, source Y is zero. After the initial countdown, the reset value is:

```text
current_health / max(1.0, base_health_divisor)
```

Its direction and endpoint behavior match state 2, but use phases 0 through 3. Because the first direction is decrement and the level-3 flag is bounce, first underflow sets phase 1 and toggles to increment.

## Authoritative integration fields

The server must own and deterministically snapshot these behavior fields:

| State | Required authoritative fields |
| ---: | --- |
| 2 | position, formation target, group/platform drift, timer B, animation phase/interval/countdown/direction/metadata, RNG order |
| 3 | SWD index, point index, progress, return selector, position, velocity, acceleration, timer A, RNG order |
| 4 | position, formation/return route state, timer A, RNG order |
| 6 | position, heading, X/Y scale, speed, steering mode/countdown, health/divisor, timers A/B and steps, animation phase/countdown/direction/max/metadata, RNG order |
| 10 | position, horizontal velocity/acceleration/flip interval/countdown, vertical velocity/acceleration, timer A, animation phase/countdown/direction, RNG order |

Run behavior at the authoritative 60 Hz simulation rate. A high-refresh renderer should interpolate snapshots and derive source rectangles from authoritative phase; it must not advance timers, RNG, paths, or animation from render delta.

For online anti-cheat and replay determinism, clients should submit input only. The server owns RNG state and draw order, state transitions, selected SWD, projectiles, damage/destruction count, timer reductions, and supplemental/state-10 motion. Snapshot or event-log the PRNG state plus a monotonically ordered simulation event sequence.

## Caller/order and evidence boundary

Proven ordering that must be retained:

- common entity-slot animation seeds occur before LVD ordinary spawning;
- state-2 leader SWD selection occurs once, then recruited followers copy it;
- state-10 timer-A fire evaluation precedes its motion block;
- state-6 timer-A fire evaluation follows its movement/wrap block in the traced state branch;
- kill-driven timer reductions occur after the collision/destruction pass and use that pass's local qualifying count.

The numeric state-4 selector branches, cutoff draw, update order, return states,
state-6 steering-choice policy, aimed-shot difficulty travel multiplier, fire
gate, geometry, and pool-full draw behavior are now executable-backed runtime
contracts. Retail
modulo behavior and endpoint rules are preserved where traced; fixed-point
replacement of rare float32 comparison edges is an explicit replay/hash-state
v9 modernization.

Only human prose names for extra follower flags and numeric return-selector
routes remain evidence-only. The runtime intentionally consumes their proven
numeric behavior without assigning speculative directional labels.

## Corrections to earlier evidence

This trace supersedes these early hypotheses:

1. Timer B is the state-2 attack-launch denominator, not a generic timer.
2. Timer steps apply per qualifying destruction count, not per elapsed tick.
3. Supplemental words 2–4 are base health, timer-A initial, and timer-A step.
4. LVD fixed-table record 0 words 0 and 1 produce animation maximum/count behavior for the level-3 supplemental enemy; word 1 also controls ordinary state-2 loop/bounce behavior.
5. The shared numeric conversion helper truncates toward zero.
