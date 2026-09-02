# Rocket Pack and Alien Lock runtime trace

- Contract schema: `warblade.ordnance.v1`
- Executable SHA-256: `ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef`
- Generated `ordnance.json` SHA-256: `b9b424d17fff3cfb85b7d012f7ec353cb03a5cf24a363e86832456b9cf8a6467`
- Trace status: exact and complete; the gameplay-critical closure list is empty.

## Retail contract corrections

- Rocket Pack adds 10 and clamps at 50. A pre-purchase count of 50 or more rejects without charging; counts 41 through 49 still pay and clamp to 50.
- Alien Lock preserves the owning seat's two captured-alien slots (occupied flags, saved indices, and state-8 records) through Warp. It has no homing, weighting, reservation, or RNG effect on rockets. Ordinary death consumes the lock but preserves rocket inventory in every supported remake match mode.
- Retail match mode 6 is Time Trial (`0x0059c8a7-0x0059c91d`), not a gameplay phase. It skips the entire death-loadout reset. Time Trial is a separate product program, so this exception must not be applied to current level, Warp, or Warp Malfunction phases.
- Secondary fire is release-armed. A pool-full or targetless press costs no rocket, makes no sound, and requires release before retry.
- Rockets share the 100-record physical player projectile pool. Successful spawn consumes one rocket, uses one weighted target draw followed by the two animation draws, and records the firing physical seat as owner.
- A rocket deals 200 to ordinary enemies. State 13 uses strict local boss bounds, no HMA damage test, and `max(1, damage/10)`, so a rocket deals 20 before the boss controller owns terminal behavior.
- `DAT_00e11346` is an any-player-projectile-allocation flag, not a rocket-fired flag. Both successful primary and missile allocations disqualify the alien-projectile final-kill reward.
- Missile fire increments a separate rocket counter, not the ordinary-shot denominator. Confirmed missile hits do increment the shared hit numerator; retail clamps the computed percentage to 100.

## Byte-pinned executable regions

| Role | Virtual address | Bytes | SHA-256 |
|---|---:|---:|---|
| rocket pack purchase | `0x00562007` | 176 | `97c0220e3a8d757d02c8eb7a4d00a2e077ef06281fe55b525789f3a08f4f1614` |
| alien lock purchase | `0x00561f92` | 112 | `ed0d0e47518ad751608d554643edc208b8305a17e7198aa8e9d419b0c46ee297` |
| secondary input target and spawn | `0x005ebb6e` | 1232 | `26a6e21c46cdb24682f73133e3100a49cfc13ffcaaae90f5bfe3a3a035529a49` |
| missile update | `0x0061fff0` | 2288 | `48fa98b2b573ea8436bd0e291805a3e99b157b7ba53f7fadcad414a22ba17e2a` |
| missile render | `0x006211e0` | 1040 | `4ac9d7741aeb13aa0f46503ca0033e857069b87e69cd270341e1a7be5ed1f8e6` |
| player projectile enemy collision | `0x00585840` | 7424 | `1ed35c685d70a977f7deb74719dba25697acb12f27d8c420e29e0a687ac44da5` |
| warp alien lock retention | `0x0055da8c` | 168 | `b058cb6b5e2574ba099df1a781a7df8baac6e2dda07a243b028c80f73e6ef850` |
| ordinary death alien lock clear | `0x005719d8` | 32 | `507c5aaee7f7b67007df7b20452c40ab7b271b5ad6929eaabc66dbb77d0f4eae` |
| final kill projectile reward | `0x00555d08` | 880 | `01fc20ec14e492c8bb57dab17c1217d93906d3fc98a84fd6393b6dbaccf85fe0` |
| final kill rocket inventory reward | `0x005562b2` | 162 | `078953b55d4771388529f71bc72870ea4b4ca4467f8db0915997911c9bf0cdab` |
| saved game snapshot writer | `0x00537c80` | 928 | `586da2f9c89cf79c075793a76fed08f47930807202cf132d79e796d6aa12c2c8` |
| saved game snapshot loader | `0x005384f0` | 2064 | `bdfc973ce575edaacae60128163ff94d6348ec2b53793a5ca012845db9ab5d95` |
| above level 25 accuracy sample | `0x005696f0` | 224 | `d37ed95d889d4ce60b10586b1d13420c68735d0fc97150533794f8f2f3f83352` |
| new player initialization | `0x00623980` | 1424 | `d771cc1cb0d62a989c6d5936fc2342dd822f795503e83e33cc1af485df97218f` |
| retail match mode identity switch | `0x0059c8a7` | 121 | `79f5cd01d6827784ed74a944c67e2ac8a585a19f32f082e2f6a968287e3ea48f` |

## Runtime ordering

The weighted scan admits active, unreserved records whose targetability scalar is at most 1, excluding states 5 and 8. States 6, 9, 11, and 12 have weight 8; states 13 and 18 have weight 16; all remaining admitted states have weight 1. State 13 and 18 targets are deliberately not reserved. Alien Lock on and off traverse identical candidates and consume identical RNG.

