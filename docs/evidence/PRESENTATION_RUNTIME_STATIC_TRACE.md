# Retail Presentation Runtime Static Trace

This document records executable-proven presentation geometry and animation state for the scrolling background, fixed bitmap fonts, fighter thrust, ordinary alien projectiles, falling bonuses, and the `expl_small` effect. It is based on static PE/data-flow analysis and original asset dimensions, not screenshots or visual estimation.

Source executable:

`Game/warblade.exe`

SHA-256:

`ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`

All addresses are 32-bit virtual addresses at preferred image base `0x00400000`. One eligible retail update is one 60 Hz simulation step, as established in `LVD_STATIC_TRACE.md`.

## Result summary

| Subject | Recovered retail contract | Confidence |
| --- | --- | --- |
| Background | Whole `1024x1024` stars texture mapped into two `672x600` quads at x=64; Warp offset step is `scale / 20` with 0/600 wrap | Proven; authoritative draw/post offsets integrated |
| Fixed bitmap fonts | `abcd_2` 8x8, `abcd_3` 12x9, `abcd_4` 32x24, fixed advances and executable glyph indices | Proven; `abcd_2` integrated in HUD |
| `endfont` | Losslessly packaged 800x48 atlas and an executable consumer with variable-width source/advance/adjustment tables | Source/executable evidence only; entries are not semantically named without proof |
| Fighter thrust | `figterfire2`, ten `16x25` frames, one frame per eligible update | Proven |
| Ordinary alien projectile | Firing alien atlas, `(480, 0/32, 32, 32)`, top-left anchored | Proven |
| Alien projectile row timing | Per-projectile two-state phase, exported by the authoritative simulation as `animation_frame` | Proven and integrated |
| Falling bonus geometry | `bonuses`, 37 logical rows, ten horizontal `20x20` frames per row | Proven |
| Falling bonus timing | Per-pickup phase, period, and countdown; the authoritative simulation exports the resulting frame | Proven and integrated |
| `expl_small` type-10 effect | Thirteen `32x32` frames in five columns; period 0 holds one update per frame (13 total), period 1 holds two (26 total) | Proven for retail effect type 10 |
| Type-10 call-site binding | State-13 player-projectile impact branch at `0x00585c15`; never generic enemy/player destruction | Proven; exact authoritative boss-effect call integrated |
| Enhanced destruction/flare effects | Generic snapshot-event visual fallbacks | Intentional macOS presentation policy, not a retail claim |

## Scrolling background

`fcn.00550900` selects the `stars1` through `stars5` handle through global `0x007cd068`. The bounded draw region `0x00551a25`-`0x00551b0f` has SHA-256 `f9885bf2ecd4df9da4cf0384f1c14230c3d4d7336a50f53dfc4bbaa259f0f370` in the pinned executable. It sends the whole `1024x1024` source rectangle to two destination quads:

```text
(64, offset - 600) .. (736, offset)
(64, offset)       .. (736, offset + 600)
```

The post-draw update at `0x00551b10`-`0x00551b84` has SHA-256 `8dfe9604a62a68f8d14090526fc9cfccac7be90642476f31f837332135ff414c`. It adds the active player field at `+0x254`, divided by `20.0`, then subtracts 600 at `>= 600` or adds 600 at `<= 0`. That field is the already-authoritative Warp scale. The authoritative 60 Hz step now captures the pre-update draw offset and applies every float32 `scale / 20` update; snapshot-v9 additively publishes `warp.background_draw_offset` and `warp.background_post_draw_offset`. This avoids reconstructing three changing scales from a single 20 Hz server snapshot. The client uses wrapped interpolation between successive authoritative draw offsets without feeding render time into simulation. Normal level steps do not advance the offset. The traced draw has one layer, so the product does not manufacture a parallax layer.

## Fixed bitmap fonts

The fixed renderer at `0x005d0660` consumes `abcd_2` as 8x8 cells with an 8-pixel advance and no pair adjustment in this path. `A..Z` occupy indices 0..25, digits 0..9 occupy 26..35, and the traced punctuation reaches index 52. Style rows begin at source Y 13, 21, 29, and 37. Spaces advance without a draw; newline resets X and advances one cell height. Indices 44 and 46 remain source-preserved without invented semantic character names.

The renderer at `0x005cfcd0` consumes `abcd_3` as 12x9 cells with a 12-pixel fixed advance: digits are 0..9, `A..Z` are 10..35, and traced punctuation occupies 36..51. Index 49 remains source-preserved without a manufactured name. The renderer at `0x005d04a0` consumes `abcd_4` as 32x24 cells with a 32-pixel advance; digits are indices 0..9 and colon is index 10.

`endfont.tga` is a losslessly extracted `800x48` source consumed by the renderer at `0x005d2560`. That function builds variable source-offset, width, advance, and pair-adjustment tables locally. The current evidence does not safely map every table entry to a semantic character. The product packages the bytes and records the consumer, while retaining accessible ending text rendering instead of assigning speculative glyph names or kerning pairs.

