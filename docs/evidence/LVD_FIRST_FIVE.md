# First Five LVD Evidence Summary

This is a compact inventory of the first five retail levels decoded with `tools/lvd_decoder.py`. Every generated JSON document reconstructs its source LVD byte for byte.

| Level | Mode | Groups | Enemies | Active path points | Title | First resource |
| ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 | 1 | 2 | 18 | 22 | `JUST WARMING UP` | `ALIEN001.bmp` |
| 2 | 1 | 2 | 22 | 20 | empty in source | `ALIEN001.bmp` |
| 3 | 1 | 2 | 24 | 24 | `THE FIRST BIG ONE` | `ALIEN001.bmp` |
| 4 | 2 | 25 | 25 | 85 | `K A M I K A Z E` | `ALIEN001.bmp` |
| 5 | 1 | 2 | 22 | 42 | `GETTING A BIT WARMER` | `ALIEN_2.bmp` |

## Group headers

Header tuples below are:

```text
[entry_x, entry_y, first_delay, stagger, enemy_count,
 initial_velocity_x_milli, initial_velocity_y_milli, kill_cohort_id, group_mode_id]
```

Level 1:

```text
[-200, -75, 0, 15, 9,  448, 448, 0, 1]
[ 202, -73, 0, 15, 9, -448, 448, 0, 1]
```

Level 2:

```text
[0, -108, 0, 13, 11, 0, 448, 0, 1]
[0, -108, 6, 13, 11, 0, 448, 0, 1]
```

Level 3:

```text
[-242, -68, 0, 15, 12, 0, 448, 0, 1]
[ 242, -68, 0, 15, 12, 0, 448, 0, 1]
```

Level 5:

```text
[-92, -90, 1, 15, 11, -205, 448, 0, 1]
[ 92, -90, 0, 15, 11,  205, 448, 0, 1]
```

Level 4 has one enemy per group. Its five activation cohorts are:

| Groups | Entry origin | First delay | Authored stagger | Kill cohort | Path count |
| --- | --- | ---: | ---: | ---: | ---: |
| 0–4 | `(-250, -33)` | 5 | 0 | 0 | 3 |
| 5–9 | `(-163, -47)` | 200 | 0 | 1 | 3 |
| 10–14 | `(-58, -30)` | 390 | 0 | 2 | 3 |
| 15–19 | `(43, -32)` | 525 | 21 | 4 | 3 |
| 20–24 | `(182, -35)` | 720 | 24 | 5 | 5 |

Because level 4 uses mode 2, the executable suppresses per-enemy stagger. Each group contains one enemy in any case.

## Path endings

| Level | Per-group path count | Opcode counts | Terminal point |
| ---: | --- | --- | --- |
| 1 | `11, 11` | opcode 0 × 20; opcode 1 × 2 | `[0, 0, 1, 0, 100]` |
| 2 | `10, 10` | opcode 0 × 18; opcode 1 × 2 | `[0, 0, 1, 0, 100]` |
| 3 | `12, 12` | opcode 0 × 22; opcode 1 × 2 | `[0, 0, 1, 0, 100]` |
| 4 | groups 0–19: 3; groups 20–24: 5 | opcode 0 × 60; opcode 6 × 25 | `[0, 0, 6, 0, 1]` |
| 5 | `21, 21` | opcode 0 × 40; opcode 1 × 2 | `[0, 0, 1, 0, 100]` |

The level-4 terminal opcode is not interchangeable with the normal mode-1 ending. In mode 2, opcode 6 changes the entity to the kamikaze/randomized motion state.

## Supplemental spawn records

Levels 1, 2, 4, and 5 have no active supplemental record. Level 3 record 0 is:

```text
[1, 1, 12, 1200, 25]
```

The additive executable trace now proves this record as count `1`, resource
selector `1`, base health `12`, timer-A initial `1200`, and timer-A step `25`.
It must not be remapped to lives, a projectile type, a drop, or a reward;
`ENEMY_BEHAVIOR_STATIC_TRACE.md` owns the consumer proof.

## Generated authority

The decoded documents are:

- `content/lvd_decoded/classic_level_001.json`
- `content/lvd_decoded/classic_level_002.json`
- `content/lvd_decoded/classic_level_003.json`
- `content/lvd_decoded/classic_level_004.json`
- `content/lvd_decoded/classic_level_005.json`

Each document includes:

- source size and SHA-256
- exact file offsets and raw signed words
- proven read-only aliases
- executable evidence addresses
- a base64 copy of the complete original blob

`raw_blob_base64` is the round-trip authority. Interpreted fields are not silently serialized over it.
