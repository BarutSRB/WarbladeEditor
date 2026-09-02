# Warblade LVD Static Trace

This document records the binary contract recovered from the retail executable without requiring live play. It is the implementation basis for the remake's authored level data. Human-readable names are only assigned where the executable loader and at least one consumer agree.

## Evidence identity

| Artifact | SHA-256 |
| --- | --- |
| `Game/warblade.exe` | `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef` |
| `classic_level_001.lvd` | `6938e9f31d93071b129a7c583f37751e899239bd97dd3d4c678664880d04aaf1` |
| `classic_level_002.lvd` | `0db45277db488947b998b1478523c2e8d2905c0d720ddb9a3efc489423a38934` |
| `classic_level_003.lvd` | `32f28ba7335a5fde68951f7f4af8ecf8c6f5937cb0d12e60eafb9ee229680a33` |
| `classic_level_004.lvd` | `0c816b48f007965b14a141797603a13de900879030895016e3491a56c5ab5942` |
| `classic_level_005.lvd` | `0584103d5211181bb65deef633cd6d440bbc1658bcf5ed71132e740d457044c6` |

Addresses below are 32-bit PE virtual addresses for that executable.

## File acquisition and exact extent

The executable formats `classic_level_%03d.lvd` at `0x005681e6` and reads exactly `0x1cb98` bytes into `0x00d0d9b0` at `0x0056822f`–`0x0056823f`. The deserializer is the function beginning at `0x00558d60`; its contiguous reads establish the complete layout below.

| Offset | Size | Contents |
| --- | ---: | --- |
| `0x00000` | `0x006c` | 27 signed little-endian words: mode, active group count, five supplemental records |
| `0x0006c` | `0x9fc4` | 25 group slots of `0x664` bytes |
| `0x0a030` | `0x0064` | 25 active path counts |
| `0x0a094` | `0x0024` | title Pascal string slot |
| `0x0a0b8` | `0x0034` | author Pascal string slot |
| `0x0a0ec` | `0x12558` | 25 path slabs of `0xbb8` bytes |
| `0x1c5e4` | `0x0264` | 12 Pascal resource slots of `0x33` bytes |
| `0x1c848` | `0x0320` | 50 lossless records of four signed words; proven consumers are documented separately |
| `0x1cb68` | `0x0018` | six-word tail A; score consumers are proven selectively |
| `0x1cb80` | `0x0018` | evidence-only six-word tail B |
| `0x1cb98` | — | exact end of file |

The regions are contiguous. There is no unaccounted remainder and no literal `.swd` reference in an LVD blob.

Each group slot is:

```text
9 signed words group header                   0x024 bytes
50 × 8 signed words enemy records             0x640 bytes
                                                  -----
                                                  0x664
```

Each path slab is `150 × 5 signed words = 0xbb8` bytes.

## Global header

| Word | Proven use |
| --- | --- |
| `+0x00` | numeric level mode ID |
| `+0x04` | active group count, `0..25` |
| `+0x08` | five supplemental spawn records, each five words |

The five supplemental records are not player lives, credits, RNG seeds, shop
data, or general game metadata. The executable iterates the records again at
`0x0056d468`. Record word 0 is a spawn count, word 1 selects a resource/type
case, and words 2–4 are base health, timer-A initial, and timer-A step as closed
by `ENEMY_BEHAVIOR_STATIC_TRACE.md`. Level 3 is the only first-five file with a
nonzero count: `[1, 1, 12, 1200, 25]`.

## Group header