## Fighter thrust

The path string at `0x00782170` is `figterfire2.tga`. The loader stores its texture handle at `0x00e11084` in `0x005a405d`-`0x005a406e`; the fighter renderer consumes that handle at `0x005ef657`.

The renderer updates a per-player float phase at `0x005ef5bb`-`0x005ef60f`:

- add `1.0` from `0x00778e48`;
- reset to zero at `10.0` from `0x00779e98`.

It truncates the phase and multiplies by 16 at `0x005ef615`-`0x005ef62e`. The source rectangle is completed at `0x005ef631`-`0x005ef647`:

```text
source = (trunc(phase) * 16, 0, 16, 25)
phase  = 0..9
```

The draw call at `0x005ef653`-`0x005ef69b` uses the retail fighter sprite origin and places the thrust at:

```text
destination_top_left = (fighter_x + 12, fighter_y + 21)
destination_size     = (16, 25)
```

The X/Y identification is explicit: fighter X is loaded into local `-0x9c` at `0x005ef32e`-`0x005ef334`, fighter Y into `-0xa8` at `0x005ef33a`-`0x005ef34b`, and the cdecl draw call pushes Y before X. For a centered `40x27` fighter, the equivalent thrust center is approximately `fighter_center + (0, 20)`.

## Ordinary alien projectile

The ordinary alien spawn path begins at `0x006077f7`. It sets projectile type 7 at `0x00607a3a`-`0x00607a43` and copies the firing alien's texture handle into the projectile at `0x00607a4d`-`0x00607a71`. The renderer later reads that per-projectile handle at `0x0060461d`-`0x00604630`. The projectile therefore uses the firing alien's atlas, not `weapons_big`.

For the proven first-five resource mapping this means:

- levels 1-4: `alien001`;
- level 5: `alien_2`.

The type-7 renderer branch begins at `0x006040c9`. It establishes a `32x32` source/destination extent at `0x006040b5`-`0x006040bf`, chooses source X `480` at `0x006042af`, and initializes source Y to zero at `0x00604492`. At `0x006045f2`-`0x0060461a`, truncating the per-projectile phase to `1` adds 32 to source Y:

```text
frame 0 = (480,  0, 32, 32)
frame 1 = (480, 32, 32, 32)
```

The draw path at `0x00604087`-`0x006040b2` truncates the stored projectile X/Y, and `0x0060461d`-`0x0060463f` passes those coordinates unchanged to the 1:1 source-region blitter. Retail anchoring is therefore:

```text
destination_top_left = (projectile_x, projectile_y)
destination_size     = (32, 32)
```

Ordinary spawn stores that top-left at the firing alien sprite origin plus `(13, 16)`:

- X producer: `0x0060782c`-`0x00607856`, using `13.0` at `0x00779c20`;
- Y producer: `0x0060785c`-`0x00607886`, using `16.0` at `0x0077d848`.

The row selector is a per-projectile float at pool offset `+0x28` (`0x00af7ea8`), not a global render tick. Its common update is `0x00602c7f`-`0x00602d49`: a per-projectile countdown is decremented, reset from the retail `1.0` interval, and the phase is decremented and wrapped through a two-state cycle. Ordinary type-7 spawn initializes the countdown at `0x00607804`-`0x00607813` but does not explicitly overwrite the phase, so pool-slot history is part of exact retail state.

The remake owns this state in the authoritative common-projectile pool, initializes each slot deterministically, retains the slot's `animation_frame` across release/reuse, includes it in snapshots, and has the renderer consume that value. This closes both the earlier global-render-tick approximation and inactive-slot phase carryover boundary.

`Rect2i(32, 0, 4, 10)` cannot represent an alien projectile: `SPRITE_ATLAS.md` proves it is player projectile prototype 0 from `weapons_big`. The `weapons_big` handle at `0x00e11080` is consumed by the player-projectile renderer at `0x006217a7` and `0x00621b91`, not by the alien-projectile renderer.

## Falling bonuses

The path string at `0x0078266c` is `bonuses.tga`; its texture handle is loaded at `0x005a2e55`-`0x005a2e66` and copied into falling bonus objects at `0x00570064`-`0x00570070`.

Standard bonus spawn begins at `0x0056ff10`. The 37-entry selection table at `0x007d0700` is summed and sampled at `0x0056ff32`-`0x0057012e`. The selected record is copied at `0x005701d5`-`0x0057027d` from these parallel tables:

| Meaning | Address | Recovered values |
| --- | --- | --- |
| Base source X | `0x00e11910` | zero-initialized for all 37 records |
| Source Y | `0x007d07b0` | row table below |
| Height | `0x007d0860` | all `20` |
| Width | `0x007d0910` | all `20` |
| Frame count | `0x007d09a8` | all `10` |
| Logical type | `0x007d0a40` | `0..36` |

