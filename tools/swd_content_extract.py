#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

from swd_decoder import WARBLADE_EXE_SHA256, decode_file


ROOT = Path(__file__).resolve().parents[1]
PATH_ROOT = ROOT / "assets" / "original" / "paths"
DEFAULT_OUTPUT = ROOT / "content" / "swd_paths.json"


def build_document() -> dict:
    paths = []
    for runtime_index, path in enumerate(sorted(PATH_ROOT.glob("att*.swd"))):
        decoded = decode_file(path)
        paths.append(
            {
                "id": runtime_index,
                "source_file": path.name,
                "source_sha256": decoded["sha256"],
                "initial_velocity_x_fixed_256": decoded["header_words"][5],
                "initial_velocity_y_fixed_256": decoded["header_words"][6],
                "return_selector": decoded["header_words"][8],
                "active_point_count": decoded["active_point_count"],
                "points": [
                    {
                        "acceleration_x_fixed_256": point["words"][0],
                        "acceleration_y_fixed_256": point["words"][1],
                        "opcode": point["words"][2],
                        "unresolved_word_3": point["words"][3],
                        "progress_threshold": point["words"][4],
                    }
                    for point in decoded["active_points"]
                ],
            }
        )
    if len(paths) != 14:
        raise ValueError(f"expected 14 packaged SWD paths, found {len(paths)}")
    return {
        "version": 1,
        "schema": "warblade.swd.runtime.v1",
        "source_executable_sha256": WARBLADE_EXE_SHA256,
        "selection_scope": "global_loaded_catalog",
        "inactive_runtime_point_policy": "zero_fill",
        "paths": paths,
    }


def encoded_document() -> str:
    return json.dumps(build_document(), indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate compact authoritative runtime content from retail SWD files."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    generated = encoded_document()
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != generated:
            raise SystemExit(f"{args.output} is stale; regenerate it")
        print(f"verified {args.output}")
        return 0
    args.output.write_text(generated, encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