| Offset | Decoder key | Status | Runtime use |
| --- | --- | --- | --- |
| `+0x00` | `entry_origin_x` | proven | authored entry X, transformed around logical screen center |
| `+0x04` | `entry_origin_y` | proven | authored entry Y |
| `+0x08` | `first_activation_delay_ticks` | proven | initial activation countdown for the first group member |
| `+0x0c` | `activation_stagger_ticks` | proven | added after each member, except in level mode 2 |
| `+0x10` | `active_enemy_count` | proven | number of active enemy records, `0..50` |
| `+0x14` | `initial_velocity_x_milli` | proven | divided by `1000.0` by the loader |
| `+0x18` | `initial_velocity_y_milli` | proven | divided by `1000.0` by the loader |
| `+0x1c` | `kill_cohort_id` | proven | shared completion counter ID |
| `+0x20` | `group_mode_id` | proven numeric selector | human-readable meanings remain incomplete |

Spawn increments the per-group member total at `0x00d59fc0[group]` and the per-cohort total at `0x00b04248[cohort]`. Enemy destruction increments the corresponding killed counters at `0x00cde1c0[group]` and `0x008037d0[cohort]` at `0x00588c0d`–`0x00588c87` and `0x00588f64`–`0x00588fde`. Equality triggers the respective group/cohort completion flow.

## Enemy record

| Offset | Decoder key | Status | Runtime use |
| --- | --- | --- | --- |
| `+0x00` | `formation_target_x` | proven | final formation X, transformed around logical center |
| `+0x04` | `formation_target_y` | proven | final formation Y |
| `+0x08` | `resource_slot_id` | proven | selects one of six traced bitmap slots |
| `+0x0c` | `base_health` | proven | difficulty contribution is added, then copied to current and maximum health |
| `+0x10` | `behavior_timer_a_initial` | proven | projectile-fire denominator outside state 2 |
| `+0x14` | `behavior_timer_a_step` | proven | post-kill timer-A tightening |
| `+0x18` | `behavior_timer_b_initial` | proven | state-2 SWD-launch denominator |
| `+0x1c` | `behavior_timer_b_step` | proven | post-kill timer-B tightening |

Base health is consumed at `0x0056d094`–`0x0056d114`. Damage subtracts from current health at `0x00585e55`–`0x00585e77`, with death handling after the nonpositive check at `0x0058603b`.

The timer pairs are initialized into runtime fields around
`0x0056d160`–`0x0056d379`. The complete consumers in
`ENEMY_BEHAVIOR_STATIC_TRACE.md` prove timer A as the projectile-fire
denominator in states 1/3/4/6/10, timer B as the state-2 SWD-launch
denominator, and both steps as post-collision qualifying-kill reductions.

## Logical coordinate transform

The original logical width is the integer at `0x007d32f8`, whose retail value is `800`. The transform is performed at `0x0056cc15`–`0x0056cdc1`.

The retail runtime stores the active 32x32 enemy position as a top-left coordinate. For the nonmirrored case:

```text
formation_target_x = 400 + authored_formation_target_x
formation_target_y = authored_formation_target_y
retail_entry_left   = 400 + authored_entry_origin_x - 16
retail_entry_top    = authored_entry_origin_y - 16
```

For the mirrored case, X additions become subtractions:

```text
formation_target_x = 400 - authored_formation_target_x
retail_entry_left   = 400 - authored_entry_origin_x - 16
```

The remake simulation and renderer use entity centers. The lossless conversion therefore adds the 16-pixel half extent back to the retail entry position:

```text
remake_entry_center_x = retail_entry_left + 16
remake_entry_center_y = retail_entry_top + 16
```

Formation targets are already consumed as logical center-space targets and are not offset again. For level 1 group 0 enemy 0, the retail entry top-left `(184, -91)` becomes remake center `(200, -75)`. After its first normal tick, the center is `(200.448, -74.552)` and the formation target remains `(358, 85)`.

The mirror byte at `0x00e10f3b` is global runtime state, not an LVD group field. Level setup computes:

```text
mirror = (current_level_number // 100) & 1
```

at `0x0056a6f6`–`0x0056a712`. All groups in levels 1–5 therefore use `mirror = 0`. Player coordinates and bounds are recorded separately in `PLAYER_STATIC_TRACE.md`.

For a high-resolution remake, preserve this logical-coordinate simulation and scale the presentation. Reinterpreting the authored values as physical display pixels would change paths and formations.

