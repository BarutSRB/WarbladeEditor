# Profile locks

Executable-backed contract for the retail profile lock system: the
start-with awards evaluated when a solo or Time Trial match starts
with an open profile. Extracted from the pinned retail executable
`ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`.

| Role | VA |
| --- | --- |
| start_state_applier | `0x0054d440` |
| locks_screen | `0x0054a260` |
| grouped_best_getter | `0x005465d0` |

## In-the-game score tiers

| Threshold | Effect | Value |
| ---: | --- | ---: |
| 5000000 | bullet_capacity | 10 |
| 7500000 | speed_steps | 3 |
| 10000000 | auto_fire | 1 |
| 20000000 | weapon_at_least | 1 |
| 50000000 | armour_charges | 1 |
| 100000000 | money | 500 |
| 250000000 | money | 1000 |
| 500000000 | armour_charges | 2 |
| 1000000000 | weapon_at_least | 2 |

## Grouped best tiers (level-100 / Time Trial / Meteor Storm)

| Threshold | Effect | Value |
| ---: | --- | ---: |
| 5000000 | score_multiplier | 2 |
| 6000000 | scoop | 1 |
| 7000000 | score_multiplier | 5 |
| 8000000 | auto_fire | 1 |
| 9000000 | speed_steps | 3 |
| 10000000 | speed_steps | 5 |
| 15000000 | super_auto_fire | 1 |
| 17000000 | speed_steps_max | 1 |
| 20000000 | time_trial_extra_minute | 1 |

## Games-played tiers

| Threshold | Effect | Value |
| ---: | --- | ---: |
| 1000 | autofire_through_shop | 1 |
| 2500 | missile_stealth | 1 |
| 5000 | gem_counter_on | 1 |
| 10000 | single_shot_bonus_off | 1 |
| 15000 | double_shot_bonus_off | 1 |
| 20000 | only_blue_coins | 1 |
| 25000 | triple_shot_bonus_off | 1 |
| 35000 | meteor_multiplier_enabled | 1 |
| 50000 | weapon_at_least | 3 |
| 75000 | bullet_speed_up | 1 |
| 100000 | good_start_package | 1 |

## Fastest Meteor Storm locks (milliseconds)

| Threshold | Effect | Value |
| ---: | --- | ---: |
| 2000 | extra_time_max | 60 |
| 1000 | extra_time_max | 90 |

## Other locks

- Hit-rate shop unlocks: 70/80/90 percent above level 25 unlock shop
  items 18/19/20 (already implemented and tested).
- Find all secrets (30): full armour, or 2,000 cash when armour is
  already full, plus at least Super Triple Shot.
- Above 200,000,000: the secret counter display starts on.
- Rank 32 (WARBLADE GOD SOL): the undocumented terminal package —
  maximum bonus time, 25,000 cash, raised bullet speed, weapon 8,
  Super Auto Fire, and 25 bullets.
- The 100,000-games package: half-maximum speed steps, 25 bullets,
  half-maximum bonus time, and 5,000 cash.

## Interpretation notes

- The locks screen groups the level-100, Time Trial, and Meteor Storm bests under one tier list; the applier's Time Trial branch reads the grouped best through getter 0x005465d0. The remake evaluates the group against the maximum of the three stored bests.
- Flag-style tiers apply at their behavior sites: shop exit keeps autofire, the drop selector skips excluded single/double/triple entries, coins spawn blue-only, and the Meteor Storm multiplier gate opens.
- Easy profiles keep their reduced rank cap; ranks above the cap and their locks stay unreachable on that profile.

## Reproduction

```sh
python3 tools/profile_lock_extract.py
python3 tools/profile_lock_extract.py --check
python3 tools/profile_lock_test.py
```
