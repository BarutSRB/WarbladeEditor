# Original Content Evidence

This directory records what the remake copies from the local Warblade
installation, where every copied byte came from, and which claims are proven
versus lossless evidence-only boundaries. The complete six-category product
ledger is `../GAP_MATRIX.md`.

## Reproduce and validate

The extraction tool never invokes `tar.extract` and never accepts archive
paths discovered at runtime. It reads only exact regular-file member names
from `tools/pac_allowlist.json`, rejects duplicate sources or destinations,
checks the source PAC hash before reading, confines every destination below
`assets/original`, and writes files atomically.

```sh
python3 tools/extract_original_assets.py \
  --game-root Game
python3 tools/validate_content.py
```

Exact enemy, fighter, playable-projectile, and HMA source-rectangle contracts
are generated separately from the verified executable:

```sh
python3 tools/sprite_atlas_extract.py --output content/sprite_frames.json
python3 tools/sprite_atlas_test.py
```

See `SPRITE_ATLAS.md` for the traced renderer states, fighter banking producer,
all supported supplemental linkages, Laser continuation frames, pixel-mask
format, and explicit evidence boundaries.

The Time Trial catalog (retail match mode 6) is generated from pinned retail
instruction bytes plus lossless LVD decoding:

```sh
python3 tools/time_trial_extract.py
python3 tools/time_trial_extract.py --check
```

See `TIME_TRIAL.md` for the match clock, its byte-identical entry sites, the
loader and mode globals, and the fifteen authored levels.

The hurry-up secret-ship contract is generated the same way:

```sh
python3 tools/hurry_up_extract.py
python3 tools/hurry_up_extract.py --check
python3 tools/hurry_up_test.py
```

See `HURRY_UP_SECRET_SHIPS.md` for the deadline, every spawner guard, the
complete random-draw order, both ship behaviours, their collision boxes, the
found-secret ids, and the two further secret ships that stay evidence only.

The global SWD catalog and player weapon-runtime contracts are reproduced with:

```sh
python3 tools/swd_roundtrip_test.py
python3 tools/swd_content_extract.py --check
python3 tools/weapon_runtime_test.py
python3 tools/weapon_runtime_extract.py --check
python3 tools/difficulty_rules_test.py
python3 tools/difficulty_rules.py --check
python3 tools/endless_progression_test.py
python3 tools/endless_progression_extract.py --check
python3 tools/first_five_runtime_extract.py --check
python3 tools/classic_levels_extract.py --check
python3 tools/bonus_modes_extract.py --check
python3 tools/bonus_modes_test.py
python3 tools/boss_contract_extract.py --check
python3 tools/boss_contract_test.py
python3 tools/ordnance_contract_extract.py --check
python3 tools/ordnance_contract_test.py
```

`SWD_ATTACK_BEHAVIOR.md`, `ENEMY_BEHAVIOR_STATIC_TRACE.md`,
`WEAPON_RUNTIME_TRACE.md`, and `DIFFICULTY_RULES.md` are the current additive
behavior authorities; `ENDLESS_PROGRESSION.md` is the authority for campaign
play beyond level 100, and `HUD_LAYOUT.md` pins the retail sidebar and score
composition. Where they supersede an early hypothesis, the older
trace is reconciled to name the current authority rather than advertise stale
work.

The generated `provenance_manifest.json` contains the SHA-256 and byte length
of all source anchors and all 936 copied assets. It also embeds
`tools/known_facts.json`, so the exact evidence used to author content travels
with the asset inventory.

The current allowlist contains:

| Category | Files |
| --- | ---: |
| All campaign raw LVDs | 100 |
| Complete global SWD attack-path set | 14 |
| Enemy sprites and masks involved in levels 1–100 | 240 |
| Ending and credits slides | 13 |
| Player sprites and masks | 5 |
| Alternate player sprites (`fighter_gold`) | 2 |
| Weapon sprites and masks | 8 |
| Warp-malfunction LVD sources | 4 |
| Warp-malfunction sprites and masks | 10 |
| Warp-malfunction sheet/mask completion | 9 |
| Time Trial raw LVDs | 15 |
| Time Trial enemy sprites and masks | 18 |
| Alternate enemy sheets | 39 |
| Money-feature sprites (`moneyship`, `moneysucker2`) | 6 |
| Hurry-up mothership rasters | 2 |
| Hurry-up HMA (evidence-only, no paired raster) | 1 |
| Supplemental `_mask.hma` hit-mask files | 6 |
| Malfold colour/mask completion | 5 |
| Title, menu, and HUD art | 54 |
| First-shop art | 53 |
| Weapon and combat effects | 50 |
| Memory Station and Meteor Storm textures/masks | 6 |
| Credits portraits | 7 |
| Music used by the product | 12 |
| Core sound-effect source files | 112 |
| Complete rank-0 retail voice pack | 103 |
| Voice pack 2 clips and pack table | 37 |
| Voice transcript and pack documents | 3 |
| Retail manual text | 1 |
| Application icon | 1 |

Every file in `warblade.pac` is now allowlisted (667 of 667 members). The
remaining exclusions are external: the 12 `.mus` tracker modules
(tracker-module `.mus` playback is a permanent product non-goal; the extracted
MP3 soundtrack is the final music system), the byte-identical
`memorystation.mp3` duplicate of `memory.mp3`, and the Windows-only
executables (`Jukebox.exe`, `bass.dll`, `fmod.dll`) plus the website shortcut,
which have no asset role in the macOS remake.

## Source anchors

| Source | SHA-256 |
| --- | --- |
| `warblade.exe` | `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef` |
| `data/warblade.pac` | `5ee9195f48c22341b058e1f84afb7839b4b03a4ac0f01319714c905e05129bba` |
| `Warblade_Manual_V1.34_Eng.txt` | `d2d486652db908001a86dfcf4e10421823048a382b8a9bb60f9d9d7c7e368e92` |
| `warblade.ico` | `7ea4bb9d30bd683fd59a7ab25f7471db93bb122741813f0ac9753f7db616c70f` |

## Confirmed first-five metadata

| Level | Title | Enemy sheet | Raw LVD SHA-256 | Shop after |
| ---: | --- | --- | --- | --- |
| 1 | JUST WARMING UP | `alien001` | `6938e9f31d93071b129a7c583f37751e899239bd97dd3d4c678664880d04aaf1` | No |
| 2 | empty | `alien001` | `0db45277db488947b998b1478523c2e8d2905c0d720ddb9a3efc489423a38934` | No |
| 3 | THE FIRST BIG ONE | `alien001` | `32f28ba7335a5fde68951f7f4af8ecf8c6f5937cb0d12e60eafb9ee229680a33` | No |
| 4 | K A M I K A Z E | `alien001` | `0c816b48f007965b14a141797603a13de900879030895016e3491a56c5ab5942` | Yes |
| 5 | GETTING A BIT WARMER | `alien_2` | `0584103d5211181bb65deef633cd6d440bbc1658bcf5ed71132e740d457044c6` | No |

All five files are 117,656 bytes and name Edgar Vigdal as author. The shop
placement also agrees with the manual’s every-fourth-level rule.

## Confirmed levels 6–20 metadata