## Activation sequencing

The group spawner at `0x00569260` walks the active groups and each active enemy:

1. Start an accumulator from `first_activation_delay_ticks`.
2. Copy it to the entity's activation countdown.
3. Unless `level_mode_id == 2`, add `activation_stagger_ticks`.
4. The update loop subtracts the simulation tick scale while the countdown is positive.
5. Entry movement begins when the countdown expires.

Level 4 uses mode 2, so its authored stagger values are not added even when nonzero.

## Fixed-tick path simulation

The executable stores a float tick scale at `0x00e11274`. Normal play loads `1.0` from `0x007d1520`; a special-fast flag loads `3.0` from `0x0077ada4` at `0x005a0851`–`0x005a0870`. Initialization sets the update target to `60` at `0x005a0830`.

Each path point contains:

| Offset | Decoder key | Status |
| --- | --- | --- |
| `+0x00` | `acceleration_x_milli` | proven, divided by `1000.0` |
| `+0x04` | `acceleration_y_milli` | proven, divided by `1000.0` |
| `+0x08` | `opcode` | proven numeric command |
| `+0x0c` | `unknown_0c` | evidence-only; no reachable runtime consumer |
| `+0x10` | `duration_threshold_ticks` | proven |

The ordinary update at `0x00613a21`–`0x00613bbe` uses this exact explicit-Euler order:

```text
position.x += velocity.x * tick_scale
position.y += velocity.y * tick_scale
velocity.x += acceleration.x * tick_scale
velocity.y += acceleration.y * tick_scale
progress   += tick_scale
```

Progress is converted to an integer and compared at `0x00613bd9`–`0x00613c2d`. The path advances only when:

```text
int(progress) > duration_threshold_ticks
```

The strict comparison is important: with normal tick scale `1.0`, a threshold of `N` runs through integer progress `N` and advances on the following tick.

The authoritative remake simulation should remain fixed at 60 updates per second and preserve the explicit-Euler order. High-refresh rendering should interpolate between authoritative states rather than changing the tick rate or multiplying authored values by render delta.

## Observed path opcodes

These are behavior observations, not invented enum names:

| Opcode | Traced side effect |
| ---: | --- |
| `0` | no extra side effect; ordinary acceleration segment |
| `1` | threshold other than 100 clears velocity and acceleration for that timed path point while state-1 progress continues, so the next point advances only after the same strict `N+1` crossing; threshold 100 is a terminal scripted-entry marker, and mode 1 transitions to post-entry state 2 |
| `2` | scans for groups with group mode 6 and spawns secondary objects |
| `3` | sets executable global `0x00e11a38` |
| `6` | mode 2 enters state 10 randomized/kamikaze motion; other traced modes deactivate the entity |
| `7` | sets an entity flag, reverses positive velocity components, and clears acceleration/progress |

Only opcodes `0` and `1` occur in first-five levels 1, 2, 3, and 5. Level 4 uses only `0` and terminal `6`.

## Evidence boundary

Confirmed:

- exact file extent and complete region arithmetic
- group/enemy/path counts and record strides
- entry and target coordinate transforms
- activation delays and mode-2 stagger suppression
- group initial velocity, enemy base health, and kill cohorts
- path acceleration, tick integration order, progress comparison, and observed opcode branches

Closed by the additive behavior/catalog traces:

- both enemy timer pairs and their post-kill update order
- supplemental words 2–4 and the reachable state-6 consumer
- executable-proven fixed-table animation entries and tail-A score entries
- global loaded-catalog SWD selection with no per-LVD assignment

Evidence-only for the finite product:

- human-readable names for numeric group modes beyond proven consumers
- path word `+0x0c`, whose 3,607 catalog values are zero and unconsumed
- inactive fixed-table entries, tail B, and unused resource slots

The lossless decoder preserves those evidence-only bytes verbatim so additional
forensic work would not require a format migration; they create no runtime
backlog.
