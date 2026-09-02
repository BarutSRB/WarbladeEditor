# Warblade SWD Attack-Path Contract

This document closes the retail `attNNN.swd` format and the first-five-level consumer path by static analysis. No runtime screenshot or visual approximation is used. The lossless decoder is `tools/swd_decoder.py`; its deterministic regression test is `tools/swd_roundtrip_test.py`.

## Evidence identity and confidence

The analyzed `Game/warblade.exe` has SHA-256:

```text
ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef
```

Addresses are 32-bit PE virtual addresses for that executable.

- **Proven** means the file read/copy and a complete relevant consumer were traced.
- **Supported** means the bounded control flow is clear but a human-readable semantic name is not fully closed.
- **Evidence-only** retains the exact raw value without inventing a label when
  no reachable finite-product consumer exists.

## Loader and fixed-size file layout

The loader begins at `0x00567bb0`. It formats `att%03d.swd`, probes numeric indices 1 through 50 inclusive, and reads exactly `0xbe0` bytes for each successful open at `0x00567c81`. Successful files are compacted, without gaps, into the runtime array at `0x00ad00b0` with stride `0xbe0`; the copy is at `0x00567f84`. The loaded count is stored at `0x00d622c0`.

The complete disk layout is:

| Offset | Size | Proven contents |
| --- | ---: | --- |
| `0x0000` | `0x0024` | 9 signed little-endian 32-bit header words |
| `0x0024` | `0x0bb8` | 150 point slots, each 5 signed little-endian 32-bit words |
| `0x0bdc` | `0x0004` | active point count, `0..150` |
| `0x0be0` | — | exact end |

The point loop is bounded to 150 slots at `0x00567dfd`. The disk active count is consumed at `0x00567db8`. Only active point slots are copied from the file; the loader zeroes unused runtime point slots. This matters for `att011.swd` and `att012.swd`, whose disk blobs contain nonzero data after their active count. The decoder preserves those inactive disk bytes, while a runtime-compatible importer must zero inactive runtime slots as the executable does.

The exact point record is:

| Word | Proven state-3 use |
| ---: | --- |
| 0 | X acceleration in fixed-point units of `1/256` |
| 1 | Y acceleration in fixed-point units of `1/256` |
| 2 | numeric opcode |
| 3 | evidence-only raw word |
| 4 | progress threshold |

Header words 5 and 6 are initial X/Y velocities in fixed-point units of
`1/256`. Header word 8 is a terminal return selector. Header words 0–4 and 7
have no reachable finite-product consumer and remain evidence-only.

## Retail catalog

The packaged retail set contains 14 successfully loaded paths. With all packaged files present, runtime slot 0 is `att001.swd`, slot 1 is `att002.swd`, through slot 13 for `att014.swd`.

| File | SHA-256 | Header words | Active |
| --- | --- | --- | ---: |
| `att001.swd` | `880ba7f0355ef98e6abde803c135e6c9c60733f84c26844d3b6511c7172c6a1e` | `[3,117,0,0,1,0,51,0,2]` | 7 |
| `att002.swd` | `880ba7f0355ef98e6abde803c135e6c9c60733f84c26844d3b6511c7172c6a1e` | `[3,117,0,0,1,0,51,0,2]` | 7 |
| `att003.swd` | `87c6ac6394ab3eee0db69e846c1e7f486a8ccf5ae1f9c5f84857920ac6b1c88f` | `[-15,142,0,0,1,0,-13,0,3]` | 6 |
| `att004.swd` | `8a8cf01e0921fcf8b99c12d7caa976bf981fb2ca1a00354dcffc310ed1ca3a28` | `[15,142,0,0,1,0,-13,0,3]` | 6 |
| `att005.swd` | `1a0d0819640363599b78f6fd5cc60ef6bcb78f7eaf9aec4c1fa6d9821460b337` | `[-82,130,0,0,1,0,0,0,1]` | 13 |
| `att006.swd` | `1af149cc2532eb09f3699791929daa2e92dfe42fa3968bcc61998e64aae8d91b` | `[-101,130,0,1,1,0,-128,0,3]` | 3 |
| `att007.swd` | `8cc5867bc2cbb6173de5010e38c3ac80bc1667764aa9497775c3c7a8c92b16d1` | `[-63,142,0,0,1,0,-448,0,3]` | 14 |
| `att008.swd` | `e4376aa1dc223920b08ee2bb5a4742924a98b95ff40e4c4335bf6e9df01fb74f` | `[-90,76,0,0,1,282,-448,0,1]` | 14 |
| `att009.swd` | `10c154e6aa421c8497f5727fe27bf8ce8fb36995d3a5b410bab6f8bd03554297` | `[-93,92,0,0,1,0,-26,0,2]` | 18 |
| `att010.swd` | `a27b2eeb66aee767763008d0a4da5bfabfc27839950d94650be8b2e58153f080` | `[-93,92,0,0,1,0,-26,0,2]` | 18 |
| `att011.swd` | `4541b93d6edb78efe6bf0b7f4be407d13d548f5e72afe3c109f8fb45609c1474` | `[-87,113,0,0,1,0,448,0,1]` | 12 |
| `att012.swd` | `09296fc4ec72d4fed947b3f20e819f69161ac9abffcfa0fa2fef43b9c557e7aa` | `[87,113,0,0,1,0,448,0,1]` | 12 |
| `att013.swd` | `1c9731609891f3dbe392e9d62744311fbab5deb447c495552d83bde0f23e77ca` | `[93,92,0,0,1,0,-26,0,2]` | 18 |
| `att014.swd` | `360745783324ca20ddc36b69b0cbe4baf7429df023907f93009865e1fd801d61` | `[93,92,0,0,1,0,-26,0,2]` | 18 |

