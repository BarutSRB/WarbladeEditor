# Warblade .lvd Schema Cheatsheet

The `.lvd` blobs inside `Warblade/data/warblade.pac` are fixed-size (0x1cb98-byte) files composed of 32-byte records (8 little-endian signed integers). The loader at `fcn.0019f1a0` copies contiguous record ranges into specific runtime structures. This note captures the layout we currently rely on for tooling.

- **Machine-readable schema:** `schemas/warblade_lvd_sections.schema.json` mirrors everything described here (start/end blocks, record counts, per-field names, news asset padding). Editor tooling can ingest it directly.
- **Validator:** `scripts/validate_warblade_lvd.py` loads the schema and runs a lightweight checker so edited JSON stays within spec.

## High-Level Sections

| Section | Record Blocks | Count | Notes |
| --- | --- | --- | --- |
| `header` | 0–1 | 2 | Difficulty, RNG seed, misc flags. |
| `header_reserved` | 2 | 1 | Spare 32-byte record left over from the loader; a few challenge `.lvd`s stash feature flags here. |
| `enemy_formations` | 3–1285 | 1,283 | 0x54c-byte chunks copied to `0x803CA0`. Each group of 6 records represents one formation row. |
| `shop_inventory_imda_header` | 1286 | 1 | `'IGDA'` signature + 0x4C record-size marker that precedes the shop chunks. |
| `shop_inventory_chunk_[0-5]` | 1287–1764 | 6 × {14} | 14 records per chunk feed the 0xb04a50 shop table. Field semantics are described in `continue.md`; validation lives in `schemas/warblade_shop_tables.schema.json`. |
| `shop_inventory_chunk_[0-5]_tail` | 1301–1766 | mixed | IGDA remainder metadata (2–13 records per chunk) that gate pagination, scripted rewards, and UI switches. Still surfaced as raw ints for now. |
| `event_table_[0-18]` | 1849–3540 | mixed (2–4 each) | Scheduling metadata consumed by `fcn.001defe0`/`fcn.001df6e0`. Records are now emitted as dictionaries with semantic keys (see below). |
| `promotion_banner_paths` *(event_table_1_aux)* | 1946–1956 | 11 | Screen-space splines for the rank/promotion banners that fly toward the scoreboard. |
| `meteor_arc_paths` *(event_table_2_aux)* | 2040–2043 | 4 | Entry/exit lanes used when the meteor storm minigame spawns debris and HUD meters. |
| `boss_callout_paths` *(event_table_3_aux)* | 2133–2139 | 7 | Camera/HUD trajectories for boss warnings and scripted set pieces. |
| `event_table_4_header` / `event_table_8_header` | 2224 / 2599 | 1 each | Single-record prologues that precede those event tables. |
| `rank_marker_gates` *(event_table_4_aux)* | 2227–2235 | 9 | Boolean/timer gates that toggle the on-screen rank markers. |
| `reward_ribbon_paths` *(event_table_5_aux)* | 2321–2336 | 16 | Grid-aligned splines that drive reward ribbons and shop freebies during intermissions. |
| `hud_flash_counters` *(event_table_6_aux)* | 2415–2416 | 2 | Minimal counter/timer pair that keeps HUD flashers in sync with the reward queue. |
| `news_ticker_globals` | 1853–1856 | 4 | Counter + layout data for the “NEWS1–NEWS4” ticker. Copied into `0xb03e10` before `fcn.00144d10` / `fcn.0018f550` consume it. |
| `news_asset_blob` | 3632–3639 | 8 | Packed ASCII (256 bytes) with the `.bmp` names the ticker cycles through (`ALIEN_big2_*.bmp`, etc.). |
| `news_ticker_runtime_shadow` | 3651–3652 | 2 | Backup copies of the ticker counters (mirrors the globals at `0xe114fc`..`0xe11528`). |
| `footer_metadata` | 3631 | 1 | Level checksum / version marker. |
| `footer_unlock_flags` | 3650 | 1 | Bitfield copied to profile data. |
| `footer_slot_counts` | 3675 | 1 | Number of populated shop slots (mirrors runtime 0xb04a50 state). |

