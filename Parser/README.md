# Warblade Level Editor & .lvd Toolkit

## Verified Lossless Decoder

`scripts/lvd_lossless.py` is now the primary decoder for retail Warblade level files. Its fixed `0x1cb98`-byte layout, coordinate transforms, activation sequencing, health field, path acceleration, fixed-tick integration, and observed opcodes were traced from the retail `warblade.exe` rather than inferred from visual patterns in one JSON dump.

The lossless JSON keeps the complete source blob in `raw_blob_base64`. Decoding and encoding therefore reproduce every byte, including inactive slots and unresolved fields:

```bash
./scripts/lvd_lossless.py verify \
  /path/to/classic_level_001.lvd \
  /path/to/classic_level_002.lvd

./scripts/lvd_lossless.py decode \
  /path/to/classic_level_001.lvd \
  --output Reports/classic_level_001.lossless.json

./scripts/lvd_lossless.py encode \
  Reports/classic_level_001.lossless.json \
  Reports/classic_level_001.roundtrip.lvd
```

Run the tests with:

```bash
python3 -m unittest discover -s tests -v
```

Set `WARBLADE_LVD_DIR=/path/to/levels` to exercise retail levels 001–005 outside the sibling `Remake/assets/original/levels` checkout. The repository sample always exercises an exact level-1 round trip.

The existing `parse_warblade_lvd.py`, editor CLI, schemas, and `docs/lvd_schema.md` are preserved as a legacy experimental workflow. Their 32-byte block names and friendly gameplay labels were heuristic and are not executable-verified. In particular, labels such as `starting_lives`, shop inventory, news ticker, and HUD paths must not be treated as meanings of retail classic LVD offsets. Use `lvd_lossless.py` and its embedded `field_contract` for remake or preservation work.

## Personal Note

When I was younger, I played a lot of Warblade by the legendary game creator Edgar M. Vigdal. I was saddened to learn that he passed away from cancer before he could complete his vision for Warblade MKII. Since no one owns the source code and his family has no access to it, I originally wanted to recreate the entire game (Warblade v1.34) as open source. But there would always be small differences in behavior, and as a solo hobbyist I’m nowhere near the skill level of the late Edgar M. Vigdal.

So instead, I decided to document the `.lvd` file format, which stores authored level data. The executable-backed lossless decoder now establishes the complete byte layout and a verified subset of gameplay semantics while preserving every unresolved byte for continued research.

I’ve also begun developing a GUI Level Editor in Rust, though it’s far from finished and may never be, as hobby projects compete with my full-time job. This repository is for anyone interested in learning, using, modding, or contributing—or even forking it to pursue their own vision of a level editor.

## Overview

Warblade ships its classic levels as fixed-size `.lvd` blobs. This repository includes an executable-backed lossless decoder, the earlier experimental JSON schemas and CLI, and an experimental GUI.

The guiding principles:

- Preserve every original byte through exact round trips.
- Separate executable-proven meanings from supported hypotheses and unknown fields.
- Offer ergonomic tooling (CLI + GUI) so anyone can decode, edit, validate, and re-encode levels.

## Repository Layout

| Path | Description |
| --- | --- |
| `scripts/lvd_lossless.py` | Primary executable-backed decoder and byte-identical encoder. |
| `tests/test_lvd_lossless.py` | Layout and first-five retail round-trip regression tests. |
| `docs/lvd_schema.md` | Legacy heuristic schema notes; not authoritative for retail classic LVD semantics. |
| `schemas/*.schema.json` | Legacy experimental JSON schemas. |
| `scripts/parse_warblade_lvd.py` | Legacy heuristic decoder/encoder retained for compatibility and research comparison. |
| `scripts/validate_warblade_lvd.py` | JSON Schema + bespoke linting for ticker data, shop tables, etc. |
| `scripts/warblade_editor_cli.py` | Batteries-included workflow (`decode → edit → lint → encode`). |
| `scripts/warblade_pac.py` | Helper for listing, extracting, and updating entries inside `warblade.pac`. |
| `Reports/` | Sample descriptors (`classic_level_001`) used for testing the tooling. |
| `LevelEditor/` | Experimental Rust/egui GUI for visualizing formations, auxiliaries, and playback timelines. |

## Requirements

