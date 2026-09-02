# Finite Product Gap Matrix

This matrix is the closure ledger for the macOS product (the authored levels
1–100 campaign plus executable-backed endless play beyond level 100) at the
change set based on `5cd94ec`. It classifies the complete inventory obtained by
searching `README.md` and every Markdown and generated evidence document under
`docs/` for
`unresolved`, `provisional`, `remaining`, `future`, `supported approximation`,
`confidence boundary`, `later`, `milestone`, `deferred`, and `unknown`.
Generated evidence retains those words only where the source bytes or human
meaning truly have no reachable runtime consumer. The high-level documents no
longer use milestone language for closed product behavior.

Status meanings are strict: **Closed** has an executable implementation and a
focused contract test; **Open** is proven retail gameplay that is traced but not
yet implemented, and is a real product gap; **Evidence-only** is losslessly
retained source data with no supported-runtime consumer; **Preserved** is a
deliberate architecture choice; **Non-goal** is excluded product scope;
**Separate program** has no defect in the finite local product.

G19 and G20 are the two rows that do not come from that search: the secret
ship family was found by tracing the executable after the search was taken, so
the ledger carries it explicitly rather than leaving it untracked. Both are now
closed.

The `5cd94ec` search produced the backlog claim families traced below. Repeated
generated-JSON instances are grouped with their owning evidence document, but
every actionable claim is mapped to an ID. Matches such as “later collision
pass,” “remaining active enemy,” “remaining fighter,” and “future input tick”
describe execution order, live counts, or validation rather than backlog; they
are grouped in the final row instead of being misclassified as product work.

| Original source occurrence | Matrix disposition |
| --- | --- |
| `README.md` — `Still unresolved or provisional`: detailed Duel | G01 (category 1), closed. |
| `README.md` — deterministic seed versus retail cursor/time/UI noise | M01 (category 4), preserved. |
| `README.md` — sequencing, background, fonts, effects, and Duel fireworks | P01–P07 (category 2), E15/E16 (category 3), and M06/M07/M09 (category 4). |
| `README.md` — tracker-module playback described as milestone work | N01 (category 5), corrected to a permanent non-goal and final MP3 system. |
| `README.md` — unresolved evidence fields, local anti-cheat, and `later cross-platform milestone` | E01–E12 (category 3), I01/I02 (category 6), and N04 (category 5). |
| `ARCHITECTURE.md` — deferred Time Trial/milestone boundary | I03 (category 6), closed by the implemented match mode 6; it does not alter supported authored level mode 6. |
| `ARCHITECTURE.md` — presentation-provisional background motion and tracker modules outside the milestone | P02 (category 2), M09 (category 4), and N01 (category 5). |
| `ARCHITECTURE.md` — raw unresolved LVD words and provisional compatibility waves | G10–G14 (category 1) where consumers are proved; E03/E04/E08/E12 (category 3) otherwise. |
| `CONTENT_CONTRACT.md` — unresolved path word and provisional compatibility-wave fields | G11 (category 1) and E03/E08 (category 3). |
| `CONTENT_CONTRACT.md` — deferred Time Trial and provisional finite-product list | I03 (category 6, now closed by `time_trial.json` and match mode 6), P01–P11 (category 2), M01–M09 (category 4), and N02 (now category 1, closed by executable-backed endless play). |
| `DIFFICULTY_RULES.md` — provisional multipliers, unresolved cash/drop behavior, rare float32 boundary, and remaining difficulty globals | G04/G07/G08 (category 1), E06/E07 (category 3), and M02 (category 4). Repeated generated `difficulty_rules.json` records have the same disposition. |
| `ENEMY_BEHAVIOR_STATIC_TRACE.md` — `Still unresolved` state-4/state-6/RNG policy and follower labels | G02–G04 (category 1) and E02 (category 3). Its earlier superseded timer/supplemental statements map to G03/G08/G10. |
| `FIRST_FIVE_FIDELITY_TRACE.md` — `Confidence boundary` | G04 (category 1) and M01–M05 (category 4); presentation ownership is P01–P11/M06–M09. |
| `LVD_CLASSIC_LEVELS.md` and `LVD_FIRST_FIVE.md` — provisional waves and remaining supplemental words | G10/G11 (category 1) and E04/E08 (category 3). |
| `LVD_STATIC_TRACE.md` — unresolved timers, supplemental/fixed/tail fields, path word, resources, and SWD association under `Confidence boundary` | G10–G14 (category 1) and E03–E06/E12 (category 3). |
| `PRESENTATION_ASSETS.md` — milestone inventory, `Unresolved presentation behavior`, remaining bindings, and projectile `supported approximation` | P02–P11 (category 2), E09/E15/E16 (category 3), and M06–M09 (category 4). |
| `docs/evidence/README.md` — `Remaining confidence boundary` | G04 (category 1), P01/P03/P05/P07 (category 2), and M01/M02/M04/M07/M09 (category 4). |
| `SPRITE_ATLAS.md` — unresolved state-10 frame producer, supported supplemental bounds, and earlier provisional grids | G10/G12 (category 1) and E04/E11 (category 3). |
| `SWD_ATTACK_BEHAVIOR.md` — unresolved header/point words and selector labels under `Confidence boundary` | G02 (category 1) and E01/E02/E12 (category 3). |
| `WEAPON_RUNTIME_TRACE.md` — unresolved RNG endpoints and Laser collision/update opportunities | G04/G05 (category 1). The generated `weapon_runtime.json` repeats the same two boundaries. |
| Generated `classic_levels.json` and `provenance_manifest.json` unresolved/provisional fields | G11/G14/G15 (category 1) for now-proved consumers; E04/E06–E09/E12 (category 3) for lossless/no-consumer fields. |
| `BIG_BOSS_STATE_13.md`, `BONUS_MODES.md`, and `ORDNANCE_RUNTIME_TRACE.md` declarations that no gameplay-critical unresolved field remains | Closed assertions, not backlog; the ordnance trace's mode-6 exception is I03 (category 6), now closed and implemented. |
| `PRESENTATION_RUNTIME_STATIC_TRACE.md` historical scope wording and other files' ordinary `later`, `remaining`, or `future` execution prose | Historical scope or execution-order language only; no product gap. Stale milestone wording is removed from current documentation. |