| Level | Source title | Mode | Entities | Enemy sheet | Raw LVD SHA-256 | Shop after |
| ---: | --- | ---: | ---: | --- | --- | --- |
| 6 | empty | 1 | 20 | `alien_2` | `455e9317c7c88949e2a01f6bbc0a7e9d2ab123c65212ca755b285cad2c748f55` | No |
| 7 | empty | 1 | 29 | `alien_2` | `c8166c50a69d3b8d18a64105001b294620e7a34a9a8807aa44ab0a9c6ecb124e` | No |
| 8 | `* * *  B O N U S   L E V E L  * * *` | 3 | 20 | `alien_2` | `ec06689d53be07b5b4a276892ab00798db347382e2cb42f03d2150f87ff8d743` | Yes |
| 9 | empty | 1 | 24 | `alien_3` | `cb74b30c90700fdbc4d99e8f0fd8f05033f33acc6d507b53a07d4e0d7c934fc7` | No |
| 10 | empty | 1 | 30 | `alien_3` | `9e35777eafe10d504464ee0804ea60983abfe4b8239c0e2805a529d7312b94e0` | No |
| 11 | empty | 1 | 33 | `alien_3` | `2c8dc69d4f373f3d0b4796c41045e645be7a5aa0e574d7db20f02744efddacfe` | No |
| 12 | `K A M I K A Z E` | 2 | 25 | `alien_3` | `8888909c4f7a8f4bcd024d035cfbdef3ee590d075c723f5c230773049aff3a86` | Yes |
| 13 | `DEJA VU.....` | 1 | 24 | `alien000` | `d8ba943e3acfe6fa21ee4177d383cbf9114de8f7b97c4de95137873afadd62b8` | No |
| 14 | empty | 1 | 28 | `alien000` | `1a654e1a3ce7caefde5517ab1b661e2387977d5abd00ab36548dfb57659744a1` | No |
| 15 | empty | 1 | 34 | `alien000` | `1debac1fbaa5e4b2c98e2aaf6519f249ca8dd2a744a5dee24ff5e7ac5da66991` | No |
| 16 | `* * *  B O N U S   L E V E L  * * *` | 3 | 30 | `alien000` | `21fad6d67bed291923c03fe177370e0f9f2b5777258c07ce0896f30a4b80ed12` | Yes |
| 17 | empty | 1 | 32 | `alien_lilla` | `b5f4e31dbce7ef30b1615768d35eb90b22b0ae39ce439ac108af851fc5f723a5` | No |
| 18 | empty | 1 | 34 | `alien_lilla` | `f91d59b3f2464c5709c3056219208ab0735f045faffa00c2670d062ed4a7f1cf` | No |
| 19 | empty | 1 | 30 | `alien_lilla` | `30c5e49b1486de3dd50f53a58fc0b30df0c141057e3c137fa4b1178c955079e2` | No |
| 20 | `K A M I K A Z E` | 2 | 30 | `alien_lilla` | `33dc4133c6caf4575a46c4ee56659f7eff884aa498d1ada07f81874a17e2fc62` | Yes |

Levels 3, 7, 11, 15, 19, 23, 28, 32, 36, 40, 44, 48, 53, 57, 61, 65, 69,
73, 78, 82, 86, 90, 94, and 98 contain active supplemental spawns.
`LVD_CLASSIC_LEVELS.md` records exact groups, paths, supplemental and fixed
records, scores, new enemy assets, and the bounded executable-backed mode-3
rules. `classic_levels.json` is the unified machine-readable authority.

## Confirmed levels 21–35 metadata

The `Slot counts` column uses `resource_slot_id:enemy_count`. Level 25's mode-4
records are interpreted only by the separately pinned boss contract.