| Component | Dependencies |
| --- | --- |
| CLI / scripts | Python 3.11+, `pip install -r requirements.txt` is not needed because everything uses the standard library. |
| GUI Level Editor | Rust toolchain with Cargo (edition 2024; `rustup` stable ≥1.75 recommended). `eframe` pulls in wgpu, so recent graphics drivers are helpful. |

## Rust GUI Level Editor

The GUI lets you visualize formation grids, aux path splines, and wave metadata while editing JSON descriptors.

```bash
cd LevelEditor
cargo run -- ../Reports/classic_level_001.json
# or point at any decoded JSON descriptor
```

- Launching without an argument opens a blank editor; type or browse to a JSON descriptor path and click **Load**.
- Switching between the Formations/Aux views lets you inspect row colors (formation rows of six records) and aux splines.
- The editor tracks dirty state; use the **Save Copy** workflow to write an updated descriptor.
- Animated previews (playback controls in the right rail) are still experimental but already useful when tweaking timer ranges.

## Legacy Decode → Edit → Encode Workflow (CLI)

The older CLI wraps heuristic decoding, editing, linting, encoding, and optional PAC updates. It is preserved so existing experiments continue to work, but its field names are not the verified retail format contract.

```bash
# Decode classic_level_001, open your editor, lint, and emit a patched .lvd
./scripts/warblade_editor_cli.py edit classic_level_001.lvd \
  --pac /path/to/Warblade/data/warblade.pac \
  --out ./Reports/classic_level_001_patched.lvd

# Skip launching $EDITOR (useful when you hand-edit JSON elsewhere)
./scripts/warblade_editor_cli.py edit classic_level_001.lvd \
  --out ./tmp/classic_level_001.lvd --skip-editor
```

Under the hood the CLI:

1. Calls `scripts/parse_warblade_lvd.py decode` to turn an `.lvd` blob into structured JSON under `Reports/<entry>.json`.
2. Launches `$VISUAL`/`$EDITOR` (or the command passed to `--editor`) so you can edit the descriptor.
3. Validates the JSON with `scripts/validate_warblade_lvd.py`.
4. Encodes the JSON back into an `.lvd` blob using the same parser.

You can also run each step manually:

```bash
# Decode an entry straight out of warblade.pac and pretty-print JSON
./scripts/parse_warblade_lvd.py decode classic_level_001.lvd > Reports/classic_level_001.json

# Re-encode edited JSON back to binary
./scripts/parse_warblade_lvd.py encode \
  --json Reports/classic_level_001.json \
  --out Reports/classic_level_001.lvd

# Validate before flashing it back into the PAC
./scripts/validate_warblade_lvd.py Reports/classic_level_001.json
```

## Working With `warblade.pac`

The helper script keeps you from corrupting the archive that Warblade reads at runtime:

```bash
# Inspect entries inside the PAC file
./scripts/warblade_pac.py list --pac /Applications/Warblade/data/warblade.pac

# Replace a single level with your encoded blob (keeps a .bak backup)
./scripts/warblade_pac.py update classic_level_001.lvd \
  --replacement Reports/classic_level_001_patched.lvd \
  --pac /Applications/Warblade/data/warblade.pac \
  --backup
```

Because the PAC is a plain tar, `warblade_pac.py` simply re-packs it with your modified entry while preserving everything else.

## Legacy Schemas & Documentation

- `docs/lvd_schema.md` records the earlier block interpretation. Its headers, formations, shop, aux-path, ticker, and footer labels are unverified hypotheses.
- `schemas/warblade_lvd_sections.schema.json` mirrors that document so validators and editors can enforce constraints (record counts, ranges, friendly names).
- `schemas/warblade_shop_tables.schema.json` narrows the focus to shop inventory data, especially the IGDA chunks.
- `scripts/validate_warblade_lvd.py` wires those schemas into a lightweight validator that also checks ticker padding, IMDA signatures, and shop slot counts.

## Contributing & Roadmap

- **Documentation coverage**: Missing sections (anything still surfaced in `remainder`) belong in `docs/lvd_schema.md` + the schema files.
- **GUI polish**: The Rust editor still needs UX love (save states, keyboard shortcuts, playback overlays); feel free to file issues or PRs.
- **Automation**: Tests/CI for round-tripping sample levels and schema validation would make future refactors safer.

Whether you want to preserve Edgar M. Vigdal’s work, learn from it, or build new ideas on top of it, this repository should give you a solid foundation. Fork it, experiment, and share what you build with the community.
