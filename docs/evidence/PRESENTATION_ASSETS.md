# Presentation assets

`content/presentation.json` is generated from the Parser's validated retail inventory and the byte-for-byte extraction provenance manifest.

Regenerate:

```sh
python3 tools/presentation_manifest.py
```

Verify without writing:

```sh
python3 tools/presentation_manifest.py --check
```

## Source integrity

- PAC: `data/warblade.pac`
- PAC SHA-256: `5ee9195f48c22341b058e1f84afb7839b4b03a4ac0f01319714c905e05129bba`
- Provenance SHA-256: `fe2ed2cbfe61658bb36827b427c9922ad45d1cfbb917379f112f20c5af693984`
- TGA packet bounds, dimensions, depth, compression, and storage origin are validated by the Parser.
- HMA values, peer dimensions, byte length, and top-left row-major orientation are validated by the Parser.
- Every selected source hash is compared with provenance and with the extracted `res://` file.

## Finite-product inventory

| Namespace | Entries | Required at startup |
|---|---:|---:|
| Textures and HMA masks | 533 | 188 |
| Music | 12 | 9 |
| SFX | 116 | 38 |
| Voices (pack 1, rank-0) | 103 | 103 |
| Voice pack 2 clips | 36 | 0 |

The texture namespace contains 407 Godot-loadable rasters and 126 HMA collision masks. HMA entries use `kind: hit_mask` and are never marked `required`, so they cannot be sent through Texture2D resource validation.

Voice pack 2 is the retail alternate pack: 36 OGG clips selectable at runtime with a per-clip fallback to pack 1 where a counterpart exists (`pack_1_fallback_available`); `loser` is pack-2-only. The retail pack is incomplete by design, matching the original product.

## Campaign bindings

| Binding | Asset keys | Confidence |
|---|---|---|
| Level backgrounds | Levels 1–25 `stars1`; 26–50 `stars2`; 51–75 `stars3`; 76–99 `stars4`; remainder level 100 `stars1` | Proven selector and Warp-only two-quad scrolling contract at `0x00550900` |
| Difficulty borders | `border_easy`, `border`, `border_hard`, `border_ace` | Proven by executable difficulty table |
| Enemy sheets | All 100 level bindings and every declared resource slot, including `alien_big1_*` at 25, `alien_big2_*` at 50, `alien_big3_*` at 75, and `alien_big4_*` at 100 | Proven by exact LVD resources and executable atlas evidence |
| Fighter sheets | `fighter1`, `fighter2` | Proven atlas and HMA geometry |
| Player projectiles | `weapons_big` | Proven atlas and HMA geometry |
| Alien projectiles | Firing enemy atlas (all eighty declared resource sheets), type 7 at x=480 with `alienshoot10`; supplemental type 6 at x=448 with `alienshoot2` | Proven executable bindings and sounds; per-sheet HMA bounds live in `sprite_frames.json` |
| Fighter thrust | `figterfire2`, ten 16x25 frames | Proven executable geometry and one-tick advance |
| Pickups | `bonuses`, ten 20x20 horizontal frames with recovered type rows and per-object phase/period | Proven executable bindings |
| Original-core effects | Allocated authoritative `boss_retail_effect` / `FUN_005dfee0` / `boss_hit` | Proven state-13 impact binding, retail pool-allocation gate, exact period-0/1 timing, 13-frame geometry, and center anchor; mix blend and the world-effect child layer are explicit runtime policy, and filename-only candidates are not bound in original mode |

Memory Station, Meteor Storm, and the terminal Gem Drop controller have byte-pinned textures, hit masks, music, SFX, and rank-0 announcement cues in dedicated bonus-mode namespaces. Rank-promotion cues required by ranks 1–20 share the voice namespace.

## Ending sequence

The terminal presentation uses 13 byte-pinned 800×600 JPEG slides in retail order (`ending_5`, `ending_4`, `ending_6`, `ending_3`, `ending_0`, `ending_1`, `ending_9`, `ending_7`, `ending_8`, `ending_2`, `ending_10`, `ending_11`, `ending_12`), each for 15 seconds, with `endgame` music. Story and credits text are extracted from the exact 3823-byte executable region `b4fe7687257464e45094fec26f4c24d9eaf47449eeb9a4e367d2a9c42a63eb06`; the leading `|` is a consumed format control and is not rendered. Text advances at 30 pixels/second or 8× while right mouse is held; left mouse pauses text only, and neither control pauses slide timing or music. The final slide holds until Escape, Space, or Fire.

## Collision-safe keys

Texture, music, SFX, and voice are separate namespaces. The four historically selected announcement cues remain addressable in SFX for compatibility while their provenance category and canonical entries are voice. Original underscores are retained. HMA keys receive `_hma`; `newlogo3.tga` owns `newlogo3`, while the reference JPG is `newlogo3_jpg`.

## Closed runtime contracts and evidence-only boundaries

- The background uses the whole 1024×1024 source in two 672×600 destination quads at x=64. The authoritative 60 Hz simulation captures the pre-update draw offset and then applies each float32 Warp `scale / 20` step with 0/600 wrapping; snapshots publish both values, and the client performs wrapped high-refresh interpolation between draw offsets. The traced path has one layer, so no parallax layer is manufactured.
- Alien projectile atlas binding, source rectangles, and authoritative two-row phase are proven; snapshot state owns the phase, including reused simulation slots.
- Original mode binds the 13-frame small explosion from an allocated authoritative state-13 `boss_retail_effect` whose exact call is `FUN_005dfee0` and nested kind is `boss_hit`; a pool-full dispatch emits no presentation event, and the client requires both a positive `allocated_count` and the authoritative `frame_period`. Period 0 advances every update for a 13-update lifetime; period 1 advances every second update for a 26-update lifetime. Explicit type-10 metadata remains accepted. Generic destruction fallbacks are an intentional enhanced-mode presentation and are not a retail claim.
- Fixed metrics and glyph maps for `abcd_2`, `abcd_3`, and `abcd_4` are executable-proven. `endfont` is now losslessly packaged; its executable-local variable-width tables remain evidence-only until every index can be named without invention.
- Title, pause, game-over, and shop retain native retail bitmap geometry where those whole assets are consumed. Accessible interactive labels, controls, and their timing are intentional macOS modernization; they are not presented as reconstructed retail composition.
- Required SFX use an intentional runtime mix policy. Unreferenced sounds remain packaged source evidence and have no runtime tuning consumer.
- Winner fireworks are deterministic from a clone of terminal simulation RNG. Their cadence and particle composition are intentional presentation modernization, not claimed retail reconstruction; Duel draws suppress them.
