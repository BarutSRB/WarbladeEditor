# Classic levels 1–100 evidence

This unified inventory derives authored campaign content from the exact retail LVD bytes. The lossless documents retain the original raw blob as round-trip authority; authored v2 is the runtime projection.

```sh
python3 tools/classic_levels_extract.py
python3 tools/classic_levels_extract.py --check
```

| Level | Mode | Group enemies | Authored / resolved | Paths | Resource scores | Shop |
|---:|---:|---|---:|---|---|---|
| 1 | 1 | `9×2` | 18 / 18 | `11×2` | `ALIEN001.bmp:50` | No |
| 2 | 1 | `11×2` | 22 / 22 | `10×2` | `ALIEN001.bmp:20` | No |
| 3 | 1 | `12×2` | 24 / 25 | `12×2` | `ALIEN001.bmp:50` | No |
| 4 | 2 | `1×25` | 25 / 25 | `3×20, 5×5` | `ALIEN001.bmp:500` | Yes |
| 5 | 1 | `11×2` | 22 / 22 | `21×2` | `ALIEN_2.bmp:50` | No |
| 6 | 1 | `10×2` | 20 / 20 | `11×2` | `ALIEN_2.bmp:75` | No |
| 7 | 1 | `14×2` | 28 / 29 | `11×2` | `ALIEN_2.bmp:75` | No |
| 8 | 3 | `10×2` | 20 / 20 | `9×2` | `ALIEN_2.bmp:200` | Yes |
| 9 | 1 | `12×2` | 24 / 24 | `11×2` | `ALIEN_3.bmp:150` | No |
| 10 | 1 | `8, 7, 8, 7` | 30 / 30 | `11×4` | `ALIEN_3.bmp:75` | No |
| 11 | 1 | `9, 7, 9, 7` | 32 / 33 | `11×4` | `ALIEN_3.bmp:75` | No |
| 12 | 2 | `1×25` | 25 / 25 | `3×25` | `ALIEN_3.bmp:150` | Yes |
| 13 | 1 | `24` | 24 / 24 | `16` | `ALIEN000.bmp:50` | No |
| 14 | 1 | `14×2` | 28 / 28 | `16×2` | `ALIEN000.bmp:50` | No |
| 15 | 1 | `8×4` | 32 / 34 | `15×4` | `ALIEN000.bmp:50` | No |
| 16 | 3 | `15×2` | 30 / 30 | `15×2` | `ALIEN000.bmp:100` | Yes |
| 17 | 1 | `8×4` | 32 / 32 | `14×4` | `ALIEN_Lilla.bmp:150` | No |
| 18 | 1 | `5, 6×2, 5, 6×2` | 34 / 34 | `14×6` | `ALIEN_Lilla.bmp:175` | No |
| 19 | 1 | `7×4` | 28 / 30 | `17×4` | `ALIEN_Lilla.bmp:175` | No |
| 20 | 2 | `5×6` | 30 / 30 | `3×6` | `ALIEN_Lilla.bmp:200` | Yes |
| 21 | 1 | `12×2, 4×2` | 32 / 32 | `13×2, 9×2` | `ALIEN003.bmp:200, ALIEN003_3.bmp:300` | No |
| 22 | 1 | `10×2, 5×2` | 30 / 30 | `9×4` | `ALIEN003.bmp:200, ALIEN003_3.bmp:300` | No |
| 23 | 1 | `8×2, 5×2` | 26 / 28 | `8×2, 7×2` | `ALIEN003.bmp:200, ALIEN003_3.bmp:300` | No |
| 24 | 3 | `30` | 30 / 30 | `14` | `ALIEN003.bmp:200` | Yes |
| 25 | 4 | `1×2, 12, 1×2` | 16 / 17 | `7, 43, 0×3` | `ALIEN_BIG1_1.bmp:50, ALIEN_BIG1_2.bmp:50, ALIEN_BIG1_3.bmp:0, ALIEN_BIG1_4.bmp:0, ALIEN_BIG1_5.bmp:0, ALIEN_BIG1_6.bmp:0` | No |
| 26 | 1 | `25` | 25 / 25 | `14` | `ALIEN_rakett.bmp:300, ALIEN_rakett_gronn.bmp:400` | No |
| 27 | 1 | `11×2` | 22 / 22 | `14×2` | `ALIEN_rakett.bmp:300, ALIEN_rakett_gronn.bmp:400` | No |
| 28 | 1 | `6×4` | 24 / 26 | `17, 10×2, 17` | `ALIEN_rakett.bmp:300, ALIEN_rakett_gronn.bmp:400` | Yes |
| 29 | 2 | `6×6` | 36 / 36 | `3×6` | `ALIEN_rakett.bmp:400, ALIEN_rakett_gronn.bmp:400` | No |
| 30 | 1 | `12×2, 3×2` | 30 / 30 | `10×4` | `ALIEN_baller.bmp:500, ALIEN_baller2.bmp:600` | No |
| 31 | 1 | `8, 6×2, 8` | 28 / 28 | `10×4` | `ALIEN_baller.bmp:500, ALIEN_baller2.bmp:600` | No |
| 32 | 1 | `3×6` | 18 / 21 | `10×6` | `ALIEN_baller.bmp:500, ALIEN_baller2.bmp:600` | Yes |
| 33 | 3 | `15×2` | 30 / 30 | `11×2` | `ALIEN_baller.bmp:500, ALIEN_baller2.bmp:600` | No |
| 34 | 1 | `15×2` | 30 / 30 | `12×2` | `ALIEN_Green_lilla_t.bmp:450, ALIEN_Cyan_lilla_t.bmp:550` | No |
| 35 | 1 | `11, 7, 11, 7` | 36 / 36 | `12×4` | `ALIEN_Green_lilla_t.bmp:450, ALIEN_Cyan_lilla_t.bmp:550` | No |
| 36 | 1 | `14, 10×2, 14` | 48 / 51 | `21×4` | `ALIEN_Green_lilla_t.bmp:450, ALIEN_Cyan_lilla_t.bmp:550` | Yes |
| 37 | 2 | `6×6` | 36 / 36 | `11×2, 10×2, 11×2` | `ALIEN_Green_lilla_t.bmp:450, ALIEN_Cyan_lilla_t.bmp:550` | No |
| 38 | 1 | `18×2` | 36 / 36 | `13×2` | `ALIEN_RaudKule.bmp:500, ALIEN_Cyan_lilla_t.bmp:550` | No |
| 39 | 1 | `20×2` | 40 / 40 | `16×2` | `ALIEN_RaudKule.bmp:500, ALIEN_RaudKule2.bmp:550` | No |
| 40 | 1 | `30` | 30 / 34 | `15` | `ALIEN_RaudKule.bmp:500, ALIEN_RaudKule2.bmp:550` | Yes |
| 41 | 3 | `20×2` | 40 / 40 | `20×2` | `ALIEN_RaudKule.bmp:500, ALIEN_RaudKule2.bmp:550` | No |
| 42 | 1 | `15×4` | 60 / 60 | `9, 3×2, 9` | `ALIEN_Blavinger_gf.bmp:600, ALIEN_RaudKule2.bmp:550` | No |
| 43 | 1 | `10×4` | 40 / 40 | `11×4` | `ALIEN_Blavinger_gf.bmp:600, ALIEN_RaudKule2.bmp:550` | No |
| 44 | 1 | `10×2, 6×2, 10×2` | 52 / 56 | `5×2, 4×2, 5×2` | `ALIEN_Blavinger_gf.bmp:600, ALIEN_Blavinger_gf2.bmp:750` | Yes |
| 45 | 2 | `5×6` | 30 / 30 | `3×6` | `ALIEN_Blavinger_gf2.bmp:200` | No |
| 46 | 1 | `15×6` | 90 / 90 | `4×2, 5×2, 2×2` | `ALIEN_RBille.bmp:800` | No |
| 47 | 1 | `5×6, 15×2` | 60 / 60 | `4×6, 2×2` | `ALIEN_RBille.bmp:850` | No |
| 48 | 1 | `5×10, 20×2` | 90 / 94 | `4×10, 17×2` | `ALIEN_RBille.bmp:850` | Yes |
| 49 | 3 | `10×4` | 40 / 40 | `4×4` | `ALIEN_RBille.bmp:750` | No |
| 50 | 4 | `1×2, 10, 1×2` | 14 / 15 | `2, 21, 0×3` | `ALIEN_big2_1.bmp:0, ALIEN_big2_2.bmp:0, ALIEN_big2_3.bmp:0, ALIEN_big2_4.bmp:0, ALIEN_big2_5.bmp:0, ALIEN_big2_6.bmp:0` | No |
| 51 | 1 | `12×2, 8×2, 10, 8×2, 10` | 76 / 76 | `7×4, 21, 7×2, 21` | `ALIEN_gultop.bmp:1000` | No |
| 52 | 1 | `40×3` | 120 / 120 | `8×3` | `ALIEN_gultop.bmp:1000` | Yes |
| 53 | 1 | `5×6` | 30 / 34 | `2×6` | `ALIEN_gultop.bmp:1000, ALIEN_lillatop.bmp:1200` | No |
| 54 | 2 | `6×6` | 36 / 36 | `3×6` | `ALIEN_gultop.bmp:500, ALIEN_rakett_gronn.bmp:400` | No |
| 55 | 1 | `10×6` | 60 / 60 | `12×6` | `ALIEN_bluekreps.bmp:750, ALIEN_lbluekreps.bmp:800, ALIEN_brownkreps.bmp:1000` | No |
| 56 | 1 | `15×4, 10×2, 13, 10×2, 13` | 126 / 126 | `3×2, 4×2, 5×4, 4, 5` | `ALIEN_bluekreps.bmp:750, ALIEN_lbluekreps.bmp:800, ALIEN_brownkreps.bmp:1000` | Yes |
| 57 | 1 | `20×2, 10, 20×2, 5, 10, 5` | 110 / 114 | `9×2, 4, 9×2, 4×3` | `ALIEN_bluekreps.bmp:750, ALIEN_lbluekreps.bmp:800, ALIEN_brownkreps.bmp:1000` | No |
| 58 | 3 | `20×4` | 80 / 80 | `7×4` | `ALIEN_brownkreps2.bmp:500, ALIEN_gulkreps.bmp:500` | No |
| 59 | 1 | `20×2` | 40 / 40 | `3×2` | `ALIEN_Rvinggk.bmp:750, ALIEN_Rvinggk.bmp:750` | No |
| 60 | 1 | `8×2, 15×2` | 46 / 46 | `5×2, 2×2` | `ALIEN_Rvinggk.bmp:750, ALIEN_Gvingbk.bmp:750` | Yes |
| 61 | 1 | `22` | 22 / 26 | `2` | `ALIEN_Rvinggk.bmp:750, ALIEN_Gvingbk.bmp:750` | No |
| 62 | 2 | `1×25` | 25 / 25 | `3×25` | `ALIEN_Gvingbk.bmp:500` | No |
| 63 | 6 | `10, 14, 10×7, 15, 18` | 127 / 127 | `5×11` | `ALIEN_lila_royr.bmp:1000` | No |
| 64 | 6 | `10×3, 20, 10×5` | 100 / 100 | `4×3, 2, 4×5` | `ALIEN_lblaa_royr.bmp:1000` | Yes |
| 65 | 6 | `15×5` | 75 / 79 | `4×3, 6×2` | `ALIEN_lblaa_royr.bmp:1000, ALIEN_lila_royr.bmp:1000` | No |
| 66 | 3 | `15×4` | 60 / 60 | `3×4` | `ALIEN_lblaa_royr.bmp:1000` | No |
| 67 | 6 | `20×4, 12×4` | 128 / 128 | `6×4, 5×4` | `ALIEN_lilla_makk.bmp:1000, ALIEN_lblaa_makk.bmp:1500` | No |
| 68 | 6 | `8×6, 20×4` | 128 / 128 | `4×2, 5×8` | `ALIEN_lilla_makk.bmp:1000, ALIEN_lblaa_makk.bmp:1500` | Yes |
| 69 | 6 | `15, 11` | 26 / 30 | `2×2` | `ALIEN_lblaa_makk.bmp:1000, ALIEN_lilla_makk.bmp:1500` | No |
| 70 | 2 | `5×7` | 35 / 35 | `3×7` | `ALIEN_lblaa_makk.bmp:1500` | No |
| 71 | 6 | `9×2, 10×6` | 78 / 78 | `6×2, 3×6` | `ALIEN_rocktalien.bmp:1500` | No |
| 72 | 6 | `8×4, 18×2` | 68 / 68 | `3×2, 2×2, 3×2` | `ALIEN_rocktalienG.BMP:0, ALIEN_rocktalien.bmp:1500` | Yes |
| 73 | 6 | `28×2` | 56 / 61 | `8×2` | `ALIEN_rocktalien.bmp:1500, ALIEN_rocktalienG.bmp:1500` | No |
| 74 | 3 | `40×2, 2×2` | 84 / 84 | `21×2, 5×2` | `ALIEN_rocktalien.bmp:3000, ALIEN_rocktalienG.bmp:3000` | No |
| 75 | 4 | `1×2, 16, 1×2` | 20 / 21 | `7, 43, 0, 1×2` | `ALIEN_big3_1.bmp:50, ALIEN_big3_2.bmp:50, ALIEN_big3_3.bmp:0, ALIEN_big3_4.bmp:0, ALIEN_big3_5.bmp:0, ALIEN_big3_6.bmp:0` | No |
| 76 | 6 | `16×2, 40×2` | 112 / 112 | `20×2, 3×2` | `ALIEN_Gspis.bmp:1500, ALIEN_Rspis.bmp:1500` | Yes |
| 77 | 6 | `15×6` | 90 / 90 | `3×6` | `ALIEN_Gspis.bmp:1500` | No |
| 78 | 1 | `15×4` | 60 / 64 | `11×4` | `ALIEN_Rspis.bmp:1500` | No |
| 79 | 2 | `6×6, 7×2` | 50 / 50 | `4×8` | `ALIEN_Rspis.bmp:1500, ALIEN_Gspis.bmp:2000, ALIEN_gulkreps.bmp:2000` | No |
| 80 | 1 | `10×3, 7, 9×2, 7, 9, 10, 9` | 90 / 90 | `6×2, 5, 6, 15, 14, 6, 15, 5, 14` | `ALIEN001_gul.bmp:1000, ALIEN001_raud.bmp:1000, ALIEN001.bmp:1000` | Yes |
| 81 | 1 | `10×10` | 100 / 100 | `4×10` | `ALIEN001_blue.bmp:1500, ALIEN001_raud.bmp:1500, ALIEN002.bmp:0` | No |
| 82 | 1 | `40×2` | 80 / 85 | `2×2` | `ALIEN001_gul.bmp:200, ALIEN001.bmp:0, ALIEN002.bmp:0` | No |
| 83 | 3 | `15×6` | 90 / 90 | `9×6` | `ALIEN001_raud.bmp:2000, ALIEN001.bmp:0, ALIEN002.bmp:0` | No |
| 84 | 1 | `20×7` | 140 / 140 | `3, 4, 2×4, 4` | `ALIEN_lysper2.bmp:3000, ALIEN001.bmp:0` | Yes |
| 85 | 1 | `15×2, 16, 14` | 60 / 60 | `2×4` | `ALIEN_lysper2.bmp:3000, ALIEN_lysper.bmp:3000` | No |
| 86 | 1 | `10×8, 4×4` | 96 / 100 | `11×8, 2×4` | `ALIEN_lysper2.bmp:2000, ALIEN_lysper.bmp:2000` | No |
| 87 | 2 | `6×9` | 54 / 54 | `2×9` | `ALIEN_lysper2.bmp:2500` | No |
| 88 | 6 | `10×3` | 30 / 30 | `2×3` | `ALIEN_n1_bla.bmp:2500, ALIEN_n1_gron.bmp:2500` | Yes |
| 89 | 6 | `10×4, 1×8` | 48 / 48 | `2×12` | `ALIEN_n1_bla.bmp:2500, ALIEN_n1_gron.bmp:2500` | No |
| 90 | 6 | `10×8` | 80 / 83 | `7×8` | `ALIEN_n1_bla.bmp:3000, ALIEN_n1_gron.bmp:2500` | No |
| 91 | 3 | `20` | 20 / 20 | `24` | `ALIEN_n1_lilla.bmp:5000, ALIEN_n1_bla.bmp:2000` | No |
| 92 | 6 | `8×18` | 144 / 144 | `3×18` | `ALIEN_n2_bla.bmp:3000, ALIEN_n2_red.bmp:3000` | Yes |
| 93 | 6 | `15, 18, 15×6` | 123 / 123 | `5, 2, 5×6` | `ALIEN_n2_bla.bmp:3000, ALIEN_n2_red.bmp:3000` | No |
| 94 | 1 | `20×4` | 80 / 84 | `13×4` | `ALIEN_n2_green.bmp:3000, ALIEN_n1_lilla.bmp:3000` | No |
| 95 | 2 | `6×10` | 60 / 60 | `2×10` | `ALIEN_metaballs.bmp:5000, ALIEN_metaball2.bmp:5000, ALIEN_metaball3.bmp:5000` | No |
| 96 | 1 | `18×2, 20×4` | 116 / 116 | `19×2, 10×4` | `ALIEN003_3.bmp:3000, ALIEN_RaudKule2.bmp:4000, ALIEN_kuleR.bmp:5000, ALIEN_kuleG.bmp:5000` | Yes |
| 97 | 1 | `30×2` | 60 / 60 | `2×2` | `ALIEN_kuleG.bmp:3000, ALIEN_kuleB.bmp:3000, ALIEN_kuleO.bmp:3000, ALIEN_kuleL.bmp:3000` | No |
| 98 | 1 | `15, 13, 17` | 45 / 55 | `2×3` | `ALIEN_kuleR.bmp:5000, ALIEN_kuleO.bmp:5000, ALIEN_MkuleR.bmp:50000, ALIEN_kuleL.bmp:3000` | No |
| 99 | 3 | `20×4` | 80 / 80 | `4×3, 5` | `ALIEN_n2_bla.bmp:5000` | No |
| 100 | 4 | `1×2, 4×2, 1×2` | 12 / 13 | `7, 43, 0, 2×3` | `ALIEN_big4_1.bmp:50, ALIEN_big4_2.bmp:2500, ALIEN_big4_3.bmp:0, ALIEN_big4_4.bmp:0, ALIEN_big4_5.bmp:0, ALIEN_big4_6.bmp:0` | Yes |