The remaining `remainder` list should be empty now; if it isn’t, a new section needs to be mapped in `SECTION_LAYOUT`.

## Header Block

`header` occupies the first two records and decodes into the knobs the loader feeds into the global startup structs.

| Key | Notes |
| --- | --- |
| `version_id` | Format/difficulty preset identifier (observed `1`). |
| `mode_id` | Level mode selector (0 = classic, others TBD). |
| `seed_word_0` | Low word of the RNG seed passed to `fcn.00125c12`. |
| `seed_word_1` | High word of the RNG seed. |
| `difficulty_mask` | Bitmask that gates which difficulty tiers present the level. |
| `starting_lives` | Number of lives granted on entry; matches UI defaults. |
| `starting_credits` | Continue counter seed. |
| `reserved_word` | Padding (still zero in stock files). |

### Header Reserved Record

Block `2` is technically part of the header chunk as well. Stock classic levels leave the entire record zeroed, but the loader still copies the 8 words into an address right after the seed struct. When decoding we expose it as `header_reserved` so future feature flags (e.g., alternative timeline scripts) can live there without falling back to the raw `remainder` mechanism.

## Shop Tables

The four static shop arrays (`0x7d07b0`..`0x7d0a40`) provide base price, stock, per-sale limit, spawn quantity, and category ID for each of the 0x25 player-facing slots. Indices ≥37 are sentinels that drive scripted rewards, so the JSON schema marks them as `readOnly` to keep editors from touching them.

Schema file: `schemas/warblade_shop_tables.schema.json`

## Shop Inventory Entries (derived)

The raw `shop_inventory_chunk_[0-5]` blocks are emitted as the `shop_inventory` section for easier editing. Each entry is the 0x4C-byte structure the loader copies into `0x847720` before the shop UI (`fcn.001dfee0`, `fcn.001e0030`, etc.) consumes it.

| Key | Notes |
| --- | --- |
| `slot_state` | Zeroed slots stay hidden; writers set it to 1 when enabling an offer. |
| `page_id` | Negative values pin hard-coded reward pages; positive IDs map to shop tabs. |
| `category` | Item grouping (ties into `item_id`). |
| `price_primary` / `price_secondary` | Credits / alt currency price ladders. |
| `stock_count` / `stock_alt` | Default stock and the alternate/restock count. |
| `ui_column` | Column index in the shop grid. |
| `ui_pos_x` / `ui_pos_y` | Pixel offsets for the entry badge. |
| `ui_width` / `ui_height` | Hit-box dimensions; still zero for unused slots. |
| `icon_id` / `icon_variant` | Sprite table indices for the widget artwork. |
| `item_id` | Game item / reward identifier. |
| `item_arg_0` / `item_arg_1` | Extra parameter slots (weapon rank, bundle size, etc.). |
| `unlock_req` | Requirement flag (promotion rank, story gate, etc.). |
| `reserved_word` | Padding to keep the struct 0x4C bytes; presently unused. |

### IGDA Shop Chunk Metadata (chunk tails)

The six shop chunks are wrapped inside one long IGDA container: block `1286` stores the `'IGDA'` signature and the 0x4C record-size marker the retail tools used when emitting the data. After each 14-record chunk the blob carries 2–13 extra records (`shop_inventory_chunk_[0-5]_tail`) that act as pagination/gating metadata. These fields are still being traced (addresses `0xb04aa0`, `0xe11910`, etc.), so the parser surfaces them as raw `word_0`..`word_7` lists for now. Editors should leave them untouched until the semantic mapping is complete—the validator watches the IGDA header to make sure the signature (`0x49474441` or `0x4e594157`) and the 0x4C size stay intact.

## Enemy Formations

`enemy_formations` covers the 1,283 32-byte records the loader copies into `0xa95cb0`. Each record now decodes to:

| Key | Notes |
| --- | --- |
| `spawn_delay_start` | Frames before the first enemy in the group can spawn. `fcn.00169260` subtracts this from the normalized timeline (see `fisub [0xa95cb0]`). |
| `spawn_delay_increment` | Additional jitter applied when the same slot is reused during cascades. |
| `spawn_delay_secondary` | Second-stage delay used when a pattern re-enters (e.g., mirror waves). |
| `spawn_window_secondary` | Companion to the secondary delay; acts as the time window for respawns. |
| `offset_x` | Horizontal offset in screen units (negative values place the swarm off-screen before entry). |
| `offset_y` | Vertical offset. |
| `enemy_type` | Index into the enemy-definition tables touched inside `fcn.0015aa10`. |
| `behavior_flags` | Flags / variant selector. Values ≥10 correspond to scripted boss or bonus spawns. |

These four timing fields feed the clamp/normalize math in `fcn.00169260` (writes to `0x849a78`..`0x849a68`), while the final four integers describe spatial offsets and the `enemy_type`/`behavior` pair the renderer uses when instantiating the hazard.

## Event Queue Rows

`event_table_*` sections feed the 0xd5e358 scheduler that `fcn.001df6e0`/`fcn.001eb550`/`fcn.0021fff0` manipulate. Each `.lvd` record (8 words) now decodes to a dictionary using the first eight fields of the runtime struct:

| Key | Offset | Meaning |
| --- | --- | --- |
| `in_use_flag` | +0x00 | Should be zero in the file; runtime uses it when seeding the slot. |
| `spawn_delay_frames` | +0x04 | Frame countdown before the event goes live. |
| `owner_id` | +0x08 | Script or profile index that owns the event. |
| `table_index` | +0x0C | Row selector for the `0x7cd340/0x7cd458/0x7cde30` tables. |
| `normalized_progress` | +0x10 | Fixed-point progress seed (normally 0). |
| `base_delta` | +0x14 | Duration seed used to scale RNG jitter. |
| `event_stage` | +0x18 | Stage number / type selector. |
| `event_stage_secondary` | +0x1C | Secondary stage counter (multi-wave events). |

The remaining runtime fields (child handles, timers, HUD blink state, etc.) are derived at load time and therefore omitted from the file. When encoding, the tool honors whatever integers the editor provides for these keys and writes them back in order, ensuring round-trips stay lossless even though the JSON is now human-readable.

### Event Table Aux Ranges

The first six event tables each carry a follow-up IGDA block. The parser now surfaces them under friendly names (with the legacy `event_table_*_aux` labels still accepted when encoding); the metadata retains a `source_section` field to track the original raw name. `event_table_8` also keeps its one-record IGDA header at block `2599` even though the other tables lack one.

These rectangles hold the UI bounds, cooldown timers, and state-machine switches that `fcn.001df6e0` copies into `0xd5e398` right after the main 8-word rows. Each record is emitted as:

| Key | Meaning |
| --- | --- |
| `origin_x` / `origin_y` | Pixel-space launch point for the HUD element / projectile. Negative values place it off-screen. |
| `target_x` / `target_y` | Pixel-space destination used by the lerp caretakers. |
| `velocity_x` / `velocity_y` | Delta applied each frame while the caretaker walks toward the target. |
| `timer_primary` | Frame countdown before the segment is allowed to run (also reused as a scoreboard slot selector for some tables). |
| `timer_secondary` | Secondary cooldown / blink counter that the caretakers decrement in `fcn.0021fff0`.

The fixed record counts above map to specific gameplay subsystems, so editors can tweak only the section they care about instead of wading through anonymous blocks. Field order always stays `{origin_x … timer_secondary}`; the subsections below explain how each subsystem interprets those values and list the `segment_name`s that now show up in decoded JSON when we have good coverage.

### Promotion Banner Paths (`event_table_1_aux`)

`fcn.001df6e0` feeds these coordinates into the promotion caretaker (`fcn.0021fff0`). It walks eleven segments in order; we now tag each one with a descriptive `segment_name` so editors know which portion of the animation they are touching.

