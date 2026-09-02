# Retail big boss state 13

- Level-25 contract: `retail_big_boss_v1`
- Canonical level-25 authored payload SHA-256: `6ec7ac4f9f5eb5ea7a074d0315a2393acc37da1b0f1fd8f08f9b2c9032a6498f`
- Level-50 contract: `retail_big_boss_level_50_v1`
- Canonical level-50 authored payload SHA-256: `c4ae166f52d970d2e099ae82edab819d24904473cec5f80cdfbc55917f3494bd`
- Level-75 contract: `retail_big_boss_level_75_v1`
- Canonical level-75 authored payload SHA-256: `daa437aca2a5fe322fef8941a3632d2962da6c7d3d627eca9cae46887af4c64d`
- Level-100 contract: `retail_big_boss_level_100_v1`
- Canonical level-100 authored payload SHA-256: `ccc5c188f1c4f4e1344d831c759d01590159ccb99b02ae935784a2283bb56f47`
- Executable SHA-256: `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`
- Generated `bosses.json` SHA-256: `979dc649d4108afdd654e33219557389e13b7170b4b74301a89f4c3fe68d8002`
- Source encounters: levels 25, 50, and 75 use LVD mode 4 with group modes `4,5,6,7,7`; mirrored level 100 uses `4,5,6,6,7,7`.
- Trace status: exact and complete; runtime loading must reject a false or missing `exact_trace_complete` gate.

## Pinned trace entry points

| Role | Virtual address |
|---|---:|
| init | `0x00569260` |
| update | `0x00605fe0` |
| collision | `0x00585840` |
| mark | `0x00555c40` |
| dispatcher | `0x005afc50` |
| renderer | `0x00618560` |
| projectile type 15 spawn | `0x00612fc7-0x006132bf` |
| projectile type 14 spawn | `0x00614031-0x006143cf` |
| common projectile update | `0x006027e3-0x00602de0` |
| projectile renderer | `0x00603808/0x00603b32` |
| projectile player collision | `0x005842c0` |
| projectile hma collision | `0x00625a50` |
| global sound gate thunk | `0x00525924->0x00567990` |
| global sound gate dispatch calls | `0x005b0c72/0x005b0d96/0x005b10ac/0x005b1191/0x005b1280` |
| get ready to level transitions | `0x005abac2/0x005abfc0` |
| warp to shop transitions | `0x0061bce8/0x0061be78/0x0061c082` |
| rank ready storage and initialization | `DAT_008487b4@0x006245a2` |
| rank ready shop producer | `0x00565094` |
| rank ready state 13 samples | `0x005860a7/0x00588340/0x0058a2fc` |
| only blue storage and initialization | `DAT_008489d4@0x00624487` |
| only blue persisted hydration | `0x005495ec` |
| only blue runtime producer | `0x00578b90` |
| only blue state 13 sample | `0x0057116e` |

All `*_rng` arrays record the retail half-open call arguments unless a field says otherwise. The first two arguments in every death SFX tuple are deliberately retained as the retail unsigned reversed-bound bug (`216,190`); they are not normalized or reordered.

The authoritative JSON preserves each encounter's six animation sheets, exact two-part packed renderer and per-part hit-flash countdown, state-13 collision and attack constants, exact death event ordering, destroyed-count completion mark, unchanged rank-marker policy, and reward scale. Its v4 routing contracts separate retail next-level intent from configured campaign boundaries at 25, 50, 75, and 100. Level 50 pins opcode 3, the 1,377 aimed-fire timer, ten dynamic opcode-2 records at speed 5.0, and Big2 HMA bounds. Level 75 pins 613 health, a 5,000,000-point reward, one reverse 16-record burst at speed 4.6, and group-3/4 aimed origins. Mirrored level 100 pins a 10,000,000-point reward, two reverse four-record bursts at speed 7.5, opcode-6 terminal paths, group-4/5 aimed origins, and rejection of level 101. The contracts also pin the retail-high effect preset, all five bounded pool capacities and update order, plus the per-physical-player `rank_ready` and `only_blue_coins_active` RNG branches. The gameplay-critical closure list is empty.