`att001.swd` and `att002.swd` are the only byte-identical retail pair. Every active retail point has word 2 equal to zero and word 3 equal to zero. The opcode branches described below are therefore latent format behavior, not exercised by these 14 active point ranges.

## Exact first-five assignment and selection

There is no SWD index or filename in an LVD file. The LVD layout closes exactly at `0x1cb98`, contains no `.swd` string, and its entry path does not assign a per-level attack-path set.

The executable instead loads the SWDs globally. When an ordinary post-entry enemy in state 2 launches an attack:

```text
swd_runtime_index = RNG_int(0, loaded_swd_count)
state = 3
```

The state change and draw are at `0x00609af0`–`0x00609b20`. The integer helper is half-open, so the packaged 14-file pool produces indices `0..13`. Consequently:

- levels 1, 2, 3, and 5 use the same complete 14-path global pool after their mode-1 entry ends in state 2;
- level 4's mode-2 terminal opcode enters state 10 and does not select an SWD;
- level 3's supplemental record enters state 6 and does not select an SWD.

The state-2 leader can recruit nearby state-2 entities into the same dive. A recruited follower copies the leader's selected SWD index, velocity, acceleration, progress, point index, and return selector rather than consuming another SWD-selection RNG draw. The exact spatial recruitment checks are supported: candidate state 2, strict vertical center delta `16 < dy < 60`, and strict horizontal center delta `-60 < dx < 60`, plus active/eligibility flags.

## State-3 integrator

State 3 begins at `0x0060af05`. At launch:

```text
velocity.x     = swd.header[5] / 256.0
velocity.y     = swd.header[6] / 256.0
acceleration.x = swd.point[0].word[0] / 256.0
acceleration.y = swd.point[0].word[1] / 256.0
point_index    = 0
progress       = tick_scale
return_selector = swd.header[8]
```

Each authoritative update uses this order:

```text
position.x += velocity.x * tick_scale
position.y += velocity.y * tick_scale
velocity.x += acceleration.x * tick_scale
velocity.y += acceleration.y * tick_scale
progress   += tick_scale
```

The engine truncates progress toward zero through helper `0x00526ae0` and advances only when:

```text
trunc_toward_zero(progress) > current_point.word[4]
```

On advance it increments `point_index`, loads the new acceleration, and resets progress to `tick_scale`. A zero threshold on the newly selected point is the terminal sentinel; the check is at `0x0060c14a`. Since the loader zeroes every inactive runtime point slot, the first slot after `active_point_count` supplies that sentinel even when inactive disk bytes are nonzero.

Two latent point opcodes are fully traced:

| Opcode | Side effect |
| ---: | --- |
| 1 | clear velocity and acceleration |
| 6 | deactivate the entity |

All active retail points use opcode 0, so retail first-five SWD motion is purely the segment integrator plus terminal routing.

## Terminal routing

Header word 8 selects one of three state-3 terminal branches:

- selector 2: branch beginning at `0x0060c16c`;
- selector 3: branch beginning at `0x0060c595`;
- selector 1 and fallback: path beginning at `0x0060c9fa`.

Those branches apply screen/group-dependent positioning and eventually return
the entity to state 4 or state 2. The numeric routing is proven. Human labels
such as “left return,” “right return,” or “loop” are not justified by the
evidence and remain neutral evidence-only prose; the runtime needs no label.

## Integration contract

For retail-faithful authoritative simulation:

1. Load every valid `att%03d.swd` in ascending filename index and compact successful files.
2. Preserve disk blobs losslessly, but zero inactive point slots in the runtime representation.
3. Keep selection in server-owned RNG order; followers copy the leader's selection without another draw.
4. Preserve fixed-point conversion, explicit-Euler order, float32 storage boundaries where bit compatibility is required, and the strict progress comparison.
5. Run behavior on the authoritative 60 Hz simulation clock. Render at 120/144/240 Hz by interpolating authoritative states; never advance SWD progress with render delta.
6. Replicate the selected path index, point index, progress, position, velocity, and acceleration in snapshots or deterministic replay state.

## Reproduction

Emit the complete catalog and verify every structured round trip:

```sh
python3 tools/swd_decoder.py --catalog --verify-roundtrip
```

Run pinned catalog, hash, layout, inactive-slot, and error-path tests:

```sh
python3 tools/swd_roundtrip_test.py
```

The decoder stores all 150 point slots and a base64 copy of the original blob.
It never normalizes evidence-only or inactive disk data.

## Evidence boundary

Proven:

- exact `0xbe0` layout, signed word encoding, loader probe range, runtime compaction, and inactive-slot zeroing;
- packaged 14-file order, hashes, headers, active counts, and only duplicate pair;
- absence of an LVD-to-SWD assignment and global state-2 selection;
- follower copy behavior;
- state-3 fixed-point conversion, integration order, strict threshold, sentinel, and numeric return-selector branches.

Supported:

- synchronized-dive recruitment as the gameplay label for the bounded follower-copy branch.

Evidence-only with no reachable runtime consumer:

- header words 0–4 and 7;
- point word 3;
- human-readable meanings of return selectors 1, 2, and 3.
