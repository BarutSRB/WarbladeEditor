# Warblade Sprite Atlas and Hit-Mask Trace

This document records all 100 campaign-level sprite rectangles recovered from the retail executable and the copied original assets. The committed machine-readable result is `content/sprite_frames.json`; `tools/sprite_atlas_extract.py` regenerates it without screenshots, visual guessing, or live play.

## Reproduce

The extractor verifies the retail executable SHA-256 before reading any table, parses its PE sections, validates every referenced TGA/HMA pair, decodes all 100 LVD files, and emits deterministic JSON.

```sh
python3 tools/sprite_atlas_extract.py \
  --exe Game/warblade.exe \
  --asset-root assets/original/textures \
  --level-root assets/original/levels \
  --output content/sprite_frames.json
python3 tools/sprite_atlas_test.py
```

The required executable SHA-256 is:

`ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`

All addresses below are 32-bit virtual addresses at the executable's preferred image base `0x00400000`.

## Confidence vocabulary

- **Proven** means exact source bytes are connected to a traced producer and/or renderer consumer.
- **Supported** means the structure and rectangles are strongly constrained, but a semantic name or dynamically populated bound remains open.
- **Evidence-only** means retained source bytes have no proven runtime consumer in the supported product, so no behavior is invented.

## HMA collision-mask format

The loader beginning at `0x005300a0` allocates exactly `width × height` bytes, formats `%s.hma` at `0x00530140`, and reads exactly that many bytes at `0x00530189`–`0x0053019e`. The collision consumer beginning at `0x00555230` indexes the buffer at `0x00555289`–`0x005552a2` as:

```text
mask[(source_y + local_y) * sheet_width + source_x + local_x]
```

It sums mask bytes and tests for a nonzero result. All 83 HMA files consumed by the committed v10 catalog contain only `0` and `1`, establishing:

- `0` is empty and `1` is occupied.
- The file is headerless, one byte per atlas pixel.
- Storage is row-major with a top-left logical origin.
- The texture and hit mask use the same source rectangle.
- There is no vertical flip or separate mask-frame transform.

The extractor decodes each RLE TGA into top-left order and compares `alpha != 0` with `HMA != 0`. The direct-orientation match is stronger than a vertical flip for every inspected file:

| Asset | Size | HMA bytes | Direct match | Vertical flip |
| --- | ---: | ---: | ---: | ---: |
| `alien001` | 576×96 | 55,296 | 93.9724% | 57.8686% |
| `alien_2` | 576×96 | 55,296 | 95.5313% | 59.2321% |
| `alien_3` | 576×96 | 55,296 | 100.0000% | 56.7491% |
| `alien000` | 576×96 | 55,296 | 99.7197% | 71.2945% |
| `alien_lilla` | 576×96 | 55,296 | 97.2674% | 62.5307% |
| `fighter1` | 440×28 | 12,320 | 99.4318% | 60.0974% |
| `fighter2` | 440×28 | 12,320 | 97.1185% | 85.9659% |
| `weapons_big` | 672×100 | 67,200 | 95.3467% | 68.5074% |

Alpha mismatches are intentional mask shaping. The HMA, not TGA alpha, is collision authority.

## First-twenty foundational enemy sheets

Lossless LVD decoding proves that every active ordinary enemy in levels 1–20 uses resource slot 1. Levels 1–4 bind `alien001`, 5–8 `alien_2`, 9–12 `alien_3`, 13–16 `alien000`, and 17–20 `alien_lilla`. All active groups use numeric group mode 1.