| Id | `segment_name` | Behavior / HUD usage | Field hints |
| --- | --- | --- | --- |
| 0 | `vertical_pre_roll` | Drops the ribbon from its spawn height down to the scoreboard baseline while the scoreboard slot arms. | `velocity_x = 0`, `velocity_y 0..100`, `timer_secondary 0..320`. |
| 1 | `column_alignment_gate` | Slides horizontally to the scoreboard column before the banner becomes visible. | `target_x 0..59`, `velocity_x -26..269`, `timer_secondary 0..100`. |
| 2 | `backdrop_swing` | Pulls the ribbon backward/off-screen to set up the diagonal swoop. | `velocity_y -333..0`, `timer_primary -320..102`. |
| 3 | `slot_anchor_offset` | Locks the scoreboard slot and cached offsets prior to rendering text. | `target_y -589..128`, `velocity_x 0..6`. |
| 4 | `diagonal_swoop` | Fast diagonal move that lands on the scoreboard entry. | `velocity_x`/`velocity_y` hit `±640`, `target_y = 100`. |
| 5 | `linger_jitter` | Small jitter while the scoreboard flashes. | `velocity_y 0..16`, `timer_secondary -13..230`. |
| 6 | `scoreboard_snap` | Micro-adjustment to perfectly center the ribbon inside the scoreboard cell. | `target_y 0..256`, `velocity_x -256..0`. |
| 7 | `return_buffer` | Moves caretakers back to neutral so the next banner starts cleanly. | `origin_x`/`origin_y` dip to `-282`, velocities approach 0. |
| 8 | `flash_hold` | Holds position while the scoreboard flash routine finishes. | `timer_secondary 0..358`, coordinates stay fixed. |
| 9 | `diagonal_exit` | Sends the ribbon back off-screen once the flash expires. | `velocity_x = velocity_y = -384`. |
| 10 | `fade_out_clamp` | Final clamp that lets alpha fade without moving the sprite. | Timers drop to zero; coordinates remain on the scoreboard cell. |

### Meteor Arc Paths (`event_table_2_aux`)

The meteor-storm minigame uses four segments; we expose them with the following names.

| Id | `segment_name` | HUD element | Notes |
| --- | --- | --- | --- |
| 0 | `entry_lane` | Rock spawn lane along the top of the storm. | `origin_y 0..6`, `target_y 0..100`, `velocity_x -282..0`, `timer_primary 0..1`. |
| 1 | `hud_speed_meter` | Speed/distance meter next to the ship. | `origin_y` up to `358`, `target_x` up to `294`, `timer_secondary` as low as `-269` to offset the percentage text. |
| 2 | `abort_lane` | Emergency exit path when the player bails early. | Coordinates hug the origin, `velocity_x -320..0`, `timer_secondary 0..16`. |
| 3 | `cooldown_gate` | Resets the HUD once the storm finishes. | Coordinates zeroed; only `velocity_x 0..100` matters. |

### Boss Callout Paths (`event_table_3_aux`)

Seven segments drive the “WARNING / BOSS APPROACHING” overlays and the accompanying camera pans.

| Id | `segment_name` | HUD widget | Notes |
| --- | --- | --- | --- |
| 0 | `warning_left_slide` | Left-hand banner. | `origin_x` dips negative, `velocity_x` peaks near `100`, sliding the overlay in from the left. |
| 1 | `camera_pan_left` | Camera nudge to show the boss entry lane. | `target_x` drops to `-640` and `timer_secondary` climbs to `+640`, matching the camera offset used by `fcn.0018f550`. |
| 2 | `warning_center_slide` | Center text shimmy. | `origin_x -435..269`, `target_y` up to `27`, letting the warning settle in the middle. |
| 3 | `warning_right_slide` | Right-hand banner. | Mirrors segment 0 but with positive `target_x` (up to `461`). |
| 4 | `blink_gate_a` | First blink toggle. | Coordinates stay near zero; only the timers (0/1) matter, gating the warning flash. |
| 5 | `blink_gate_b` | Secondary blink toggle for alternative boss scripts. | Same behavior as segment 4 but offset in time. |
| 6 | `linger_counter` | Keeps the warning on-screen while the boss spawns. | `timer_primary 0..100`; once it reaches zero the caretakers dismiss the overlays. |