| Level | Source title | Mode | Authored entities | Slot counts | Raw LVD SHA-256 | Shop after |
| ---: | --- | ---: | ---: | --- | --- | --- |
| 21 | empty | 1 | 32 | `1:24, 2:8` | `1188e5921436ec80804c209541b4c8d4ce22fbea8422d738a4fecb16197afd5a` | No |
| 22 | empty | 1 | 30 | `1:20, 2:10` | `7caa3564e1f551b29414faa751088066bee360fb443efa686864992129716a72` | No |
| 23 | empty | 1 | 26 + 2 supplemental | `1:16, 2:10` | `86ff2053ef0983bb58f3625431171d014336d168a26254257059319883ff9979` | No |
| 24 | `* * *  B O N U S   L E V E L  * * *` | 3 | 30 | `1:30` | `d71a08ff42e78c41edb4362c3db5e74c77203c29905b0b576ebdaab9d5bcbe2e` | Yes |
| 25 | `* * * *   B I G  T R O U B L E  * *` | 4 | 16 + 1 supplemental record | `1:10, 0:6` | `c8ac14a7c8a064e1904accdf8a2d763e7ff8a05210a4cdc9d197f9eba43c560c` | No |
| 26 | `GOING TO THE MOON` | 1 | 25 | `1:25` | `bfde5523953e9005a89685b1477939252fd63190f2aaeb92432f5d8130a4e14f` | No |
| 27 | empty | 1 | 22 | `1:14, 2:8` | `ee9d6f6352d6b979dbd36c8bc59c4ac15a68bda7c6cf49d1cbb4f11f1a60e83c` | No |
| 28 | empty | 1 | 24 + 2 supplemental | `1:16, 2:8` | `7124d57b5d85994898058992dc962af6d3804a6f477ca021c027163663fc0853` | Yes |
| 29 | `K A M I K A Z E` | 2 | 36 | `1:36` | `5c79d73bd15cdebc763f79c5b61d9f1deca9ae7795ea90bad28c63e65db47d89` | No |
| 30 | empty | 1 | 30 | `1:24, 2:6` | `7a10646f11ea7f4e287f3432abe287640de25fe860bd784a9b694442565679d7` | No |
| 31 | empty | 1 | 28 | `1:16, 2:12` | `0bf2a4dcb3a79be4ab0ea6f78a77410dae9ab606efa24de198cb9b954f99ba19` | No |
| 32 | empty | 1 | 18 + 3 supplemental | `1:12, 2:6` | `05ce934465c2b1d676171aafeff191c0cd2008095e720502e4d85a485c810b93` | Yes |
| 33 | `* * *  B O N U S   L E V E L  * * *` | 3 | 30 | `1:15, 2:15` | `7d411500d5f0051f808d955a83369cb2270dcdc32f6658ab9104ed408d14c839` | No |
| 34 | `S Q U A R E S` | 1 | 30 | `1:20, 2:10` | `a81d2fa87a458a1433dfb2f091dc2e2f6a637ede5318ea9abce1544e2a1250da` | No |
| 35 | empty | 1 | 36 | `1:24, 2:12` | `a5a99f338362778d89b21c4a5633f3475cd2fb5d411dc0aa70cfe81d94ba85e4` | No |

## Confirmed levels 36–50 metadata

| Level | Source title | Mode | Authored entities | Slot counts | Raw LVD SHA-256 | Shop after |
| ---: | --- | ---: | ---: | --- | --- | --- |
| 36 | empty | 1 | 48 + 3 supplemental | `1:28, 2:20` | `32c07f826ccd01339a6f7c317b9f9ce918a9d406a1a83817879100421a4015d6` | Yes |
| 37 | `K A M I K A Z E` | 2 | 36 | `1:36` | `773682a0039bf91617b5e47b2bedd945ff92c4d636fb54d624e0a83dd513344a` | No |
| 38 | empty | 1 | 36 | `1:36` | `7538ddd7e703bac2518fa60346929dbe594cb5025beba04f92ad920f76406ee4` | No |
| 39 | empty | 1 | 40 | `1:32, 2:8` | `73379105938feb131a60063efda747ace668168dfe99814628e08f2ef6a35772` | No |
| 40 | empty | 1 | 30 + 4 supplemental | `1:30` | `1efa85e858c4668e0fbac60c77b65c89d3b0813fdff841cfbdcd5c14799550ed` | Yes |
| 41 | `* * *  B O N U S   L E V E L  * * *` | 3 | 40 | `1:40` | `5bc28174aa8b4aea0e7e0bd1e45cfa0ccfd9ef8b2a476da7e857a1921b8b3d82` | No |
| 42 | empty | 1 | 60 | `1:60` | `cb8742813e53d02135245521a9f6f954670ebaa36a567740a2078ab95024c1c9` | No |
| 43 | empty | 1 | 40 | `1:40` | `e440b3812197ec63a880e8f38bdb986f8df84ea709ffbd08e0d4b294e24e3157` | No |
| 44 | empty | 1 | 52 + 4 supplemental | `1:40, 2:12` | `0e53c0a4f98f39a14c0dbacc72afdd60eadc0cf7c8d5e2adf947948fe8ce9a60` | Yes |
| 45 | `K A M I K A Z E` | 2 | 30 | `1:30` | `c2f3e865e4b0dbda6e950219f1aa50e02a81a017a7f55b58f49ea628b348d3ba` | No |
| 46 | empty | 1 | 90 | `1:90` | `bd6b544381816314be6e900c680b4f3a42d780658b5652ac7d3c47ee765080d5` | No |
| 47 | empty | 1 | 60 | `1:60` | `1ee7741f5a753c3b4d36efa9a37fccc46866c43ec393236a0a78f8e69fbeb321` | No |
| 48 | empty | 1 | 90 + 4 supplemental | `1:90` | `2374047dc174c5b72fa151b02255253836ef8d2501a168a1ce65da31f0203775` | Yes |
| 49 | `* * *  B O N U S   L E V E L  * * *` | 3 | 40 | `1:40` | `5a27f4a840de7d650c0de0bb51d02a1ed990b0f66e641024a596c4846f7ce41d` | No |
| 50 | `* *   B I G  T R O U B L E   * *` | 4 | 14 + 1 supplemental record | `1:8, 0:6` | `d618806d1994bd2df44371b3451c5786a727daaf4ef212da987fcc05c9619db2` | No |

