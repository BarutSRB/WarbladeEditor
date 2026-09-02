# Retail Difficulty Rules for Levels 1–100

This document closes the reachable Easy, Normal, Hard, and Ace rules for the
finite campaign. It comes from bounded static analysis of retail
`warblade.exe`, not screenshot matching. The machine-readable extraction is in
`difficulty_rules.json`, and `tools/difficulty_rules_test.py` pins the
executable bytes used by each conclusion.

## Evidence identity and confidence

The analyzed executable has SHA-256:

```text
ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef
```

Addresses are 32-bit PE virtual addresses for that image.

- **Proven** means the retail assignment and a complete relevant gameplay consumer were both traced.
- **Supported** means a bounded consumer supports the neutral label, but does
  not justify a narrower human semantic name.
- **Evidence-only** preserves the exact value when no reachable finite-product
  consumer exists.

## Executive result

The first-five-level rules are not conventional health/speed multipliers:

- Every ordinary authored enemy in levels 1–5 has exactly 1 health on every
  difficulty. Remake co-op health scaling is an explicit modernization, not a
  retail difficulty rule.
- Easy and Normal use simulation scale 1. Hard uses float32 bits `0x3f955555` (approximately 7/6); Ace uses `0x3faaaaab` (approximately 4/3).
- That scale affects enemy activation, path position and velocity, path progress, player movement, and alien projectile velocity. It is a simulation pace, not a display-frame-rate setting.
- Ordinary alien firing uses the authored timer-A denominator. Difficulty adds `+400`, `+200`, `-50`, or `-200`, applies floors `300`, `200`, `190`, or `180`, and tests a strict random condition each eligible update.
- Timer A and B tighten when qualifying enemies are destroyed. They are not decremented every simulation tick.
- The retail initial value 3 means three total fighters: one active and two reserve icons. Retail game over occurs on the third death.
- Each difficulty selects its own retail border asset.
- The live falling-bonus branch uses difficulty denominators 18/28/38/48. No
  difficulty score or cash multiplier has a reachable finite-campaign
  consumer; those values remain evidence-only rather than fabricated rules.

## Difficulty enum

The difficulty ID is stored at `0x00af7940`. The switch at `0x0056877e` uses the jump table at `0x00568c6c`.

| ID | Difficulty | Menu evidence | Init case |
| ---: | --- | --- | --- |
| 0 | Easy | `0x00591b07` | `0x005687a3` |
| 1 | Normal | `0x00591b2a` | `0x005688d2` |
| 2 | Hard | `0x00591b4d` | `0x00568a01` |
| 3 | Ace | `0x00591b70` | `0x00568b34` |

## High-impact difficulty values

The complete initialization function is `0x00568760`–`0x00568c68`.

| Proven rule | Global | Easy | Normal | Hard | Ace |
| --- | --- | ---: | ---: | ---: | ---: |
| simulation scale | `0x7d1520` | 1 | 1 | 1.1666666269 | 1.3333333731 |
| timer-A initial adjustment | `0x8f20b8` | +400 | +200 | -50 | -200 |
| timer-A floor | `0x8f20b0` | 300 | 200 | 190 | 180 |
| timer-B initial adjustment | `0x8f20b4` | +400 | +200 | -50 | -200 |
| timer-B floor | `0x8f20ac` | 300 | 200 | 190 | 180 |
| ordinary alien projectile base speed | `0x8f2060` | 3.5 | 4.3000001907 | 5 | 5.5 |
| player base lateral speed | `0x8f2080` | 4.1999998093 | 4 | 3.5 | 3 |
| player speed-upgrade increment | `0x8f2084` | 0.8000000119 | 0.6999999881 | 0.6000000238 | 0.5 |
| timed-effect duration, milliseconds | `0x8f2090` | 50000 | 40000 | 30000 | 20000 |
| special-enemy health base A | `0x8f206c` | 10 | 16 | 20 | 25 |
| special-enemy health base B | `0x8f2070` | 300 | 350 | 450 | 600 |
| special-enemy health base C | `0x8f207c` | 75 | 100 | 125 | 150 |
| special-enemy health base D | `0x8f2078` | 1500 | 1750 | 2000 | 2500 |

Critical float32 encodings:

| Value | Bits |
| --- | --- |
| Hard simulation scale | `0x3f955555` |
| Ace simulation scale | `0x3faaaaab` |
| Normal projectile base 4.3 | `0x4089999a` |