Every file is 117,656 bytes and reconstructs byte-identically. Resolved counts add only positive counts from supplemental records 0–3, matching the executable loop; the fifth raw record remains preserved without being treated as a spawn source.

## Authored LVD v2 and fixed table

Every `authored_lvd` block carries all 50 fixed records as exact four-word arrays. The retail consumers establish these semantics:

- Fixed record 0 word 1 supplies ordinary-enemy animation metadata.
- A supplemental spawn uses its same-index fixed record: word 0 minus one is the animation maximum and word 1 is the animation metadata/bounce flag.
- Supplemental word 2 supplies health and a divisor numerator (`word2 / 10.0`); words 3 and 4 supply timer-A initial and step values.
- Active supplemental entities occur on levels 3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61, 65, 69, 73, 78, 82, 86, 90, 94, and 98.

Level 15 has fixed record `[7, 0, 0, 0]`, so its supplemental animation reaches frame index 6. Retail selects `(384, 0, 64, 64)`; that `alien000.hma` cell contains 1,123 occupied pixels with local inclusive bounds `[0, 0, 61, 38]`.

Level 23 has supplemental record `[2, 1, 60, 1312, 29]` and fixed record `[7, 1, 0, 0]`, so two supplemental entities use all seven 64px phases with bounce metadata. The phase-6 `alien003.hma` cell contains 1,424 occupied pixels with local inclusive bounds `[2, 2, 61, 60]`.