Level 36 is the first LVD with two active supplemental records; their three
entities select both declared resource sheets and use four animation phases.
The `Shop after` column is the ordinary cadence flag. Levels 41 and 49 instead
use the recurring mode-three post-Warp shop contract.

Levels 1–25 select `stars1`; levels 26–50 select `stars2`; levels 51–75 select
`stars3`; levels 76–99 select `stars4`; and level 100 uses the modulo remainder
mapping to `stars1`. Level 25 is terminal only when explicitly configured as the
match boundary; the full campaign continues to level 26.
Level 50's independent exact state-13 contract binds all six `alien_big2`
resources. It is terminal when `end_level=50`; the default campaign instead
hands off exactly once to level 51.

## Confirmed levels 51–62 metadata

| Level | Source title | Mode | Authored entities | Slot counts | Raw LVD SHA-256 | Shop after |
| ---: | --- | ---: | ---: | --- | --- | --- |
| 51 | `HALF CENTURIE` | 1 | 76 | `1:76` | `f0f9d2773e953b52df3839645e671754b99822e3f458ad337b1433bbc6b896b8` | No |
| 52 | `W O R M S` | 1 | 120 | `1:120` | `5f017642a15b80fb760ea47c71bcb4bc314416541c7c9523ee96492341d9b1b3` | Yes |
| 53 | empty | 1 | 30 + 4 supplemental | `1:24, 2:6` | `f50fd98269363d89c1f60a8c1ac74811e8f40bffd3b15d7450ea2d6a13078a48` | No |
| 54 | `K A M I K A Z E` | 2 | 36 | `1:36` | `5b45d80c0115c0d1090bd7e50aacae4574343e3d0889ad9d5230a2587d3c65cc` | No |
| 55 | `MORE AND MORE` | 1 | 60 | `1:20, 2:20, 3:20` | `e5f7dcf31adbd6120bfe111440e8f2dc7e1105f42204219b8ca052e8a24040c0` | No |
| 56 | empty | 1 | 126 | `1:96, 2:15, 3:15` | `34b16e5b79443f6a7f26ea03f5f21c93774a863e71aa85acdf27621b1026c134` | Yes |
| 57 | empty | 1 | 110 + 4 supplemental | `3:110` | `4075b0386414775546a162f20ed3a64e4b988e0bdbd2a88383c104f81b6c957d` | No |
| 58 | `* * *  B O N U S   L E V E L  * * *` | 3 | 80 | `1:40, 2:40` | `dbe38e8c34e2b76e09530981df118f5354e65641d5184b59508371feebfb1717` | No |
| 59 | `FIRE FLIES` | 1 | 40 | `1:40` | `8fe7d99f71cd836f8f73c5afe7e6eabb4710b869e95d23eabe0a6eee4a55797c` | No |
| 60 | empty | 1 | 46 | `1:30, 2:16` | `09901b45fe4d24e0da9e945161c17bf45d59a9f61dd9550fd559b19dda8e52db` | Yes |
| 61 | empty | 1 | 22 + 4 supplemental | `1:22` | `2767de87ae0e6d5335d1dc2b5edc4a1d7262a83c43523a8512de63097b4132a7` | No |
| 62 | `K A M I K A Z E` | 2 | 25 | `1:25` | `ed86616a4a51717733cf52d4a19b935202afbb59eb0a4b688fe127313465cb73` | No |