The source-Y table, indexed by logical type, is:

```text
 0:60   1:80   2:100  3:120  4:140  5:20   6:460  7:160  8:180
 9:280 10:300 11:40  12:340 13:320 14:360 15:240 16:380 17:400
18:260 19:420 20:0   21:500 22:520 23:540 24:560 25:660 26:440
27:200 28:480 29:600 30:580 31:620 32:640 33:220 34:700 35:680
36:720
```

The collection switch begins at `0x00571c60`. Its effect strings close the finite-product runtime semantics:

| Remake meaning | Retail type(s) | Source Y | Executable evidence |
| --- | ---: | ---: | --- |
| Letter E/X/T/R/A | `0..4` | `60,80,100,120,140` | five ordered draws at `0x00593330`-`0x00593436` plus collection state flow |
| Armour | `21` | `500` | type-21 branch and `ARMOUR` string push at `0x00578350` |
| Extra time | `28` | `480` | type-28 branch and `EXTRA TIME` string push at `0x0057ab19` |
| Money variants | `29..32` | `600,580,620,640` | four `MONEY` string pushes at `0x0057ae95`, `0x0057b264`, `0x0057b636`, `0x0057ba12` |

Type 16/Y `380` is `SCOOP`, proven by the string push at `0x0057674d`; it is not extra time.

The source X is animated per object. Spawn stores a frame period sampled between `3.0` and `7.0` at `0x00570024`-`0x00570064`, and initializes phase to integer RNG `[0,5) + 2` at `0x00570243`-`0x00570267`. Update `0x005f4924`-`0x005f49be` decrements the countdown; on expiry it restores the stored period, increments phase, and wraps at the record's frame count of 10. Draw `0x005f728e`-`0x005f72be` adds `trunc(phase) * 20` to source X.

The exact rectangle is therefore:

```text
source = (animation_frame * 20, source_y_for_type, 20, 20)
```

The remake now stores authoritative per-pickup `animation_frame`, `animation_period_fp`, and `animation_countdown_fp`, advances them in the simulation, exports the resulting frame in snapshots, and has the renderer consume it. No global-render-tick approximation remains in this path.

## `expl_small` effect type 10

The path string at `0x0078245c` is `expl_small.tga`. Its handle is loaded at `0x005a3777`-`0x005a3788` and used only by the type-10 draw at `0x00622a1f`-`0x00622a3d` in this bounded trace.

The spawner at `0x005dfee0` writes:

- effect type `10` and frame `0` at `0x005dff5b`-`0x005dff71`;
- frame period and countdown from integer RNG `[0,2)` at `0x005dff7b`-`0x005dffb1`.

Update `0x006221f8`-`0x0062224b` subtracts `1.0` from the countdown, restores the frame period when it expires, and increments the frame at `0x00622376`-`0x0062238b`. With period zero, subtraction makes the countdown negative on every update, so each frame lasts one update and the sequence lasts 13 updates. With period one, the first subtraction reaches zero and the next becomes negative, so each frame lasts two updates and the sequence lasts 26 updates. The type-10 guard at `0x00622397`-`0x006223bf` deactivates the slot after frame 12, proving frames `0..12` for both exact period branches.

Render `0x006227ec`-`0x00622860` centers a `32x32` destination by subtracting 16 from the stored effect X/Y. Source X and Y come from the tables at `0x007cf138` and `0x007cf188`:

```text
frame 0..12:
x = (frame % 5) * 32
y = (frame / 5) * 32
size = 32x32
```

The physical `160x96` image contains 15 cells, but retail effect type 10 consumes only the first 13. `fcn.005dfee0` has one xref through thunk `0x00526829`; that thunk is called at `0x00585c15` inside `fcn.00585840`, after the state-13 check at `0x00585a57`. The inclusive instruction region `0x00585a57`-`0x00585c19` has SHA-256 `ea40f903dc5bce682a07058e7fdede5de7f25e0a4c1d2517ced056af9bf52ae5`. This proves a state-13 player-projectile impact consumer and excludes generic enemy/player destruction call sites.

The state-13 controller invokes its effect callback as `FUN_005dfee0` with nested payload kind `boss_hit` and exact impact X/Y. It publishes the authoritative `boss_retail_effect` only after the retail effect runtime returns a positive `allocated_count`; a full 50-record flash pool consumes no RNG and publishes no visual event. The game simulation republishes an allocated event without changing its call, payload, allocation count, or exact `frame_period`, and original presentation mode requires both the allocation and period before binding the event to `expl_small`. Near-miss calls, pool-full calls, malformed period metadata, and generic `enemy_destroyed` or `player_destroyed` events fail closed. Explicit type-10 metadata remains accepted. Enhanced mode keeps deterministic destruction and flare fallbacks as a macOS presentation policy. Its mix blend and child-layer draw order are likewise explicit runtime policy rather than executable-backed claims.