| Level | Sheet | Authored ordinary enemies | Original state flow reached |
| ---: | --- | ---: | --- |
| 1 | `alien001` | 18 | entry 1 → formation 2 |
| 2 | `alien001` | 22 | entry 1 → formation 2 |
| 3 | `alien001` | 24 | entry 1 → formation 2, plus supplemental state 6 |
| 4 | `alien001` | 25 | entry 1 → kamikaze state 10 |
| 5 | `alien_2` | 22 | entry 1 → formation 2 |
| 6 | `alien_2` | 20 | entry 1 → formation 2 |
| 7 | `alien_2` | 28 | entry 1 → formation 2, plus supplemental state 6 |
| 8 | `alien_2` | 20 | entry 1 |
| 9 | `alien_3` | 24 | entry 1 → formation 2 |
| 10 | `alien_3` | 30 | entry 1 → formation 2 |
| 11 | `alien_3` | 32 | entry 1 → formation 2, plus supplemental state 6 |
| 12 | `alien_3` | 25 | entry 1 → kamikaze state 10 |
| 13 | `alien000` | 24 | entry 1 → formation 2 |
| 14 | `alien000` | 28 | entry 1 → formation 2 |
| 15 | `alien000` | 32 | entry 1 → formation 2, plus supplemental state 6 |
| 16 | `alien000` | 30 | entry 1; mode 3 suppresses ordinary shots |
| 17 | `alien_lilla` | 32 | entry 1 → formation 2 |
| 18 | `alien_lilla` | 34 | entry 1 → formation 2 |
| 19 | `alien_lilla` | 28 | entry 1 → formation 2, plus supplemental state 6 |
| 20 | `alien_lilla` | 30 | entry 1 → kamikaze state 10 |

The v10 catalog extends this same atlas/HMA contract through level 100 and
declares 80 ordered enemy sheets. Levels 21–24 use `alien003` plus
`alien003_3`; level 25 declares the six `alien_big1_*` boss sheets; levels
26–29 use `alien_rakett` and `alien_rakett_gronn`; levels 30–33 use
`alien_baller` and `alien_baller2`; levels 34–37 use `alien_green_lilla_t` and
`alien_cyan_lilla_t`; and levels 38–49 introduce `alien_raudkule`,
`alien_raudkule2`, `alien_blavinger_gf`, `alien_blavinger_gf2`, and
`alien_rbille` in the exact combinations declared by each LVD. Level 50 adds
all six `alien_big2_1` through `alien_big2_6` TGA/HMA pairs for its exact
state-13 encounter. Levels 51–62 add `alien_gultop`, `alien_lillatop`,
`alien_bluekreps`, `alien_lbluekreps`, `alien_brownkreps`,
`alien_brownkreps2`, `alien_gulkreps`, `alien_rvinggk`, and `alien_gvingbk`,
while level 54 also reuses `alien_rakett_gronn`. Levels 63–74 add the royr,
makk, and rocktalien families; level 75 adds all six `alien_big3_*` sheets;
levels 76–99 add the spis, defender, lysper, `n1`/`n2`, metaball, and kule
families; and level 100 adds all six `alien_big4_*` sheets. The complete
per-sheet hashes, alpha/HMA comparisons, resource slots, and level usages live
in the generated v10 JSON.

All 80 576×96 sheets use the same recovered coordinate tables:

- source Y table: `0x007d0268`
- source X table: `0x007d02c0`
- mirrored direction-index table: `0x007d0228`

### State 1: entry directional frames

The state-1 update at `0x0060939c`–`0x006095e8` writes the source coordinates used by the ordinary 32×32 renderer:

```text
frame 0..15 = (x = frame * 32, y = 64, width = 32, height = 32)
```

Direction selection is also recovered:

1. Compute float32 slope `velocity_y / velocity_x`.
2. If `velocity_x == 0`, use `+5000.0` when `velocity_y > 0`, otherwise `-5000.0`.
3. Start at index 0 when `velocity_x >= 0`, otherwise index 8.
4. Find the first strict-open slope interval in the table at `0x007d01e0` and add its bucket `0..8`, modulo 16.
5. When mirrored, remap through `[8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7]`.

The JSON retains every interval as both a readable float and exact IEEE-754 bits. Strict comparisons matter at an exact interval boundary; when no interval matches, the initialized base index remains.

### State 2: formation animation frames

The state-2 path at `0x006095ed`–`0x0060966c` truncates the runtime animation phase and indexes the six-entry tails of the same X/Y tables:

| Frame | Source rectangle |
| ---: | --- |
| 0 | `(512, 0, 32, 32)` |
| 1 | `(512, 32, 32, 32)` |
| 2 | `(512, 64, 32, 32)` |
| 3 | `(544, 0, 32, 32)` |
| 4 | `(544, 32, 32, 32)` |
| 5 | `(544, 64, 32, 32)` |

The rectangles and state-2 selection are proven. “Formation animation” is a supported descriptive name, not an original symbol.

### Supplemental state 6

Twenty-four supported LVDs expose twenty-seven nonzero supplemental records:

```text
3   [1, 1, 12, 1200, 25]
7   [1, 1, 15, 861, 13]
11  [1, 1, 23, 600, 11]
15  [2, 1, 20, 904, 16]
19  [2, 1, 50, 968, 23]
23  [2, 1, 60, 1312, 29]
28  [2, 1, 30, 560, 7]
32  [3, 1, 40, 1076, 30]
36[0] [2, 2, 40, 818, 10]
36[1] [1, 1, 59, 968, 14]
40  [4, 1, 40, 818, 10]
44  [4, 2, 79, 968, 19]
48  [4, 1, 50, 1054, 13]
53[0] [2, 1, 59, 925, 8]
53[1] [2, 1, 79, 1054, 22]
57  [4, 3, 98, 1441, 7]
61  [4, 1, 88, 1162, 23]
65[0] [2, 1, 110, 1484, 14]
65[1] [2, 2, 110, 1570, 14]
69  [4, 1, 108, 1119, 17]
73  [5, 1, 110, 1291, 10]
78  [4, 1, 98, 1742, 26]
82  [5, 1, 300, 1600, 5]
86  [4, 1, 72, 710, 18]
90  [3, 2, 118, 1398, 25]
94  [4, 1, 118, 968, 23]
98  [10, 3, 150, 2000, 10]
```

The spawner uses word 1 as the resource selector, binding the declared slot's
sheet and HMA, width 576 and height 96, then assigns runtime state 6. This
includes slot 2 for level 36 record 0 and level 44, plus slot 3 for level 57.
The state-6 renderer at
`0x0061924d`–`0x006192c9` uses a 64×64 source rectangle. The update at
`0x0060f90b`–`0x0060f92f` sets:

```text
source_x = trunc(animation_phase) * 64
source_y = 0
```

Each sheet exposes seven addressable 64×64 cells at X `0, 64, 128, 192, 256, 320, 384`; an individual sheet may intentionally leave a cell transparent. The formula, size, level linkage, and resource binding are proven. The exported seven-frame upper bound is marked supported because the executable obtains its animation limit through dynamically populated metadata rather than a closed static constant. The second supplemental-projectile phase in `alien_raudkule2` is intentionally blank and is retained as a zero-occupancy mask rather than approximated.

Words 0 and 1 of the supplemental record are proven as spawn count and resource selector. The health/timer labels for words 2–4 remain supported.

### State 10 frame producer

Levels 4, 12, 20, 29, 37, 45, 54, 62, 70, 79, 87, and 95 reach original runtime state 10 after their terminal opcode 6. The selector at `0x0060e5e9`–`0x0060e65a` truncates the entity's existing animation phase and indexes the six-entry tails of the ordinary source tables at `0x007d02a8` and `0x007d0300`. State 10 therefore uses the same six 32×32 rectangles listed for the formation-animation family, not a directional frame or a visual guess.

The update at `0x0060e65b`–`0x0060e82a` subtracts the retail tick scale from the existing countdown and preserves equality. On strict underflow it resets the countdown to `4.0`; a nonzero direction decrements the phase and wraps below zero to 5, while zero increments and wraps above 5 to zero. State-10 entry preserves the per-slot phase, countdown, and direction seeded during level initialization. The v10 contract pins the two instruction regions with SHA-256 values `2f84aa1f998b3af3688dc383fc80de79bfc1687bd3ffef7fa04fbd41abdca260` and `a31a962b37f247fe76840345231e70d1f41d19251e2a625af0693bebb0327701` respectively.

## Fighter sheets and banking

`fighter1` and `fighter2` are each stored as 440×28. The renderer beginning at `0x005ef1b0`, specifically `0x005f0113`–`0x005f01a8`, truncates the float at `player+0x700`, applies signed modulo 11, multiplies by 40, and draws a 40×27 rectangle:

```text
frame 0..10 = (x = frame * 40, y = 0, width = 40, height = 27)
```

HMA row 27 is completely empty for both sheets, confirming that the last storage row is not part of the effective collision frame.

The frame producer is also proven:

- Initialization at `0x0062381f`–`0x00623825` sets `5.0`.
- Left input subtracts `0.5` and clamps at `0.0` (`0x005eb649`–`0x005eb6aa`).
- Right input adds `0.5`; the phase can transiently reach `10.5`, and the next
  right update reaches `11.0` and resets it to `10.0`
  (`0x005eb935`–`0x005eb99a`). Both `10.0` and `10.5` truncate to rendered
  frame 10.