Levels 51–62 select `stars3` and use the nine new `gultop`, `kreps`, and
`ving` family sheets, with `alien_rakett_gronn` reused at level 54. The
ordinary cadence shops follow levels 52, 56, and 60. Level 58 uses the shared
mode-three result/Warp/post-Warp-shop contract. The full campaign continues to
the source-backed level 63 rather than treating level 62 as a boundary.

## Confirmed levels 63–100 metadata

`LVD_CLASSIC_LEVELS.md` and `content/levels.json` pin the remaining 38 LVDs,
including mode 6, the late mode-3 occurrences at 66, 74, 83, 91, and 99, the
level-75 `alien_big3` boss, the mirrored level-100 `alien_big4` boss, all late
resource scores and supplemental records, and the authored every-fourth-level
shop flag through 100. Terminal level-100 routing suppresses a reachable shop
and starts the 13-slide ending/credits sequence.

## Confirmed weapon facts

The executable’s weapon switch, root-prototype table, damage table, recursive
spawn graph, dimensions, movement tables, spawn offsets, damage store, and
collision subtraction path were traced together. These are not labels inferred
from neighboring bytes.

| ID | Weapon | Root | Flattened projectile prototypes | Damage per projectile |
| ---: | --- | ---: | --- | ---: |
| 0 | Single Shot | 0 | 0 | 1 |
| 1 | Double Shot | 1 | 1, 66 | 2 |
| 2 | Triple Shot | 9 | 9, 14, 15 | 3 |
| 3 | Quad Shot | 4 | 4, 63, 65, 64 | 2.5 |
| 4 | Super Triple Shot | 8 | 8, 6, 7 | 4 |
| 5 | Plasma | 18 | 18 | 5.5 |
| 6 | Fireballs | 25 | 25, 26, 30, 31 | 6 |
| 7 | Laser | 22 | 22, 23, 24, 50 | 10 |
| 8 | War.I.Plasma | 19 | 19, 20, 21 | 15 |

Manual fire is edge-latched and has no universal cooldown. Auto Fire repeats
only when the current absolute millisecond value is strictly greater than its
deadline, then schedules 100 milliseconds; Super Auto Fire schedules 25
milliseconds. An expired Auto deadline may emit a second volley in the same
update as a manual-edge volley.

Projectile capacity counts every live root and recursive child, checks only
once before a volley, starts at 5, caps at 50, and loses one upgrade on death.
Recursive offsets are independently relative to the original fire origin.

Fireballs secondary values 190–200 encode one-time spawn-X jitter;
War.I.Plasma values 163–165 encode time-scaled random horizontal velocity. The
Laser uses persistent chain `22 -> 23 -> 24 -> 50 -> -1`: X is latched at fire
time, its collision column runs from screen top to the owning player's live Y,
and ordinary-enemy damage halves after each collision without consuming the
beam. Exact spawn/collision geometry, collision-before-update order, and its
four live-frame opportunities are in `WEAPON_RUNTIME_TRACE.md`.

## Confirmed first-shop facts

The executable initializes item prices to:

`50, 75, 100, 150, 200, 300, 400, 500, 600, 750, 800, 990, 1000, 1250, 1500, 2000, 3000, 5000, 15000, 30000, 500000`

The first shop exposes IDs 1–17. IDs 18–20 require a best hit percentage above
level 25 of at least 70, 80, and 90 respectively. ID 21 requires the profile
shield mask `0x3f`. The full item names, IDs, prices, gates, and instruction
addresses are in the manifest. The first-shop dispatcher also proves
same-weapon/cap rejection, Extra Time's `+5` pre-check behavior, Rank Marker's
six-bit/full-mask reward, and Game Secret's 30-image selection with no gameplay
upgrade.

## Confirmed Rocket Pack and Alien Lock facts