Level 28 has supplemental record `[2, 1, 30, 560, 7]` and fixed record `[4, 0, 0, 0]`, so two `alien_rakett` supplemental entities use phases 0 through 3. The phase-3 HMA cell contains 1,044 occupied pixels with local inclusive bounds `[17, 1, 46, 61]`.

Level 32 has supplemental record `[3, 1, 40, 1076, 30]` and fixed record `[4, 0, 0, 0]`, so three `alien_baller` supplemental entities use phases 0 through 3. The phase-3 HMA statistics are pinned in the JSON evidence.

Level 36 has two active supplemental records: `[2, 2, 40, 818, 10]` selects `alien_cyan_lilla_t` and `[1, 1, 59, 968, 14]` selects `alien_green_lilla_t`; both use four animation phases. Levels 40, 44, 48, 53, 57, and 61 retain their exact same-index resource/fixed-table linkages. Late-campaign supplementals occur at levels 65 (two records), 69, 73, 78, 82, 86, 90, 94, and 98; their fixed phase counts are source-pinned at four, seven, or six as exported under `fixed_table_contract.active_supplemental_records`.

## Per-resource score table

The authored resource slot is decremented into a six-case executable switch. Each case copies the corresponding LVD tail-A word to the enemy award fields; slot 2 never falls back to slot 1. The table above and `enemy_resources` arrays pin every declared resource score through level 100, including the six-slot state-13 encounters at levels 25, 50, 75, and 100.