## 1. Actionable gameplay defects or missing behavior

| ID | Inventory item | Resolution | Status |
| --- | --- | --- | --- |
| G01 | Detailed retail Duel through levels 1–100 | The complete traced implementation (simultaneous fighters, pass-through opponent shots, contested pickups, independent progression, sequential shops, terminal winner/draw result, and ending metadata) was closed, then removed from the product together with retail alternating play by user decision (2026-08-10). It is preserved intact on the `retail-two-player-modes` branch. | Removed |
| G02 | State-4 return selector | The numeric selector branches, cutoff draw, update order, and return states use the executable trace. Unproven human direction labels are separated into E02. | Closed |
| G03 | State-6 steering and firing | Supplemental steering, aimed-shot difficulty travel multiplier, fire gate, draw order, geometry, and pool-full behavior are executable-backed and tested. | Closed |
| G04 | RNG endpoints and modulo bias | Unsigned endpoint conversion, half-open biased integer wrappers, absence of rejection sampling, float32 maximum-word rounding, and modulo cases have deterministic vectors. | Closed |
| G05 | Player-weapon update/collision ordering | Projectile allocation, motion, collision opportunities, Laser continuation, damage subtraction, expiry, and counter order follow the traced dispatcher. | Closed |
| G06 | Armour hazard coverage | Alien-projectile damage enters the shared per-seat `_damage_player` Armour/death path with absorption and spill-through tests in every supported match family. | Closed |
| G07 | Difficulty drop behavior with a live consumer | The executable denominators 18/28/38/48 drive the reachable bonus-drop branch on the four difficulties with deterministic tests. Cash scaling without a consumer is E07. | Closed |
| G08 | Difficulty globals with reachable consumers | Extra Time floors, Meteor parameters, follower thresholds, the state-6 aimed-shot travel multiplier, Timer-B launch values, and fighter/death rules are named only at proven consumers and tested by difficulty. | Closed |
| G09 | Fighters, death, respawn, and game over | Solo and remake co-op use their proven/shared fighter accounting and terminal rules; the campaign matrix exercises the mode-correct respawns. | Closed |
| G10 | LVD supplemental words and timer dataflow | Spawn count/resource, state-6 fields, Timer-A/Timer-B updates, and proven score-table entries are consumed under evidence-backed names; other bytes remain E03/E04. | Closed |
| G11 | Legacy `waves[0]` gameplay dependency | Runtime combat defaults and speed now come from explicit versioned contracts; `waves` is predecessor-read compatibility only and cannot alter v9 authoritative play. | Closed |
| G12 | State-10 frame-index producer | The six-frame seeded/reversed producer, retained frame, HMA geometry, renderer binding, and collision frame agree with the executable trace and deterministic tests. | Closed |
| G13 | Playfield and movement bounds | The 800×600 retail field and fighter clamps are explicit runtime contracts tied to executable evidence rather than inferred LVD bytes. | Closed |
| G14 | Fixed table and LVD tail-A consumers | Only executable-proven entries are exposed to gameplay; inactive entries and tail B remain lossless evidence under E04. | Closed |
| G15 | Late special-projectile constants | Values 163, 165, 190, and 200, their allocation/update order, target rules, and collision behavior are promoted to generated evidence and focused runtime tests. | Closed |
| G16 | Forward and reversed letter-sequence awards | Every letter collect scores 100 (multiplier applies), the strict consecutive E-X-T-R-A and A-R-T-X-E chains fill fighters and armour to their caps or award the 5,000,000 SUPER variants, and the repeating all-collected award grants a fighter (with the clamped ten bonus-time units), an armour, or 1,000,000. `LETTER_AWARDS.md` pins the dispatcher, the four banners, and the score table; focused chain tests cover forward, reverse, broken, capped, and repeating passes. | Closed |
| G17 | End-of-game tally, retire, and Duel totals | Every terminal result computes the per-seat GAME BONUSES tally (cash x 100, the cumulative rank bonus table, perfects x 100,000, truncated hit percentage x 1000) and carries base and total scores; the pause-menu retire ends the run through the same game-over path. The traced Duel winner rule (score plus bonus sum, equality preserved as a draw) left the product with the Duel mode and is preserved on the `retail-two-player-modes` branch. The unreachable retail MAX CASH BONUS branch stays evidence-only. `GAME_BONUS_TALLY.md` pins the sequencer, seed, accumulator, renderer, and rank table. | Closed |
| G18 | Profile locks, persistence, and shop-exit Auto Fire | Profiles persist the retail statistics (games, levels, highest level/rank/money, shots, hits, game time, fastest clear, secrets seen) and the lock evaluator applies the traced start-with table on solo starts: score tiers, games-played tiers with drop-table exclusions and blue-only coins, the find-all-secrets award, the above-200,000,000 secret counter, the hit-rate shop unlocks, and the terminal-rank package. Retail Auto Fire now resets at shop exit unless the 1,000-games lock or purchased Super Auto Fire holds it. The fastest-Meteor-Storm producer is untraced, so its field stays unset and those Extra Time locks stay dormant. `PROFILE_LOCKS.md` pins the applier, the locks screen, and every threshold. | Closed |
| G19 | Hurry-up secret ships | Ordinary play arms a per-player deadline from the difficulty timed-effect interval (50/40/30/20 seconds), and running past it spawns the state-9 mothership with the "H U R R Y   U P" banner, a `hurryup1`/`hurryup2` voice line, the mothership hum, and a re-randomised parallax planet row; every eighth wave also spawns the state-12 money ship. Both raise the level object total, use their traced hitboxes, score 2,500 and 25,000, take their health from the traced difficulty bases, and record found-secrets 3 and 6 on a solo profile. Time Trial is excluded, and the spawner re-arms on the flat ten-second interval. `HURRY_UP_SECRET_SHIPS.md` and `hurry_up.json` pin the deadline, every guard, the complete random-draw order, both motion handlers, and both death cases; `tests/sim/test_hurry_up.gd` covers them. The remake stops at the traced rectangle instead of also running retail's per-pixel mask, and it starts the mothership animation fields at their fresh-level values instead of retail's entity-slot residue; both deviations are recorded in the evidence document. | Closed |
| G20 | Money-sucker and guard secret ships | Two further secret ships share the death dispatcher switch at `0x005887bc` with the hurry-up family but have independent spawners and triggers. The money sucker (state 11, `FUN_00581250`, `moneysucker2.tga`) is drawn by cash above 750 weighted by `cash / 1340 + RngInt(3, 10)` behind a 120,000 ms cooldown, patrols the surface reversing at either edge, and drains one retail money-pickup value (10/50/100/200) whenever it is inside the traced band; killing it raises difficulty health base B by 20. The guard (state 18, `FUN_00581990`, `guard.tga`) needs a level above 15 with at least ten levels since the last one, is excluded in match mode 6, opens a random firing window during which it stops moving and walks a 70-pixel column of kind-18 beam segments from `ship_y + 30`, and leaves at either edge; killing it raises difficulty health base D by 250. Neither records a found secret, both raise the level object total, and both take their health from the shared effect pool wave's difficulty bases, now shipped as `special_health_base_b` and `special_health_base_d` in `content/difficulties.json` v4. `HURRY_UP_SECRET_SHIPS.md` pins every guard, draw, motion mode, and death case; `tests/sim/test_hurry_up.gd` covers them. The remake suppresses all three spawners on the mode-3 bonus and mode-4 boss levels, wraps each sheet's animation at its own frame count, and starts its clock at zero so the very first frame of a match cannot spawn a money sucker; all three deviations are recorded in the evidence document. | Closed |