`content/ordnance.json` is generated from byte-pinned purchase, secondary-input,
missile update/render/collision, Warp/death, final-kill, save/load, accuracy, and
player-initialization regions. The trace is complete and its gameplay-critical
closure list is empty; `ORDNANCE_RUNTIME_TRACE.md` records every executable
range and hash.

Rocket Pack adds 10 and clamps at 50, rejecting an already-full pack without a
charge. Release-armed secondary fire uses the shared 100-record physical player
projectile pool. A successful shot performs one weighted target draw and two
animation draws, consumes one missile, deals 200 ordinary damage or 20 to the
state-13 boss, and renders/collides through the `768×72` rocket TGA/HMA. Pool
or target failure consumes no missile and requires release before retry.

Alien Lock is not a missile-homing upgrade. It preserves each owning seat's two
captured-alien fields through Warp and clears on ordinary death while leaving
rocket inventory intact in every currently supported match mode. The
executable match-mode value 6 is Time Trial mode, so its reset exception
applies only in that match mode and never to Warp or Warp Malfunction; it is distinct from authored LVD mode 6,
whose aimed-shot setup, speed multipliers, and terminal opcode are now pinned.
Any allocated player projectile disqualifies the
alien-projectile final-kill reward. Missile fire does not increase the ordinary
shot denominator, while a missile hit does increase the shared hit numerator;
the retail percentage is clamped to 100.

## Recovered behavior

The executable-backed lossless LVD decoder now establishes all 100
levels' group and enemy counts, entry origins, formation targets, activation
delays, initial velocities, base health, kill cohorts, path accelerations,
path thresholds, and observed opcodes. `content/levels.json` embeds those
authored records and the deterministic simulation consumes them directly.
The recurring mode-3 result controller additionally binds levels 8, 16, 24,
33, 41, 49, 58, 66, 74, 83, 91, and 99 to
per-player hit ownership, reveal rewards, perfect-chain progression/reset,
deadlines, Warp, and shop handoff in `content/bonus_modes.json`; its legacy
level-8 projection remains synchronized for replay compatibility.

Post-entry tracing additionally establishes:

- state-2 formation easing, six-frame loop/bounce animation, timer-B SWD launch
  draw, global 14-path selection, and first-five follower-copy behavior
- state-3 SWD fixed-point load, explicit-Euler order, strict truncated-progress
  comparison, zero sentinel, numeric terminal selectors, and late-tail routing
- state-1/3/4/6/10 timer-A firing roles, proximity adjustment where applicable,
  and kill-pass timer tightening
- state-4 dedicated roaming vector, randomized turns, and strict wraps
- level-4 state-10 acceleration/flip/motion/deactivation and animation order
- level-3 supplemental state-6 spawn/resource/health/timers, base motion/wrap,
  steering, aimed type-6 firing, and health-scaled bounce animation
- the five-word PRNG, MSVCRT initializer, integer/float32 wrappers, level-load
  draw order, common-pool phase reuse, and projectile frame/collision ordering
- all non-boss levels through 100 ordinary-path LVD scores, group/cohort rewards, falling-bonus
  selection and all 37 dispatches, Scoop/Freeze, final-kill rockets, death
  deadlines, completion, watchdog diagnostics, and every-fourth-level
  Warp/shop routing; the full production-pixel route-assist campaign matrix
  proves that no level resolves through the watchdog, while focused tests own
  the shipped starting-loadout, fighter, rocket, and economy boundaries
- Warp startup progression, the 400-update mode-13 sequence, type-15's
  first-five skip barrier, mode-16 malfunction resources and shared-RNG order,
  state-6 malfunction enemies, six-color gem rewards, and the full-mask
  mode-20 promotion timing/RNG boundary
- Easy/Normal/Hard/Ace scales, timer values, projectile speeds, player speed
  lattice, fighter count, Armour, and difficulty borders
- HMA byte format and exact enemy/fighter/player-projectile source rectangles
- Memory Station's board growth, weighted tile/effect tables, scoring,
  deadlines, success/failure flow, and original presentation assets
- Meteor Storm's 30-slot spawn/motion/collision controller, biased bonus draw,
  cash/score/gem rewards, difficulty growth, result thresholds, and assets