### Rank Marker Gates (`event_table_4_aux`)

The scoreboard/rank HUD at `0x0afb938` consumes these nine records before drawing the “NEXT RANK” widgets. The caretakers treat each entry as a latch: `timer_primary` acts as the gate/enable, `origin_*` bits indicate which slots are already filled, and non-zero `velocity_*` fields select the blink axis. Record `8` is the only one that drives `target_y` all the way to `100`, which is the sentinel for “draw at full height”.

| Id | `segment_name` | Purpose | Notes |
| --- | --- | --- | --- |
| 0 | `required_mark_gate` | Global requirement and flash duration. | `origin_x` stores how many unique marks the player must bank (retail data uses `6`); `target_x` selects the scoreboard column and `timer_secondary ≈ 100` frames keeps the toast visible. A non-zero `velocity_y` tells the HUD to pulse vertically. |
| 1 | `slot_0_marker_gate` | Left-most rank marker slot. | `origin_y`/`target_y` reflect whether this slot is already lit when the level loads, while `timer_primary` lets scripted promotions pre-arm it. |
| 2 | `slot_1_marker_gate` | Second slot (reading order). | Shares the same format as slot 0. Observed descriptors set `timer_primary = 1` whenever the slot should be “always on” for that level. |
| 3 | `slot_2_marker_gate` | Third slot. | Uses `target_y = 1` to request a vertical blink; the caretakers reuse that bit when picking which of the six colored sprites to flash. |
| 4 | `slot_3_marker_gate` | Fourth slot. | `origin_x = 1` nudges the sprite to the right-hand column, while `velocity_y = 1` keeps the blink vertical so it lines up with the tall HUD border. |
| 5 | `slot_4_marker_gate` | Fifth slot. | `target_x = 1` and `timer_secondary = 1` introduce a one-frame offset so the blink alternates with slot 3. |
| 6 | `slot_5_marker_gate` | Sixth slot. | Only entry that sets `velocity_x = 1`, forcing a horizontal flash for the last colored marker. |
| 7 | `full_set_latch` | Fires once all six colored markers are banked. | `origin_y` mirrors the aggregate state, while `timer_primary` transitions from `0` → `1` to tell the HUD it can show “NEXT RANK READY”. |
| 8 | `full_height_flash_gate` | Expands the HUD toast to its tallest variant. | `target_y = 100` is the sentinel the renderer checks before drawing the tall capsule graphic; other fields stay zero. |

### Reward Ribbon Paths (`event_table_5_aux`)

The intermission ribbon UI (`fcn.001f3d60`, `fcn.001f4210`) reads these sixteen entries whenever the player earns freebies. Coordinates live in a `0–38` HUD-space grid so they line up with the tilemap and scoreboard text.