## 2. Actionable presentation fidelity work

| ID | Inventory item | Resolution | Status |
| --- | --- | --- | --- |
| P01 | Recoverable sequencing outside bonus and ending controllers | Authoritative phase/snapshot state and deduplicated events let title, get-ready, level, shop, pause, death, game-over, and terminal presentation recover without becoming gameplay authority. No unified retail timeline is claimed; unsupported transition timing is M09. | Closed |
| P02 | Background crop, motion, scrolling, and parallax | Each 1024×1024 atlas is mapped through two 672×600 quads spanning logical X 64–736. The authoritative 60 Hz simulation captures the pre-update draw offset and applies every executable-backed float32 Warp `scale / 20` step with 0/600 wrap; snapshots publish draw/post offsets and the client performs wrapped high-refresh interpolation. | Closed |
| P03 | Bitmap-font metrics, kerning, and layout | Executable-proven fixed contracts for `abcd_2`, `abcd_3`, and `abcd_4` expose exact glyph cells, advances, fixed layout rules, and empty pair-kerning tables; the supported HUD consumer renders through the manifest-driven layout. HUD centering/rectangle placement is M09, and unrepresented glyphs/E16 do not acquire invented metrics. | Closed |
| P04 | Title, HUD, pause, game-over, and shop presentation | Native source geometry and exact title, HUD, pause, game-over, and shop rasters are manifest-bound on the 800×600 canvas; fixed-font HUD pixels use P03. The surrounding interactive composition/timing has no proved retail contract and is explicitly M09 rather than a fidelity claim. | Closed |
| P05 | Effect rectangles, anchors, order, blend, and timing | Executable-backed coverage proves the type-10 `expl_small` source as 13 consecutive 32-pixel frames, exact period-0 one-update holds and period-1 two-update holds (13/26-update lifetimes), and the 16-pixel center-anchor subtraction. Mix blend and effect-child layering are bounded M06 runtime policy rather than retail claims; unbound packaged sources are E15. | Closed |
| P06 | Effect type-10 event binding | The executable call site proves type 10 for the state-13 player-projectile impact. The state-13 controller dispatches first and emits the exact authoritative `boss_retail_effect` / `FUN_005dfee0` / nested `boss_hit` payload only when the retail effect pool reports a positive allocation, carrying its exact `frame_period`; original mode requires both fields and rejects pool-full, malformed-period, and generic hit/destruction events. Explicit type-10 metadata remains accepted. | Closed |
| P07 | Deterministic Duel winner fireworks | The traced winner-only routing shipped and then left the product with the Duel mode (user decision, 2026-08-10); it is preserved on the `retail-two-player-modes` branch. The client-local duplicate of terminal snapshot RNG/tick still makes the M07 ending firework cadence/particles deterministic. | Removed |
| P08 | Alien-projectile pool phase | Slot reuse, initial phase, two-row source selection, update order, and snapshot export are authoritative; the former approximation label was stale. | Closed |
| P09 | Runtime-required SFX binding | The 38 consumed cues have explicit event bindings and bounded playback tests. Their gain, concurrency, priority, loop, and pitch values are the M08 runtime mix policy rather than an invented retail mixer claim; the other 78 compatibility records are E09. | Closed |
| P10 | Presentation bindings and layout contracts | Every supported binding has a validated source hash, dimensions, runtime consumer, and smoke/layout assertion; missing required resources fail closed. | Closed |
| P11 | Hold-state frame retention | Runtime fallthrough retains the proven source frame for authored hold states, including HMA agreement, without guessing a new frame. | Closed |