The exact remaining assignments are retained. Consumer-backed rows use neutral
labels where a narrower meaning is not proven; rows with no finite-product
consumer are explicitly evidence-only:

| Global / current classification | Easy | Normal | Hard | Ace |
| --- | ---: | ---: | ---: | ---: |
| `0x8f2058`, evidence-only | 2 | 3 | 3 | 2 |
| `0x8f20a4`, proven Extra Time floor | 15 | 10 | 5 | 5 |
| `0x8f2024`, evidence-only | 200 | 200 | 210 | 220 |
| `0x8f2028`, evidence-only | 200 | 225 | 230 | 235 |
| `0x8f202c`, evidence-only | 170 | 130 | 115 | 95 |
| `0x8f2030`, neutral consumer-backed range A | 2.4 | 3.1 | 3.3 | 3.5 |
| `0x8f2034`, neutral consumer-backed range B | 3.2 | 3.8 | 4.3 | 4.8 |
| `0x8f2038`, neutral consumer-backed threshold | 50 | 40 | 30 | 20 |
| `0x8f2094`, proven Meteor parameter | 0.0014 | 0.00145 | 0.0015 | 0.0017 |
| `0x8f2098`, proven Meteor parameter | 12090 | 14000 | 15540 | 17000 |
| `0x8f209c`, proven Meteor threshold | 7 | 6 | 5 | 4 |
| `0x8f203c`, proven falling-bonus drop denominator | 18 | 28 | 38 | 48 |
| `0x8f2074`, evidence-only | 3 | 4 | 5 | 6 |
| `0x8f2020`, proven follower threshold | 4 | 6 | 10 | 15 |
| `0x8f2068`, proven state-6 aimed-shot travel multiplier | 3 | 2.2 | 2 | 1.8 |

The JSON contains the unrounded float32 values, source VAs, and bit patterns for every row.

## Health in levels 1–5

Enemy spawn at `0x0056d094` converts the additive float at `0x00e113f8`, adds it to LVD base health, and copies the result into current and maximum health.

`0x00e113f8` is zeroed at `0x0053818a`. None of the four difficulty cases writes it. Its later progression increment at `0x00538375` requires:

```text
level > 5
(level - 1) mod 100 == 0
```

Therefore levels 1–5 use exact authored health on all four difficulties. Every active ordinary enemy record in those five LVD files has base health 1.

This does not say all later special enemies have equal health. Four separate special-enemy health bases are difficulty-dependent, as shown above.

## Timer initialization and kill-driven tightening

Spawn logic is `0x0056d160`–`0x0056d2f7`:

```text
timer_A = max(authored_A_initial + difficulty_A_adjustment, difficulty_A_floor)

if authored_B_initial == 0 and authored_B_step == 0:
    timer_B = 0
else:
    timer_B = max(authored_B_initial + difficulty_B_adjustment, difficulty_B_floor)
```

The collision/death function beginning at `0x00585840` counts qualifying enemy destructions in local `-0x114`. Its increments are at `0x00587ef6`, `0x005881c0`, `0x00588b30`, `0x0058954a`, `0x00589ee3`, and `0x0058b1e9`.

At `0x0058b900`–`0x0058bab9`, the function updates each remaining active enemy whose state is not 8 and whose timer B is nonzero:

```text
timer_A = max(timer_A - authored_A_step * kills_in_this_pass, A_floor)
timer_B = max(timer_B - authored_B_step * kills_in_this_pass, B_floor)
```

Across passes, this is equivalent to using cumulative qualifying kills `K`, subject to the same active/state eligibility. It is not `step * tick_scale`.

### Exact first-five contracts

Each level has one unique health/timer tuple across its active authored enemies.

| Level | Authored A `initial/step` | Authored B `initial/step` | Spawn A Easy / Normal / Hard / Ace | Spawn B Easy / Normal / Hard / Ace |
| ---: | --- | --- | --- | --- |
| 1 | 2400 / 100 | 2400 / 100 | 2800 / 2600 / 2350 / 2200 | 2800 / 2600 / 2350 / 2200 |
| 2 | 2400 / 85 | 2400 / 85 | 2800 / 2600 / 2350 / 2200 | 2800 / 2600 / 2350 / 2200 |
| 3 | 2400 / 75 | 2400 / 80 | 2800 / 2600 / 2350 / 2200 | 2800 / 2600 / 2350 / 2200 |
| 4 | 1500 / 44 | 0 / 20 | 1900 / 1700 / 1450 / 1300 | 400 / 200 / 190 / 180 |
| 5 | 2394 / 85 | 2906 / 105 | 2794 / 2594 / 2344 / 2194 | 3306 / 3106 / 2856 / 2706 |