| Id | `segment_name` | Purpose | Notes |
| --- | --- | --- | --- |
| 0 | `carousel_anchor_top_left` | Top-left tile of the ribbon carousel. | `velocity_y = 1` establishes the baseline drop animation. |
| 1 | `carousel_anchor_top_right` | Top-right tile. | `target_x = 1` and `timer_secondary = 1` push the sprite to the next tile while delaying its flash by one frame. |
| 2 | `carousel_anchor_bottom_left` | Bottom-left tile. | Only anchor with `velocity_x = 1`, making it the horizontal counterpart to record 0. |
| 3 | `carousel_anchor_bottom_right` | Bottom-right tile. | `origin_y = 1` plants it on the lower row so the carousel can fan outward. |
| 4 | `expand_vertical_gate` | Opens the carousel vertically. | `target_y = 1` sets the row delta; velocities stay at zero so the caretakers rely on the timers. |
| 5 | `expand_horizontal_gate` | Opens the carousel horizontally. | `origin_x = 1` and `velocity_y = 1` pull the ribbon toward the right edge. |
| 6 | `collapse_horizontal_gate` | Collapses the horizontal span. | `target_x = 1` plus `timer_secondary = 1` retract the animation along X. |
| 7 | `collapse_vertical_gate` | Collapses the vertical span. | `velocity_x = 1` mirrors the behavior from record 6 but along Y. |
| 8 | `scoreboard_sync_gate` | Keeps the ribbon aligned with the scoreboard toast. | `origin_y = 100` is treated as “full height”; caretakers zero it once the scoreboard finishes flashing. |
| 9 | `reserved_slot_9` | Reserved placeholder. | Stock `.lvd` files leave it zeroed; preserve the record so the loader’s pointer math stays valid. |
| 10 | `reserved_slot_10` | Reserved placeholder. | Same guidance as record 9. |
| 11 | `reserved_slot_11` | Reserved placeholder. |  |
| 12 | `reserved_slot_12` | Reserved placeholder. |  |
| 13 | `reserved_slot_13` | Reserved placeholder. |  |
| 14 | `reserved_slot_14` | Reserved placeholder. |  |
| 15 | `reserved_slot_15` | Reserved placeholder. |  |

`timer_primary`/`timer_secondary` continue to act as grow/shrink toggles. Keeping them within `0–1` avoids pushing the caretakers out of the intended 38-pixel grid.

### HUD Flash Counters (`event_table_6_aux`)

Two global counters keep the HUD flashes in sync with the ribbon/rank caretakers. They live right next to the ribbon paths inside the `.lvd`, so editors can tweak durations without browsing raw remainder blocks.

| Id | `segment_name` | Purpose | Notes |
| --- | --- | --- | --- |
| 0 | `rank_flash_timer` | Global flash duration for rank markers / promotion banners. | `origin_y` is the number of frames to keep flashing (0–6 in stock data). `timer_primary` toggles the on/off latch. |
| 1 | `reward_flash_timer` | Flash duration for the reward ribbon carousel. | Same layout as record 0; the caretakers decrement it separately so promotions and freebies can run different flash lengths. |

## News Ticker Blocks

Four dedicated sections drive the in-game “Warblade News” system that lives at `0xb03e10` (ASCII buffer) and `0xe114fc`..`0xe11528` (counters/timers):

- `news_ticker_globals` (blocks `1853`–`1856`): four caretaker records that reuse the `{origin_x … timer_secondary}` layout from the HUD aux tables. `fcn.00144d10` copies them into the same scratch buffer it uses while parsing the `NEWSx:` strings, and `fcn.0018f550` consumes the normalized values while animating the ticker. Classic levels only seed `news_slot_1`/`news_slot_2`; time trials populate all four slots so the ticker can scroll in/out of the score HUD.
- `news_asset_blob` (blocks `3632`–`3639`): 8 contiguous 0x20-byte chunks that now decode into a friendly list of `{filename, padding}` entries. Each `padding` array captures the exact bytes (usually zeros/control codes) that appear before the filename so editors can reposition the bitmap list without breaking alignment. A `trailing_padding` list preserves the tail bytes after the last filename, ensuring round-trips stay bit-accurate.
- `news_ticker_runtime_shadow` (blocks `3651`–`3652`): mirror of the caretakers that lets the game persist per-slot scroll/fetch counters back to profile data. The runtime writes the same `{origin..timer}` tuple back out when saving a level or profile snapshot, so editors may leave it zeroed unless they need deterministic news state.

These blocks tie back to the research notes in `continue.md` (addresses `0xb03e10`, `0xe114fc`, `0xe1150c`, `0xe11524`, etc.). Having them mapped in the schema means editors can tweak the ticker data without hex editing.

### News Ticker Globals (`news_ticker_globals`)