## 3. Evidence-only unknowns with no runtime consumer

| ID | Inventory item | Treatment | Status |
| --- | --- | --- | --- |
| E01 | SWD header words 0–4 and 7; point word 3 | Preserve exact words and raw blob; point word 3 is zero in all catalog points. No semantic names or gameplay reads. | Evidence-only |
| E02 | Human labels for state-4 selectors and follower flags | Numeric behavior is closed; prose labels remain deliberately neutral until independently proven. | Evidence-only |
| E03 | LVD path word `+0x0c` | Preserve all 3,607 zero values and decoded positions; no finite-product consumer exists. | Evidence-only |
| E04 | Fifth supplemental slot, inactive fixed-table entries, tail B, unused resources | Preserve ordered words, counts, and raw LVD bytes; validate round trips; do not expose invented gameplay fields. | Evidence-only |
| E05 | Human names for group modes and timer roles beyond proven consumers | Keep numeric IDs and address-level descriptions. Runtime uses only proven numeric contracts. | Evidence-only |
| E06 | Difficulty globals without a finite consumer | Addresses `0x8f2058`, `0x8f2024/28/2c`, `0x8f2074`, and any unconsumed `0x8f2030/34/38` values remain evidence records only. | Evidence-only |
| E07 | Difficulty cash multiplier or global score multiplier | No reachable finite-campaign consumer is proven; the product applies no fabricated multiplier. | Evidence-only |
| E08 | Legacy parser aliases and raw evidence views | Retained for predecessor decoding and forensic round trips, excluded from current authoritative semantics. | Evidence-only |
| E09 | Inert SFX compatibility tuning records | Preserve all 78 names and raw/default values, but do not claim executable gain/overlap/pitch semantics without a call-site consumer. | Evidence-only |
| E10 | Generic state-6 prose geometry names | Exact numeric geometry is implemented; broader human pose names remain neutral evidence. | Evidence-only |
| E11 | Superseded `content/sprites.json` layouts and unused guard/beam records | The generated sprite-frame catalog is authoritative; old layouts remain non-authoritative evidence/compatibility data. | Evidence-only |
| E12 | Absence of a direct LVD-to-SWD assignment | The global catalog trace proves no per-LVD assignment; preserve this negative finding instead of inventing linkage. | Evidence-only |
| E13 | Empty generated closure arrays | Empty `gameplay_critical_unresolved`-style fields are machine assertions that no live gap remains, not backlog. | Evidence-only |
| E14 | Historical milestone wording in archived/source commentary | Treat as chronology only when retained in evidence; it grants no product scope and creates no runtime work. | Evidence-only |
| E15 | Unbound effect source assets | `explo`, sparks, glow, streak, bomb, laser, guard, and beam source records remain hash-pinned packaged evidence where no reachable executable semantic binding is proven; original mode does not invent one. | Evidence-only |
| E16 | `endfont` variable-width table semantics | The sheet and executable-local offset, width, advance, and pair-adjustment consumers are preserved, but their complete character-index mapping is not proven. The ending keeps its accessible renderer rather than assigning invented glyph names or kerning. | Evidence-only |