After the target draw, spawn consumes `RngInt(0,3)+4` for animation period and `RngInt(0,3)+3` for its initial countdown. Expiry consumes the explosion-frequency draw before flare draws. Steering consumes RNG only for an exact circular-direction tie. Cosmetic effects remain synchronous users of the root match RNG.

## Missile movement tables

The X lookup uses indexed base `0x007d0454` and bytes `0x007d0458..0x007d04d4` (SHA-256 `1a8c81e2f605d5b8aae5235be63f1e9ad91892d3b12fa2f3ab0a9d309d37f35f`). The Y lookup uses indexed base `0x007d04d4` and bytes `0x007d04d8..0x007d0554` (SHA-256 `23215a2cde67659ddb17a6afc02fb0fed3f17f189ce8f95e565d6e4c9346ce3a`). The heading itself, 1 through 32, is multiplied by four and added to each base; there is no heading-minus-one adjustment in the executable load.

| Heading | X binary32 | Y binary32 | X Q16 | Y Q16 |
|---:|---:|---:|---:|---:|
| 1 | `0x00000000` | `0xbf800000` | 0 | -65536 |
| 2 | `0x3e47c5c2` | `0xbf7b14be` | 12785 | -64277 |
| 3 | `0x3ec3ef15` | `0xbf6c835e` | 25080 | -60547 |
| 4 | `0x3f0e39da` | `0xbf54db31` | 36410 | -54491 |
| 5 | `0x3f3504f3` | `0xbf3504f3` | 46341 | -46341 |
| 6 | `0x3f54db31` | `0xbf0e39da` | 54491 | -36410 |
| 7 | `0x3f6c835e` | `0xbec3ef15` | 60547 | -25080 |
| 8 | `0x3f7b14be` | `0xbe47c5c2` | 64277 | -12785 |
| 9 | `0x3f800000` | `0x00000000` | 65536 | 0 |
| 10 | `0x3f7b14be` | `0x3e47c5c2` | 64277 | 12785 |
| 11 | `0x3f6c835e` | `0x3ec3ef15` | 60547 | 25080 |
| 12 | `0x3f54db31` | `0x3f0e39da` | 54491 | 36410 |
| 13 | `0x3f3504f3` | `0x3f3504f3` | 46341 | 46341 |
| 14 | `0x3f0e39da` | `0x3f54db31` | 36410 | 54491 |
| 15 | `0x3ec3ef15` | `0x3f6c835e` | 25080 | 60547 |
| 16 | `0x3e47c5c2` | `0x3f7b14be` | 12785 | 64277 |
| 17 | `0x00000000` | `0x3f800000` | 0 | 65536 |
| 18 | `0xbe47c5c2` | `0x3f7b14be` | -12785 | 64277 |
| 19 | `0xbec3ef15` | `0x3f7b14be` | -25080 | 64277 |
| 20 | `0xbf0e39da` | `0x3f6c835e` | -36410 | 60547 |
| 21 | `0xbf3504f3` | `0x3f54db31` | -46341 | 54491 |
| 22 | `0xbf54db31` | `0x3f3504f3` | -54491 | 46341 |
| 23 | `0xbf6c835e` | `0x3f0e39da` | -60547 | 36410 |
| 24 | `0xbf7b14be` | `0x3ec3ef15` | -64277 | 25080 |
| 25 | `0xbf800000` | `0x3e47c5c2` | -65536 | 12785 |
| 26 | `0xbf7b14be` | `0x00000000` | -64277 | 0 |
| 27 | `0xbf6c835e` | `0xbe47c5c2` | -60547 | -12785 |
| 28 | `0xbf54db31` | `0xbec3ef15` | -54491 | -25080 |
| 29 | `0xbf3504f3` | `0xbf0e39da` | -46341 | -36410 |
| 30 | `0xbf0e39da` | `0xbf3504f3` | -36410 | -46341 |
| 31 | `0xbec3ef15` | `0xbf54db31` | -25080 | -54491 |
| 32 | `0xbe47c5c2` | `0xbf6c835e` | -12785 | -60547 |

The Q16 projection decodes the pinned binary32 word, multiplies by 65536, and rounds to the nearest integer (ties away from zero; no table entry is tied). At retail speed 10, multiply the selected Q16 component by 10, then apply the existing `simulation_scale_numerator / 6` with truncation toward zero before adding it to the position.

The retail Y table is intentionally not normalized: headings 18 and 19 both contain `0x3f7b14be`. This shifts the remaining second-half values, so a host `sin`/`cos` call or symmetric direction-table derivation is gameplay-incompatible.

The checked JSON is authoritative for field offsets, lifecycle, per-seat and Duel ownership, HMA-backed 32-by-3 atlas rendering, collision teardown, the stale counter-contribution quirk, final-kill qualification, and accuracy accounting. Runtime loading must fail closed if the trace gate, required rocket assets, HMA domain, or state-13 boss contract is absent.