- With no horizontal input, the value moves toward neutral `5.0` by `0.5` without overshoot (`0x005ec978`–`0x005eca10`).
- The left branch executes before the right branch if both are reported active; idle return is skipped when either branch ran.
- The snapshot's integer `sprite_frame` is truncation toward zero of this float phase.

This preserves the original fractional banking timing instead of treating the 11 cells as a free-running animation.

## Player projectile atlas

The projectile renderer beginning at `0x006211e0` constructs `[x, y, x + width, y + height]` from four parallel tables and draws `weapons_big.tga` with its matching HMA:

| Table | Virtual address |
| --- | --- |
| source X | `0x007cd110` |
| source Y | `0x007cd228` |
| width | `0x007cd340` |
| height | `0x007cd458` |

The extraction scope is every projectile prototype reachable from the nine playable weapon graphs in `tools/known_facts.json`.

| Prototype | Source rectangle |
| ---: | --- |
| 0 | `(32, 0, 4, 10)` |
| 1 | `(48, 0, 4, 10)` |
| 4 | `(80, 0, 6, 10)` |
| 6 | `(32, 31, 10, 12)` |
| 7 | `(64, 31, 10, 12)` |
| 8 | `(48, 31, 8, 12)` |
| 9 | `(112, 0, 4, 10)` |
| 14 | `(96, 0, 8, 10)` |
| 15 | `(128, 0, 8, 10)` |
| 18 | `(176, 0, 22, 41)` |
| 19 | `(0, 0, 32, 78)` |
| 20 | `(144, 0, 32, 78)` |
| 21 | `(144, 0, 32, 78)` |
| 22 | `(240, 0, 16, 100)` |
| 23 | `(256, 0, 16, 100)` |
| 24 | `(272, 0, 16, 100)` |
| 25 | `(304, 0, 21, 50)` |
| 26 | `(336, 0, 21, 51)` |
| 30 | `(304, 52, 11, 25)` |
| 31 | `(320, 52, 11, 25)` |
| 50 | `(288, 0, 16, 100)` |
| 63 | `(80, 0, 6, 10)` |
| 64 | `(80, 0, 6, 10)` |
| 65 | `(80, 0, 6, 10)` |
| 66 | `(48, 0, 4, 10)` |

The Laser's persistent frame chain adds prototypes `23`, `24`, and `50` after
the playable root `22`; all four exact rectangles are retained. Exact
source-rectangle aliases are `[1, 66]`, `[4, 63, 64, 65]`, and `[20, 21]`.
These aliases are data, not deduplication guesses; prototypes retain distinct
movement and spawn behavior elsewhere.

## Enemy projectile cells

Ordinary type-7 shots select the firing enemy sheet and use `(480,0,32,32)` and `(480,32,32,32)` with `alienshoot10`. Supplemental state-6 type-6 shots use the same sheet at `(448,0,32,32)` and `(448,32,32,32)` with `alienshoot2`. `enemy_projectile_contracts` records exact occupied bounds and counts for both phases on all 80 current sheets; HMA bytes, not TGA alpha, remain authoritative. Both ordinary projectile cells in `alien_mkuler.hma` are intentionally empty and therefore export null broad- and narrow-phase bounds rather than an invented fallback.

The retail broad phase is distinct from the per-phase HMA narrow phase. `FUN 0x00555a04–0x00555a94` captures eight HMA-derived metadata integers per resource slot into the tables rooted at `0x00803bd0`; entity initialization copies those values at `0x0056bed6` and `0x0056d720`. Type 7 copies the four relevant entity fields at `0x0060788c–0x0060792e` (offsets `0x3fc`, `0x400`, `0x404`, `0x408`), while type 6 does so at `0x0060f016–0x0060f0b8` (offsets `0x3ec`, `0x3f0`, `0x3f4`, `0x3f8`). Collision consumes the projectile bounds at `0x00584459–0x005844e2`. The metadata is sheet-specific but phase-independent and equals each projectile cell's phase-0 local inclusive HMA bounds.

The trace is pinned to retail executable SHA-256 `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`. The table below preserves the five foundational sheets from the original trace; the generated v10 artifact and extractor tests pin the same contract for the other 75 sheets:

| Sheet | TGA SHA-256 | HMA SHA-256 | Type 7 bounds | Type 6 bounds |
| --- | --- | --- | --- | --- |
| `alien001` | `6bd559f5fb7d03736131673fcf77a7f5925c993afb7fbfd1eeca5e2db30f760e` | `0b04983374edaddf153dabfe571093b1106d4fb735ea3de0a2cb9db44258fa49` | `[0,0,5,13]` | `[0,1,11,12]` |
| `alien_2` | `a805177aba06d5b725f292a0f828f24a274dd307f39b2bf2f3be9381a69b8f34` | `41d6c093aca7c7d312ccc1a877edfca1c749d4dffdb9d211ad8a82c9ded9dbee` | `[0,0,3,11]` | `[2,2,9,9]` |
| `alien_3` | `1995f7f478ddb3d3f53c2a46d5100223f0fd12739c709427a5ee73d4f0988308` | `bae7ff4e43ac9b5f3e985508b502e417462b59515b4a582d5ad8dd98d2657622` | `[0,0,5,12]` | `[0,0,31,12]` |
| `alien000` | `3dda14d46beab0e81826a02671ebcfb5d9b7cc11762c5b7ecfe9cc2b6e963575` | `2153c68d6529e03ffa016752d8d0e12eb67f4282b7105db3fe1651a1e86d2f56` | `[0,0,7,13]` | `[0,0,13,16]` |
| `alien_lilla` | `0876ed4f60bdc24f3368d1a1a32e86a771df9222cf354618bef313b9cf22c321` | `f6af03a6a15fba704e14b21be11be9908e52b5adcd372aa3612731e97622bb09` | `[0,0,5,9]` | `[0,0,11,11]` |

Level 50's six Big2 sheets are independently byte-pinned and retain their
sheet-specific projectile broad phase:

| Sheet | TGA SHA-256 | HMA SHA-256 | Type 7 bounds | Type 6 bounds |
| --- | --- | --- | --- | --- |
| `alien_big2_1` | `1da17e9670abbfa2bc87a9deab2b083b2b2557e2c059a1fb5dc65310898ae0ff` | `246f2ae2b2b98050f3e2ecb9f55be50b192fdc9ea845a07416bab7d6bc95cd7b` | `[0,0,28,31]` | `[0,0,31,31]` |
| `alien_big2_2` | `4132e267ef0a32f339b29cdc92c6d967a5620e3580c8af329f35121eb3c1630a` | `665e76e2e064381ba1718f5353d76267701fd0202836206e79714e09246cae28` | `[0,0,28,31]` | `[0,0,31,31]` |
| `alien_big2_3` | `82293326f90147696c41e9753ecc2d187ecf82a562140cff5d87562092fa8c1b` | `871ed4f97abed103725294e5800f95566d57f28f0f91701088be6cd2dd93a9b0` | `[0,0,28,31]` | `[0,0,31,31]` |
| `alien_big2_4` | `8674358067fe3919cc9deaac886904065ce3f8c974fa8b71e3ba7effebdec569` | `9a76057353965b5eea3fbc0de91d97c1620d11de1a0c256467e82bbdf89ae606` | `[0,0,28,31]` | `[0,0,31,31]` |
| `alien_big2_5` | `4f9399fd8a5c64a78ad2ef87439ca0baf0af3fa8311831495a9de07f70acd850` | `201b6696787ae1b5ac891d99879d4f1aba4a84b8c7976760473ed7e853a63e9e` | `[0,0,28,31]` | `[0,0,31,31]` |
| `alien_big2_6` | `42a7f0814ad72d426c46ec2f1247d331763d460dd526b9a08f112fdc8b62a008` | `aa4d4ad044cdb47b047ce8a85260bfd85dae040c26e8704fdba306d680801c74` | `[0,0,29,31]` | `[0,0,31,31]` |

## Artifact contract

`content/sprite_frames.json` provides:

- executable identity and all table addresses
- verified HMA format, paths, dimensions, occupancy totals, and orientation checks
- level-to-sheet/resource mappings from all 100 original LVDs
- exact enemy, fighter, and playable-projectile texture/HMA rectangles
- renderer selection contracts keyed by remake snapshot `authored_state`
- exact directional slope/mirror tables
- the fighter frame producer and renderer rule
- all twenty-seven supplemental record-to-state-6 linkages across twenty-four levels
- per-claim confidence and explicit evidence-only boundaries

`content/sprites.json` is intentionally not treated as evidence for these rectangles. The extractor and its generated artifact supersede the earlier equal-grid implementation, which is no longer a runtime input.