## 4. Intentional modernizations

| ID | Decision | Contract | Status |
| --- | --- | --- | --- |
| M01 | Deterministic match seeding | Explicit match seeds replace retail cursor/time/UI entropy and are recorded in replay metadata. | Preserved |
| M02 | Fixed-point authoritative simulation | Integer/rational state removes host variance; explicitly tested conversion boundaries replace rare platform-float ambiguity. | Preserved |
| M03 | Server authority | Inputs and semantic commands are accepted by the server; clients never author gameplay state. | Preserved |
| M04 | Simultaneous co-op | Simultaneous co-op is an intentional modernization with shared party progression and nearest-target behavior. | Preserved |
| M05 | High-refresh interpolation | Clients interpolate authoritative 60 Hz snapshots without feeding presentation time into simulation. | Preserved |
| M06 | Optional enhanced presentation/scaling | Smooth scaling and enhanced effects may wrap the recovered source-backed presentation elements without changing authoritative state. | Preserved |
| M07 | Ending firework cadence and particles | Retail proves the firework routing, but not exact cadence/particle layout. The client uses a deterministic snapshot-seeded presentation sequence and does not claim those visual details as recovered. | Preserved |
| M08 | Runtime SFX mix policy | For the 38 consumed cues, bounded gain, concurrency, priority, loop, and pitch values provide a deterministic macOS mix. Source identity and event binding are evidence-backed; mixer values are not claimed as retail reconstruction. | Preserved |
| M09 | Accessible screen composition and timing | Title, get-ready, level, pause, death, shop, and game-over retain source-backed elements where available, but surrounding transitions, interactive overlays, rectangles, and timing are intentional accessible macOS presentation where no exact executable contract is proved. | Preserved |
| M10 | Jukebox, voice-pack selection, and input remapping | The in-app jukebox overrides the eleven retail music slots with built-in tracks, user MP3/OGG files, or a Main-slot playlist; configuration is global in `settings.json` rather than retail's per-profile `Warblade.wpl`. Voice pack 2 is selectable with a per-clip fallback to pack 1, where retail simply skips cues an incomplete pack lacks. Keyboard/controller remapping persists explicit InputMap bindings. These are deterministic client-side conveniences and never touch authoritative gameplay. | Preserved |
| M11 | Online identity and the persistent talent tree | Remake-original meta progression, not retail recovery: a nickname plus a device key the client generates once identify the pilot on the Rust lobby server (`lobby-server/`), seat 0 binds that identity, and server-validated talent purchases compose deterministic start-state grants plus licenses for the four talent-gated shop effects (`enable_autofire`, `enable_super_autofire`, `rocket_pack`, `enable_alien_lock`). `content/talents.json` (v1) is the hashed twelfth content document; the contract carries `talents_enabled`, seat `shop_unlocks`, and the clamped rocket grant. With talents disabled the gated items keep their retail unlock rules byte-for-byte, and Time Trial never runs talent-enabled. Talent points are credited by the lobby server from self-reported match results without verification and cached at `user://talent_cache.json` so grants apply offline; the in-game economy never mints them. | Preserved |

