# Bonus-mode contracts

`content/bonus_modes.json` is generated from bounded regions of the pinned Warblade 1.34 executable and byte-verified original assets.

Regenerate with `python3 tools/bonus_modes_extract.py`; verify with `python3 tools/bonus_modes_extract.py --check`.

## Recurring mode-three levels

The canonical `mode_three_bonus` contract binds all twelve retail mode-three levels: 8, 16, 24, 33, 41, 49, 58, 66, 74, 83, 91, and 99. Their exact target/score pairs are 20/200, 30/100, 30/200, 30/500, 40/500, 40/750, 80/500, 60/1000, 84/3000, 90/2000, 20/5000, and 80/5000. These values are slot-1 evidence aliases; per-resource LVD scores remain authoritative for kills. All twelve levels own per-session projectile-owner hit, displayed-hit, and perfect one-shot counters; reveal 500 × score multiplier per hit; share the persistent 10,000 … 10,000,000 perfect chain; and enter their recurring shop after the Warp/result route. Each mode-three shop is separate from the ordinary every-fourth-level `shop_after` cadence. `level_8_bonus` remains an explicit synchronized legacy projection.

## Memory Station and Meteor Storm

Both originating controllers are represented by exact RNG ranges, progression constants, reward tables, timing, collision geometry, and source-backed presentation assets. The rank-0 `memorystation` and `meteorstorm` announcements are canonical voice assets, not SFX inventory entries. Memory gem tiles play `bell1` before two progress probes; Meteor gem pickups perform five probes before their common `bonus`/`bell1` tail.

## Gem Drop

A progress threshold terminally abandons Memory Station or Meteor Storm, runs the pinned RNG-consuming shared pool reset, initializes ten inactive `diamantbig` slots with 30 additional draws, switches to `gems`, and enters state 18. Standard ship movement and primary-fire allocation continue through the exact 4,000-ms intro, but state 18 does not advance ordinary projectiles. The active controller grows and recycles the pool, resolves strict AABB plus HMA collisions per seat, pays ordinary or Super color rewards, and exits only after the 2,680 scalar becomes strictly negative. It never restores the originating minigame.

## Rank promotion

Ranks 1–20 contain 103 executable-traced queued cues. The bonus modes and promotion queues use 26 byte-pinned voice-pack-1 files, including Memory's one-through-ten countdown. Padding values are retained per cue.

## Pinned evidence

- Executable SHA-256: `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`
- Bounded executable regions: 51
- Bonus presentation assets: 17

All mode-three reward, counter, result, Warp, and shop semantics exported for the twelve campaign occurrences through level 99 are exact and closed.