- exact rank-0 speech queues and padding for profile ranks 1–20
- level 25's dedicated state-13 initialization, six-sheet stages and HMA parts,
  projectiles, damage/rewards, music, death sequence, and conditional level-26
  bridge
- levels 26–49 mixed-resource groups and slot-specific scores; supplemental
  animation through levels 32, 36, 40, 44, and 48; mode-2 levels 29, 37, and
  45; recurring mode-3 routing through levels 33, 41, and 49; cadence shops
  through level 48; and the `stars2` presentation boundary
- level 50's independent state-13 payload, six Big2 sheets, opcode-3 mode-7
  aim enable, 500 health, 1,377 aimed-fire timer, 1,000,000-point reward, and
  conditional terminal/level-51 bridge
- levels 51–62 mixed-resource groups and slot-specific scores; supplemental
  records at levels 53, 57, and 61; mode-2 levels 54 and 62; recurring mode-3
  routing at level 58; cadence shops through level 60; and the `stars3`
  presentation boundary
- levels 63–99 late resource families and exact mode-1/2/3/6 paths;
  supplemental records at 65, 69, 73, 78, 82, 86, 90, 94, and 98; cadence
  shops; and `stars3`/`stars4` presentation boundaries
- levels 75 and 100 exact state-13 payloads, Big3/Big4 HMA data, authored burst
  groups, aimed-fire origins, rewards, and conditional terminal routing
- level 100 terminal ending with 13 byte-pinned slides, executable-extracted
  story/credits text, exact slide/text timing, controls, and `endgame` music

The remake implements those bounded rules on its authoritative 60 Hz clock.
Its rational integer arithmetic is a deterministic modernization of retail
float32 behavior.

## Product and evidence closure

Every actionable gameplay and presentation item for the finite levels 1–100
macOS product is tracked in `../GAP_MATRIX.md`. All presentation rows are
closed, and every gameplay row is closed except G19, the hurry-up secret ships:
their spawn contract, per-mode deadline, and four motion-handler addresses are
traced, but the handler bodies are not yet read and the feature is not
implemented. The other boundaries are deliberately classified:

- deterministic seeding, fixed-point/rational authority, simultaneous co-op,
  server authority, high-refresh interpolation, and the unproven ending
  firework cadence/particle layout are intentional modernizations; the bounded
  SFX mix values and accessible composition/timing around native screen
  bitmaps are explicit macOS policies rather than retail reconstruction claims
- simultaneous shared-party co-op is the intentional modernization and the
  only two-player mode in the product; the retail two-player modes (Duel and
  alternating) were removed by user decision (2026-08-10) and stay preserved
  on the `retail-two-player-modes` branch
- raw LVD/SWD/difficulty/audio fields without a reachable runtime consumer are
  evidence-only and retain neutral names and exact bytes
- tracker-module (`.mus`) playback is a permanent product non-goal; the
  extracted MP3 soundtrack is final, and module files are not investigated,
  extracted, converted, emulated, implemented, or scheduled
- play beyond level 100, unrelated assets, and retail-asset redistribution are
  explicit non-goals
- trusted online hosting and cross-platform delivery are separate
  infrastructure programs; Time Trial ships as retail match mode 6

Predecessor `waves` records remain read-compatible decoding scaffolds, but v9
authoritative play consumes explicit runtime contracts. All four state-13 boss
contracts and authored late mode/path exceptions are exact.

## Rights boundary

The assets remain third-party original-game material. Their presence here
reflects the user-requested local remake workflow and does not grant
redistribution rights.

The release history remains local. The extracted retail assets must not be
pushed, published, or distributed.

The bundled voice-pack notice
`data/samples/voices/1/readme.txt`
(`ac3578dd556a6346bb83a942f5764b2a1c0c898f1c682fd4cd42cff8fcf90da8`)
reserves rights and specifically restricts copying, redistribution, and
modification. For this user-requested local Warblade remake, the pipeline copies
only the 31 rank-0 cues used by the executable-proven ranks 1–20 promotion
queues, Memory Station, Meteor Storm, and Warp malfunction. Every other
voice-pack file remains excluded; the generated manifest does not grant
redistribution rights.