Retail simultaneous Duel was never in this category: simultaneous Duel is retail behavior, while retail alternating play hands control over after death. Both retail two-player modes were removed from the product by user decision (2026-08-10) and are preserved on the `retail-two-player-modes` branch; simultaneous co-op is an intentional modernization and the only two-player mode on `main`.

## 5. Explicit product non-goals

| ID | Decision | Contract | Status |
| --- | --- | --- | --- |
| N01 | Tracker modules | Tracker-module `.mus` playback is a permanent product non-goal. The extracted MP3 soundtrack is the final music system. No extraction, conversion, emulation, investigation, implementation, or scheduling of module playback is permitted. | Non-goal |
| N02 | Campaign play beyond level 100 | Retail behavior past level 100 is executable-backed and implemented: content cycles with period 100, the mirror alternates per hundred, the cumulative per-hundred progression step (health, projectile speed, simulation scale, timer adjustments, update target) applies, level-100 credits are an interstitial, and the level counter clamps at 3999. See `ENDLESS_PROGRESSION.md`. | Closed |
| N03 | Alternate voice pack 2 | Overturned by user decision: voice pack 2 (36 clips plus its pack table) is extracted, hash-pinned, and consumed by the runtime voice-pack selector with the M10 per-clip fallback to pack 1. `loser` stays packaged without an invented consumer. Unrelated minigame material does not exist in the archive: every `warblade.pac` member is allowlisted. | Closed |
| N04 | Redistribution of retail assets | Extracted content stays local and hash-pinned; it is never pushed, published, or redistributed. | Non-goal |

