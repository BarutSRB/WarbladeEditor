# Retail HUD Layout Static Trace

This document pins the retail sidebar/HUD layout consumed by
`src/client/hud_overlay.gd`. It combines bounded static analysis of retail
`warblade.exe` (SHA-256 `ddf1778c…d079ef`, the same image as
`difficulty_rules.json`) with the retained retail level-1 screenshot
(`runtime_level1_paused.png`, macOS title-bar offset 28 px).

## Top-center scores (0x005d88a0-0x005d89d3)

The abcd_3 renderer (`0x005cfcd0`) draws two rows balanced around x=400 by
digit count (6 px per digit). The renderer colour argument is the abcd_3 atlas
bank row (9 px rows): 1 = green, 2 = white, 5 = orange.

| Element | Formula | Colour bank |
| --- | --- | --- |
| `HISCORE` label | x = 400 − 6·digits − 60, y = 2 | 2 (white) |
| hiscore value | x = 400 − 6·digits + 36, y = 2 | 5 (orange) |
| `PL1` label | x = 400 − 6·digits − 36, y = 14 | 2 (white) |
| score value | x = 400 − 6·digits + 12, y = 14 | 1 (green) |

The hiscore value updates live when the run score overtakes it
(0x005d88be-0x005d88ef).

## Side rails (0x005d59f0-, per-player call with rail base x=32)

Player one's info is on the left rail, player two's on the right (manual
"On each side of the screen there is a border…"):

| Element | Position | Source art |
| --- | --- | --- |
| Money `$%d` (unpadded) | right-aligned ending x=32, y=2, small text (4 px advance) | abcd_2 style 3 (green) |
| Reserve fighters | x=24, y=22 + 10·i, 16×10, max 4, active fighter hidden | `div.tga` (0,0,16,10) |
| Points multiplier | x=24, y=68, shown while x2/x5 is active | `div.tga` (16,0,16,10) / (32,0,16,10) |
| EXTRA letters | x=22, y=85 + 21·k, one 20×20 tile per collected letter | `bonuses.tga` (60, 60+20k, 20,20) |
| Rank marks | six coloured pips below the letters | `marks.tga` 20×20 colour cells |
| Armour | at most two charges | `div.tga` colour squares |
| S/B/T bars | letters at x≈2, bars from x=7 (S blue y=279, B red y=286, T green y=293) | `div.tga` strips (51,22/28/34,45,5) |
| Wide gauge | x=9, y=331, 46×9 track | bonus-time remaining fill |
| `LEVEL` + digits | label x=7, y=580 (abcd_2 style 3); 4 zero-padded digits x=14, y=589 | numbers atlas green bank |

S fills from the fighter speed between the difficulty base and cap
(base + 16 upgrades); B fills as bullet capacity out of the 50 maximum; T and
the wide gauge fill as bonus time out of the 45-second maximum.

## Pause (retail screenshot + assets)

Retail dims nothing: the 252×128 magenta `pause3.tga` art rotates 90°
clockwise onto the playfield centre and the game stays visible behind it.

## Evidence boundary

The money/small-text renderer at 0x005d0ed0 is proven to use a 4 px advance
(the money right-align caches `strlen × 4`). The wide-gauge fill ratio and the
exact rank-mark pip art slicing remain best-effort placements from the
retained screenshot; both are marked for future executable pinning rather than
claimed as proven.