## Mode 3

- Mode 3 is classified with modes 2 and 4 by the bounded special-mode helper.
- The loader increments one dedicated global counter for each authored mode-3 enemy.
- The ordinary alien-shot path branches around allocation when the level mode is 3.
- Terminal opcode 6 enters state 10 only in mode 2; non-mode-2 entities are deactivated.
- After a mode-3 opcode-6 deactivation, the entity's group-total slot is cleared.

Levels 8, 16, 24, 33, 41, 49, 58, 66, 74, 83, 91, and 99 are the mode-3 instances, with 20, 30, 30, 30, 40, 40, 80, 60, 84, 90, 20, and 80 authored targets respectively. Their exact resource-slot scores are retained per LVD. Result, perfect-chain, and Warp behavior remain owned by `content/bonus_modes.json#mode_three_bonus` and `BONUS_MODES.md`.

## Enemy sources

Levels 11–12 reuse `alien_3`; levels 13–16 use `alien000`; levels 17–20 use `alien_lilla`; levels 21–24 use `alien003`, with `alien003_3` in resource slot 2 on levels 21–23. Levels 25, 50, 75, and 100 declare the six `alien_big1`, `alien_big2`, `alien_big3`, and `alien_big4` sheets respectively. Levels 26–62 introduce the rocket, baller, lilla, raudkule, blavinger, rbille, gultop, kreps, and ving families. Levels 63–74 add royr, makk, and rocktalien families; levels 76–79 use spis; levels 80–87 use the defender and lysper families; levels 88–94 use `n1`/`n2`; and levels 95–99 use metaball, kule, and reused late families. Every campaign TGA, mask TGA, and 576×96 binary HMA is byte-pinned in `classic_levels.json` and the provenance manifest.

