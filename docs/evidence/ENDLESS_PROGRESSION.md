# Retail Endless Progression (Levels Beyond 100)

This document closes what retail `warblade.exe` does after level 100. It comes
from bounded static analysis of the retail executable, not screenshot
matching. The machine-readable extraction is in `endless_progression.json`,
and `tools/endless_progression_test.py` pins the executable bytes used by each
conclusion.

## Evidence identity and confidence

The analyzed executable has SHA-256:

```text
ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef
```

Addresses are 32-bit PE virtual addresses for that image.

- **Proven** means the retail instruction bytes and a complete relevant
  gameplay consumer are pinned by the extraction.
- **Evidence-only** preserves an exact value whose consumer is not closed.

## Executive result

Retail Warblade does not end at level 100. The campaign continues without a
terminal level: level content cycles through the authored 100-level set,
presentation alternates a horizontal mirror every hundred, and a cumulative
progression step raises difficulty at levels 101, 201, 301, ... without a
documented ceiling. The level counter itself clamps at 3999. The manual agrees:
credits roll at level 100 and play continues ("Added Small text to level 100
credits (left and right mouse and continue)"), "Difficulty now goes up
forever !!", "Aliens WILL now speed up per 100 levels", and profile stats
record a best "Level 100 score" for *passing* level 100.

## Step trigger

The progression step fires once per crossed hundred. The cumulative
resume/warp loop at `0x005382dd`–`0x00538403` applies it for every level `L`
up to the current level that satisfies:

```text
L > 5 and (L - 1) mod 100 == 0
```

so the steps fire at levels 101, 201, 301, ... and the number of applied
steps at level `N` is `(N - 1) // 100`. The level-start path
(`0x00569be5`–`0x00569c55`) applies the identical step body. This trigger is
the same condition previously documented for the ordinary health additive in
`DIFFICULTY_RULES.md`; the step body is much wider than health.

## Step effects (each applied per crossed hundred)

| Effect | Global / field | Per step | Bound |
| --- | --- | ---: | --- |
| ordinary enemy health additive | `0x00e113f8` | +1.0 | none traced |
| special-class health additive | `0x00e113fc` | +5.0 | none traced |
| — of which one traced class consumes | `0x00e113fc` | additive × 20.0 | none traced |
| ordinary alien projectile base speed | `0x008f2060` | × 1.025 (float32) | none traced |
| simulation scale source | `0x007d1520` | + 0.12 (float32) | none traced |
| timer A initial adjustment | `0x008f20b8` | − 50 | floor −500 |
| timer B initial adjustment | `0x008f20b4` | − 50 | floor −500 |
| per-player update target | `0x00848ba4` | +2 Easy / +3 Normal / +3 Hard / +2 Ace | none traced |

Proven consumers:

- Ordinary spawn (`0x0056d094`, `0x0056d0df`): current and maximum health are
  `authored LVD base + int(health additive)`.
- The special-class additive is consumed at `0x0056b52f`–`0x0056b546` as
  `authored base + int(additive × 20.0)` and at `0x0056e4c8` as
  `authored base + int(additive)`, both storing the enemy health field.
- The projectile multiplier compounds with the difficulty base speeds
  (`0x008f2060`, proven in `DIFFICULTY_RULES.md`), so level `N` ordinary
  projectile base is `base × 1.025^steps(N)`.
- The simulation-scale increment adds to the difficulty scale source
  (`0x007d1520`), which the ordinary setup copies to the authoritative runtime
  scale (`0x00e11274`); effective pace at level `N` is
  `difficulty_scale + 0.12 × steps(N)`.
- The timer adjustments shift the spawn timers
  (`max(authored + adjustment, floor)`), so firing accelerates each hundred
  until the −500 adjustment floor pins every spawn at the difficulty floor.
- The per-player update target (`0x00848ba4`) initializes from the retail
  update target `0x00af7890` (60) and gains `0x008f2058` (2/3/3/2 by
  difficulty) per step: the whole simulation ticks faster each hundred.

The first progression step in a session additionally writes 60 to
`0x007d0790` (evidence-only; no consumer is closed here).

## Content cycling and mirror

Level content and presentation cycle with period 100:

- The background band keys on `level mod 100` (remainder stored at
  `0x00569d6f`, bands at `0x00569d75`–`0x0056a14c`).
- The loader formats `classic_level_%03d.lvd` from the requested number
  (`0x005681e6`) and returns failure for absent files; the enumeration at
  `0x005571d3`–`0x00557244` scans numbers 1–500, which is the documented
  custom-level boundary. The built-in campaign cycles through the authored
  set; the wrapped authored level is `((level - 1) mod 100) + 1`.
- The LVD mirror flag at `0x00e10f3b` is `(level // 100) & 1`
  (`0x0056a6f6`–`0x0056a712`): levels 100–199 are mirrored, 200–299 are not,
  and so on. For levels 1–100 this matches the authored `mirror_x` exactly
  (only level 100 is authored mirrored); the same formula extends the mirror
  to every wrapped level.

Because shops, bonus levels, warp-malfunction levels, and the state-13 big
bosses are all authored LVD data, they recur on the wrapped levels: shops
after every fourth wrapped level, bosses at wrapped 25/50/75/100 with the
mirror alternating per hundred.

## Level counter clamp

The per-player level number clamps at 3999 (`0x00569c73`–`0x00569c81`). No
other terminal boundary exists in the traced progression.

## Implementation coverage

The remake applies the step to ordinary enemies (+1 health), supplemental
specials (+5 health), ordinary projectile speed (×41/40), simulation scale
(+3/25 folded with the update-target pace), timer adjustments (−50, floored),
and the traced ×20 special-class consumer (state-13 boss-family health,
+100 per hundred). The boss additive ships as the versioned
`health.endless_step_additive` field of the `warblade.bosses.v5` contracts,
applied at encounter entry as `retail + 100 × steps` before the remake's
balanced-co-op multiplier; steps are zero throughout levels 1–100, so every
replay-pinned authored encounter is unchanged. The played 95→126 campaign
segment (`tests/sim/test_campaign_beyond_one_hundred.gd`) proves the credits
interstitial, wrapped shop cadence, the mirrored wrapped level-125 encounter
at 400 health, and frame-by-frame replay determinism across the boundary.

## Level-100 credits are an interstitial

The manual's changelog notes level-100 credits that the player dismisses to
continue, and profile stats keep a "Level 100 score" for *passing* level 100.
The credits/ending presentation therefore precedes continued play at level
101; it is not campaign completion.

## Deterministic server model

The remake reproduces the progression with exact rationals, consistent with
the deterministic modernization policy in `DIFFICULTY_RULES.md`:

- steps(`N`) = `(N - 1) // 100`;
- ordinary health additive = `steps`; special additive = `5 × steps`
  (traced ×20 class: `100 × steps`);
- projectile base multiplier = `(41/40)^steps` (retail stores
  float32(1.025));
- simulation scale = difficulty base + `(3/25) × steps` (retail stores
  float32(0.12));
- timer adjustments = difficulty adjustment − `50 × steps`, floored at −500;
- update-target pace factor = `(60 + {2,3,3,2} × steps) / 60`.

Retail's update-target increment raises ticks per second; the deterministic
model folds it into the effective scale because every traced consumer
(movement, firing probability per tick) is linear in ticks-per-second times
per-tick scale. Replay and hash-state version any residual float32 boundary
differences, as with the difficulty model.

## Reproduction

```sh
python3 tools/endless_progression_extract.py
python3 tools/endless_progression_extract.py --check
python3 tools/endless_progression_test.py
```

The tests pin the executable hash, the step constants, both step application
sites, the cumulative loop condition, the timer floor, the mirror rule, the
content-cycling remainder, the update-target wiring, and the 3999 clamp.
