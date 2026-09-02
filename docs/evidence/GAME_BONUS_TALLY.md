# End-of-game GAME BONUSES tally

Executable-backed contract for the terminal bonus tally, the retire
command, and the Duel winner rule. Extracted from the pinned retail
executable `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`.

## Owning functions

| Role | VA |
| --- | --- |
| game_over_sequencer | `0x005aafa0` |
| tally_seed | `0x00568f00` |
| tally_accumulator | `0x005529b0` |
| tally_renderer | `0x00596dd0` |
| duel_winner_banner | `0x00596a70` |
| rank_table_initializer | `0x007757e0` |
| retire_menu_builder | `0x00549ed0` |

## Contract

- CASH LEFT contributes money x 100 points.
- Each perfect bonus round contributes 100000
  points; the perfects counter is the per-player perfect-rounds value.
- HIT PERCENTAGE is `round(hits * 100 / max(shots, 1)) clamped to 100` and
  contributes 1000 points per percent.
- RANK BONUS is the cumulative sum of the rank bonus table from index
  1 through the player's rank index; the renderer prints the rank
  name from the same 33-entry jumptable.
- SUM BONUS POINTS is the sum of the lines above; TOTAL SCORE is
  `raw score + SUM BONUS POINTS`.
- Profile statistics record the raw score before the tally; the
  hall-of-fame consumer sees the total.
- Duel: higher raw score + bonus sum wins; equality is a draw.
- Retire: the pause-menu retire command ends the run through the same game-over sequencer: raw-score profile statistics, then the tally.
- MAX CASH BONUS (50000000) is
  unreachable: the arming counter is seeded to -1 and no retail code path raises it, so the branch never triggers. It is
  preserved as evidence and the remake implements no reachable path
  for it.

## Rank bonus table (index 1-32 consumed)

| Index | Points |
| ---: | ---: |
| 0 | 10000 |
| 1 | 20000 |
| 2 | 30000 |
| 3 | 40000 |
| 4 | 50000 |
| 5 | 60000 |
| 6 | 70000 |
| 7 | 80000 |
| 8 | 90000 |
| 9 | 100000 |
| 10 | 200000 |
| 11 | 300000 |
| 12 | 400000 |
| 13 | 500000 |
| 14 | 600000 |
| 15 | 700000 |
| 16 | 800000 |
| 17 | 1000000 |
| 18 | 2000000 |
| 19 | 3000000 |
| 20 | 4000000 |
| 21 | 5000000 |
| 22 | 10000000 |
| 23 | 10000000 |
| 24 | 10000000 |
| 25 | 10000000 |
| 26 | 10000000 |
| 27 | 10000000 |
| 28 | 10000000 |
| 29 | 10000000 |
| 30 | 10000000 |
| 31 | 10000000 |
| 32 | 50000000 |

## Reproduction

```sh
python3 tools/game_bonus_tally_extract.py
python3 tools/game_bonus_tally_extract.py --check
python3 tools/game_bonus_tally_test.py
```