## 6. Separately bounded infrastructure or product programs

| ID | Program | Boundary | Status |
| --- | --- | --- | --- |
| I01 | Trusted online hosting | Not pursued by product decision (2026-09-01): online co-op is player-hosted. The host's Mac runs the authoritative game server bound publicly (`--host=* --port --token --rendezvous --rendezvous-nonce`), a joiner takes seat 1 through UDP hole punching coordinated by the lobby server's rendezvous socket, UPnP on the host's router, or a manually entered address, and party chat rides the same server as a bounded CHAT message. The Rust lobby server (`lobby-server/`) provides identity, the lobby list, global chat, NAT rendezvous, talent storage, self-reported match records, and a loopback-only owner admin page; it never relays game traffic. There is no anti-cheat. Trusted online hosting, matchmaking beyond the lobby list, and anti-cheat operations remain a separate infrastructure program if ever wanted. | Separate program |
| I02 | Cross-platform delivery | Cross-platform delivery, signing, packaging, input certification, and platform QA are separate from the supported macOS exports. | Separate program |
| I03 | Time Trial | Retail match-mode 6 Time Trial is implemented: `content/time_trial.json` carries its fifteen authored levels and its byte-pinned clock, loader, and mode rules, and `sprite_frames.json` v11 carries its eighteen enemy sheets. Its death-reset exception applies only in match mode 6 and does not alter level mode 6, Warp, or Warp Malfunction. | Closed |

## Verification ownership

`make verify` enforces this ledger, current versions, generated evidence,
parsers, content, simulation, presentation, protocol, networking, audio, and
packaged-runtime smoke. `make test-campaign-matrix` runs two level-100
production-pixel/HMA route-assist campaigns plus a frame-by-frame authoritative
hash replay for solo and simultaneous co-op. The campaign matrix asserts
shops, deaths and
mode-correct respawns, Warp, bonus
boundaries, homing targets, bosses 25/50/75/100, absence of the liveness
watchdog, terminal credits metadata, and no level-101 request.
The route assist is explicit in each replay (`starting_weapon=8`, 999 fighters,
100 cash, and 50 rockets) so the five exhaustive routes remain bounded without
weakening shipped pixel collision. Focused simulation, shop, ordnance, hit-mask,
and first-five tests cover the production starting weapon, three-fighter
depletion, zero-cash economy, zero rockets, and HMA fail-closed boundaries.