For example, level 1 Ace timer A after qualifying kills is:

```text
max(2200 - 100 * K, 180)
```

## Exact timer-A firing condition

The ordinary alien firing branch is `0x00607725`–`0x006077cc`.

Before firing, the traced branch requires:

1. Player/session field `0x8487ec` equals zero.
2. Global `0xe1146c` equals zero.
3. Enemy Y is greater than -10.
4. Level mode global `0xa95c20` is not 3.
5. A projectile slot is available.

It converts runtime timer A at `0x00849bcc` to float and calls the random-range helper at `0x0052f800`. That helper:

1. obtains an unsigned 32-bit PRNG result `U32`;
2. multiplies by the exact double `2^-32` at `0x00778e90`;
3. multiplies by timer A;
4. rounds the returned result to float32.

With a zero lower bound:

```text
r = float32(U32 * timer_A * 2^-32)
```

The compare at `0x006077ac` loads simulation scale, multiplies it by the exact double 2.0 at `0x00779b40`, and fires only on:

```text
r < 2 * simulation_scale
```

Equality does not fire. The idealized per-eligible-enemy, per-update probability is:

```text
min(1, 2 * simulation_scale / timer_A)
```

The exact retail boundary includes float32 rounding of `r`. Other eligibility gates and lack of a free projectile slot can lengthen the observed interval.

## What the simulation scale actually changes

Ordinary setup copies the selected difficulty scale from `0x007d1520` to the authoritative runtime value at `0x00e11274` at `0x005a086a`.

The retail update target is initialized to 60 at `0x005a0830`.

Complete consumers prove:

- `0x00607f2e`–`0x00607fc4`: enemy activation countdown subtracts scale.
- `0x00613a21`–`0x00613bbe`: position adds velocity times scale, velocity adds acceleration times scale, and path progress adds scale.
- `0x005eb6cd`–`0x005eb6e8` and sibling branches: player movement delta is multiplied by scale.
- `0x006079fc`–`0x00607a34`: alien projectile vertical velocity is multiplied by scale.

Default ordinary projectile results after the final float32 store are:

| Difficulty | Base bits | Scale bits | Vertical velocity bits | Value |
| --- | --- | --- | --- | ---: |
| Easy | `0x40600000` | `0x3f800000` | `0x40600000` | 3.5 |
| Normal | `0x4089999a` | `0x3f800000` | `0x4089999a` | 4.3000001907 |
| Hard | `0x40a00000` | `0x3f955555` | `0x40baaaaa` | 5.8333330154 |
| Ace | `0x40b00000` | `0x3faaaaab` | `0x40eaaaab` | 7.3333334923 |

An unrelated option byte at `0x8f201e` adds a 1.25 multiplier. It is not the difficulty selector.

The base player speed also varies by difficulty. With no upgrade and the ordinary movement scale of 1, the final per-update lateral deltas are approximately 4.2, 4.0, 4.083333, and 4.0 for Easy through Ace. Hard and Ace do not simply make only enemies faster; the whole traced simulation boundary advances faster.

For high-refresh rendering, keep an authoritative fixed simulation clock and interpolate presentation. Driving this scale from a 120 Hz or 240 Hz display loop would incorrectly multiply gameplay speed.

## Starting fighters, death, and respawn

The default ship record at `0x007d1524` contains:

```text
base = 26
step = 4
initial_offset = 12
maximum_offset = 20
```

Initialization at `0x00623aad`–`0x00623ade` stores:

```text
raw = base + initial_offset = 38
encoded_count = (38 - 26) / 4 = 3
```

The HUD at `0x005d5e29`–`0x005d5e91` computes the same encoded count and hides one icon for the active current-player fighter. It initially draws two reserve icons.

Death branches such as `0x005ecfbe`–`0x005ecfeb` subtract one step before the terminal decision. `0x005ed058`–`0x005ed084` respawns only when the decremented raw value remains greater than base:

| Death | Raw after decrement | Fighters remaining | Respawn |
| ---: | ---: | ---: | --- |
| 1 | 34 | 2 | yes |
| 2 | 30 | 1 | yes |
| 3 | 26 | 0 | no |

The initial 3 is therefore three total fighters, not three reserves. The maximum encoded value 5 means five total fighters. This is difficulty-independent and agrees with the manual's one-active-plus-two-sidebar description.

The encoded field is per player session at `0x00848750 + session * 0x4d8`. Retail two-player modes therefore retain separate fighter counts. A shared fighter pool for the new simultaneous co-op mode is a deliberate remake rule, not recovered retail behavior.

The remake represents this as three total fighters (or equivalently two initial
reserves) for independent retail sessions. Simultaneous co-op deliberately
shares its remake-owned total-fighter pool.

## Difficulty borders

The retail loader at `0x005a2d32`–`0x005a2db6` loads four distinct textures. Rendering selects them from difficulty ID at `0x0061f66c`–`0x0061fb08`.

| Difficulty | Asset | Texture handle |
| --- | --- | --- |
| Easy | `border_easy.jpg` | `0x00e11100` |
| Normal | `border.jpg` | `0x00e11104` |
| Hard | `border_hard.jpg` | `0x00e11108` |
| Ace | `border_ace.jpg` | `0x00e1110c` |

All four files already exist under `assets/original/textures/ui/`.

## Score and cash boundary

Player score is the 64-bit value at `0x00848760`/`0x00848764`. Player cash is at `0x00848794`.

The ordinary-alien award path at `0x0058663a`–`0x0058671b` reads the alien's award fields at `0x00849bb8`/`0x00849bbc` and adds the result to player score. That bounded path contains no direct reference to:

- the difficulty selector `0x00af7940`; or
- any of the 28 globals written by the full difficulty initialization switch.

This supports using the authored ordinary-alien score award without a difficulty multiplier. It does not prove that every bonus, boss, pickup, or timed multiplier is difficulty-independent.

The falling-bonus selection branch consumes `0x8f203c` as the exact
difficulty-specific denominator: Easy 18, Normal 28, Hard 38, and Ace 48. The
runtime and deterministic tests use those four values. No reachable
finite-campaign consumer for a difficulty cash multiplier is proven, so cash
scaling remains evidence-only and the product applies no fabricated multiplier.

## Deterministic server implementation

For bit-exact retail compatibility:

- ingest the original float32 constants by bit pattern;
- reproduce the random helper's float32 result rounding;
- preserve the strict `<` comparison.

For a modern authoritative server, deterministic integer arithmetic is preferable:

- represent scales as sixths: Easy `6/6`, Normal `6/6`, Hard `7/6`, Ace `8/6`;
- store activation countdown and path progress in sixth-tick units;
- with deterministic unsigned `U32`, test firing using:

```text
U32 * timer_A * 3 < 2^32 * scale_numerator
```

where `scale_numerator` is 6, 6, 7, or 8.

The projectile bases `7/2`, `43/10`, `5`, and `11/2`, combined with those scales, can use denominator 60:

| Difficulty | Speed numerator / 60 |
| --- | ---: |
| Easy | 210 / 60 |
| Normal | 258 / 60 |
| Hard | 350 / 60 |
| Ace | 440 / 60 |

This rational model is an intentional deterministic modernization. Replay and
hash-state v9 version its rare float32 boundary differences explicitly.

## Corrections to earlier evidence

Deeper consumer tracing supersedes three early statements in earlier evidence files:

1. `0x00e11274` is difficulty-controlled on Hard and Ace; it is not always 1.0 during ordinary gameplay.
2. `0x0058b9a4`–`0x0058bab9` applies timer steps per qualifying kill count, not per tick scale.
3. The encoded starting-fighter value 3 includes the active fighter; the third death is terminal.

The older documents are reconciled to reference this authority while retaining
their address-level evidence.

## Reproduction

Generate or verify the machine-readable evidence:

```sh
python3 tools/difficulty_rules.py
python3 tools/difficulty_rules.py --check
```

Run the targeted extraction tests:

```sh
python3 tools/difficulty_rules_test.py
```

The tests pin the executable hash, enum jump table, all 28 case assignments, critical float bits, first-five timer transforms, kill-driven timer update, RNG compare, scale consumers, border mapping, and three-death fighter lifecycle.
