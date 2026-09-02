# Sprite packs

A sprite pack re-skins the game without touching anything the simulation or
the retail contracts depend on. Packs override retail textures key-by-key and
fall back to retail art for anything they do not cover; a broken or partial
pack can never fail boot. Collision (`.hma` masks), frame geometry
(`content/sprite_frames.json`), and the byte-locked retail manifest
(`content/presentation.json`) are never modified.

## Format

```
assets/packs/<name>/
  pack.json                  # schema warblade.sprite-pack.v1
  textures/<texture_key>.png # retail-exact dimensions, loose PNGs
```

- `pack.json#textures` keys must exist in `presentation.json#textures` with
  `kind: "texture"`, and each PNG must match the retail entry's exact
  width×height (validated at load; mismatches warn once and fall back).
- Packs are discovered under `res://assets/packs` and `user://packs`
  (exported builds use `user://packs`). Names: `[a-z0-9_]{1,32}`; a leading
  `_` hides a pack from discovery.
- Selection: the SPRITE PACK row in Settings (applies at next launch), the
  `--sprite-pack=<name>` flag, or the `sprite_pack` settings key.
- `--pack-smoke --sprite-pack=<name>` prints a JSON validation report and
  exits (headless-safe).

## Authoring pipeline (Tripo -> sprites)

`tools/tripo_pipeline.py` builds packs from text-prompted Tripo 3D models:

```
python3 tools/tripo_pipeline.py gen    --concept alien001            # Tripo API, spends credits
python3 tools/tripo_pipeline.py render --concept alien001            # windowed Godot turntable
python3 tools/tripo_pipeline.py post   --concept alien001            # Sea of Stars pixel pass
python3 tools/tripo_pipeline.py sheet  --concept alien001 --pack solstice
make pack-validate PACK=solstice                                     # offline gate
make run-pack PACK=solstice                                          # play with the pack
```

- Concepts live in `tools/sprite_concepts/*.json` (prompt, seed, base model
  orientation, target texture keys, recolor variants); the shared look lives
  in `tools/sprite_styles/<style>.json`.
- `render` drives `tools/render/render_cli.gd` (needs a window; `--headless`
  cannot rasterize). A job glb of `__builtin_probe__` renders test primitives
  so the whole pipeline can run without a model.
- `post` finishes frames as deliberate pixel art: shared per-animation
  palette, ramp hue-shifts (shadows toward indigo, highlights toward gold),
  isolated-pixel cleanup, and a colored outline. It also reports a
  silhouette IoU against the retail frames -- collision stays retail, so low
  IoU means the art visually overhangs its true hitbox.
- `sheet` composes retail-exact sheets from the frozen layout contracts
  (enemy 576×96 families, fighter 440×28 banking, shot cells), derives
  `*_mask` sheets and hue-rotated recolor variants, and upserts `pack.json`.
  Weapons (`weapons_big`), pickups (`bonuses`), and the small explosion
  (`expl_small`) are procedural -- drawn directly by `sheet`, no generation.
- API key: `TRIPO_API_KEY` or `~/.config/tripo/api_key`. Retail rasters are
  NEVER uploaded to Tripo (redistribution restrictions); prompts only.
- Requires Pillow (authoring only; `pack-validate` is the CI-facing gate and
  `tools/tripo_pipeline_test.py` covers the pure functions offline).

The first pack, `solstice` ("Solstice Swarm"), covers the core set: both
fighters, the six level 1-24 enemy families (plus alien001's recolors),
weapons, pickups, and the small explosion.