Each record controls one ticker slot (mirrors the in-game `NEWS1`–`NEWS4` rows). The caretakers reuse the HUD field order, so editors can repurpose the slot just like the promotion/meteor/boss tables: place it via `origin_*`, decide how fast it scrolls via `velocity_*`, and gate visibility/timers via the `timer_*` fields.

| Id | `segment_name` | Purpose | Notes |
| --- | --- | --- | --- |
| 0 | `news_slot_1` | Primary news row shown along the top border. | `origin_y` stays near `0`; setting `timer_secondary = 0/1` toggles whether the slot is armed when the level loads. |
| 1 | `news_slot_2` | Secondary row / alternate overlay. | Retail data pushes `origin_y` to `100` so the line hugs the lower HUD rail. `timer_primary` doubles as a dwell timer before the caretakers advance to slot 3. |
| 2 | `news_slot_3` | Off-screen staging lane. | Left at zero in stock classic levels; time trials move it to `origin_x = -320` / `target_y = 16` to pull the ticker off-screen before resetting scroll counters. |
| 3 | `news_slot_4` | Cooldown + click debounce. | Ships with `origin_x = 100`, `target_y = 1` in the time-trial data, which matches the click hotspot timing enforced by `fcn.0018f550`. Leave it zeroed to inherit the built-in cooldown logic. |

The runtime shadow mirrors the four records verbatim. Most levels leave it zeroed, but saving a profile after toggling the news ticker will spill the live caretaker state into these two records. Editors can either preserve them or zero them out to let the game rebuild the counters on load.

### News Asset Blob (`news_asset_blob`)

`news_asset_blob` still occupies 8 raw records (tracked via `raw_block_count`), but the parser now exposes a higher-level view:

- `records`: list of `{filename, padding}` dictionaries. `filename` is the `.bmp` name pushed into the HUD ticker, trimmed at `.bmp`. `padding` is a list of byte values (0–255) emitted before the filename—typically dozens of zeros plus occasional control codes such as `0x10`. Editors can change the string while keeping the padding untouched to preserve layout.
- `trailing_padding`: byte array (again expressed as integers) representing the bytes that follow the last filename inside the 256-byte blob. Leaving it untouched keeps round-trips identical; shrinking it lets you reclaim space for additional filenames.

When encoding, the tool emits each entry’s padding, the ASCII filename, a mandatory `0x00` terminator, and finally the trailing padding before packing everything back into 8×32-byte records. As long as the total doesn’t exceed 256 bytes, edits remain lossless.

## Footer Blocks

The last three sections carry the integrity markers plus shop bookkeeping.

### footer_metadata

| Key | Notes |
| --- | --- |
| `checksum` | CRC32 that the loader compares against its fresh calculation. |
| `signature_word_0`..`signature_word_4` | ASCII fragments (e.g., `mb.k`) preserved from the retail blobs. |
| `record_count_marker` | Observed `0x70` once all shop rows are present. |
| `reserved_word` | Padding. |

### footer_unlock_flags

| Key | Notes |
| --- | --- |
| `flags_word_0` / `flags_word_1` | Cleared when the profile has never unlocked the level. |
| `unlock_flag_primary` | Set to `1` once the stage is playable. |
| `flags_word_3`..`flags_word_7` | Reserved for future gating logic. |

### footer_slot_counts

| Key | Notes |
| --- | --- |
| `shop_slot_count` | Mirrors the number of populated shop slots (50 in stock levels). |
| Remaining fields | Reserved, left at zero to keep round-trips lossless. |

## Encoding / Decoding Notes

- The parser preserves record order and count so `encode` remains a pure inverse of `decode`.
- Event table records accept either the legacy list form or the new dictionaries; encode will coerce dictionaries using the field order above.
- `remainder` should now stay empty—any non-zero block that lands there means `SECTION_LAYOUT` is out of sync with the blobs and the validator (`scripts/validate_warblade_lvd.py`) will fail the check.

Keep this document in sync with `continue.md` when new sections are named so downstream editors and schemas can share a single source of truth.