HMA occupancy does not by itself prove broad-phase projectile rectangles. The executable HMA metadata capture and per-resource copy remain separately pinned in the presentation/runtime contract.

## State-13 boss boundaries

Level 25 is authored mode 4 with five groups, 16 authored entities, and six declared enemy resources. The completed state-13 initialization, update, collision, death, reward, and routing trace is exported as `content/bosses.json#bosses.retail_big_boss_v1`; `exact_trace_complete` is a fail-closed runtime gate.

Level 50 is the second five-group mode-4 state-13 encounter, with 14 authored metadata records plus its dedicated supplemental boss record and all six `alien_big2` resources. Its exact contract is `content/bosses.json#bosses.retail_big_boss_level_50_v1`.

Level 75 is the five-group `alien_big3` encounter and level 100 is the mirrored six-group `alien_big4` terminal encounter. Their exact contracts are `retail_big_boss_level_75_v1` and `retail_big_boss_level_100_v1` in `content/bosses.json`.

Late ordinary modes include mode 6 on levels 63–65, 67–69, 71–73, 76–77, 88–90, and 92–93; mode 1 on levels 78, 80–86, 94, and 96–98; and mode 2 on levels 70, 79, 87, and 95. Late mode-3 levels are 66, 74, 83, 91, and 99; levels 75 and 100 are mode 4. Presentation uses `stars1` for 1–25, `stars2` for 26–50, `stars3` for 51–75, `stars4` for 76–99, and the retail remainder mapping `stars1` at 100. The authored every-fourth-level shop flag continues through level 100; terminal level-100 routing suppresses a reachable post-boss shop. Each mode-3 post-Warp shop remains separately owned by `bonus_modes.json#mode_three_bonus`.

## Boundary

The legacy `waves` arrays are predecessor-read compatibility data and are not original-game evidence. Version 9 authored play reads `authored_runtime.ordinary_speed_fp`; changing a compatibility wave cannot change an authored entity. Tail array A is named as a kill-score table only where the pinned resource-switch trace proves it; tail B remains raw. Bonus-mode results, presentation selection, and route exposure have separate owners.
