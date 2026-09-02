#!/usr/bin/env python3
"""Validator for decoded Warblade .lvd descriptors.

The script expects JSON produced by parse_warblade_lvd.decode. It enforces
the JSON Schema stored in schemas/warblade_lvd_sections.schema.json and runs
extra sanity checks for the news ticker/shop metadata.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

VALID_IMDA_SIGNATURES = {0x41444749, 0x4E594157}
VALID_IMDA_RECORD_SIZES = {0x4C, 0x45}
SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas" / "warblade_lvd_sections.schema.json"


class SimpleJsonSchemaValidator:
    """Tiny JSON Schema subset validator (supports the features we emit)."""

    def __init__(self, schema: Dict[str, Any]):
        self.schema = schema
        self.defs = schema.get("$defs", {})

    def validate(self, instance: Any) -> List[str]:
        errors: List[str] = []
        self._validate(instance, self.schema, "$", errors)
        return errors

    def _resolve_ref(self, ref: str) -> Dict[str, Any]:
        if not ref.startswith("#/$defs/"):
            raise ValueError(f"Unsupported $ref '{ref}'")
        key = ref[len("#/$defs/") :]
        if key not in self.defs:
            raise ValueError(f"Unknown $ref target '{ref}'")
        return self.defs[key]

    def _validate(self, instance: Any, schema: Dict[str, Any], path: str, errors: List[str]) -> None:
        if "$ref" in schema:
            self._validate(instance, self._resolve_ref(schema["$ref"]), path, errors)
            return

        schema_type = schema.get("type")
        if schema_type:
            if schema_type == "object":
                if not isinstance(instance, dict):
                    errors.append(f"{path}: expected object, got {type(instance).__name__}")
                    return
                self._validate_object(instance, schema, path, errors)
            elif schema_type == "array":
                if not isinstance(instance, list):
                    errors.append(f"{path}: expected array, got {type(instance).__name__}")
                    return
                self._validate_array(instance, schema, path, errors)
            elif schema_type == "integer":
                if not isinstance(instance, int):
                    errors.append(f"{path}: expected integer, got {type(instance).__name__}")
                    return
                self._validate_number(instance, schema, path, errors)
            elif schema_type == "string":
                if not isinstance(instance, str):
                    errors.append(f"{path}: expected string, got {type(instance).__name__}")
                    return
                pattern = schema.get("pattern")
                if pattern and not re.fullmatch(pattern, instance):
                    errors.append(f"{path}: value '{instance}' does not match pattern '{pattern}'")
            else:
                errors.append(f"{path}: unsupported schema type '{schema_type}'")
                return
        else:
            # If no explicit type, still honor numeric constraints if applicable.
            if isinstance(instance, int):
                self._validate_number(instance, schema, path, errors)

        const_value = schema.get("const")
        if const_value is not None and instance != const_value:
            errors.append(f"{path}: expected constant {const_value}, got {instance}")

    def _validate_number(self, instance: int, schema: Dict[str, Any], path: str, errors: List[str]) -> None:
        minimum = schema.get("minimum")
        if minimum is not None and instance < minimum:
            errors.append(f"{path}: value {instance} < minimum {minimum}")
        maximum = schema.get("maximum")
        if maximum is not None and instance > maximum:
            errors.append(f"{path}: value {instance} > maximum {maximum}")

    def _validate_object(self, instance: Dict[str, Any], schema: Dict[str, Any], path: str, errors: List[str]) -> None:
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                errors.append(f"{path}: missing required property '{key}'")

        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        for key, value in instance.items():
            sub_schema = properties.get(key)
            if sub_schema is not None:
                self._validate(value, sub_schema, f"{path}.{key}", errors)
            else:
                if additional is False:
                    errors.append(f"{path}: unexpected property '{key}'")
                elif isinstance(additional, dict):
                    self._validate(value, additional, f"{path}.{key}", errors)

    def _validate_array(self, instance: List[Any], schema: Dict[str, Any], path: str, errors: List[str]) -> None:
        min_items = schema.get("minItems")
        max_items = schema.get("maxItems")
        if min_items is not None and len(instance) < min_items:
            errors.append(f"{path}: expected at least {min_items} items, got {len(instance)}")
        if max_items is not None and len(instance) > max_items:
            errors.append(f"{path}: expected at most {max_items} items, got {len(instance)}")
        items_schema = schema.get("items")
        if items_schema is not None:
            for idx, value in enumerate(instance):
                self._validate(value, items_schema, f"{path}[{idx}]", errors)


def _load_schema_validator() -> SimpleJsonSchemaValidator:
    try:
        schema = json.loads(SCHEMA_PATH.read_text())
    except Exception as exc:  # pragma: no cover - diagnostic path
        raise SystemExit(f"[validate] unable to load schema: {exc}")
    return SimpleJsonSchemaValidator(schema)


SCHEMA_VALIDATOR = _load_schema_validator()


def _load_descriptor(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # pragma: no cover - diagnostic path
        raise SystemExit(f"[validate] unable to load {path}: {exc}")


def _check_shop_imda(sections: dict) -> Iterable[Tuple[str, str]]:
    section = sections.get("shop_inventory_imda_header")
    if section is None:
        yield ("error", "shop_inventory_imda_header section missing")
        return
    if section.get("record_count") != 1:
        yield ("error", "shop_inventory_imda_header must contain exactly one record")
        return
    record = section["records"][0]
    signature = record.get("signature")
    if signature not in VALID_IMDA_SIGNATURES:
        expected = ", ".join(f"0x{value:08x}" for value in sorted(VALID_IMDA_SIGNATURES))
        yield (
            "error",
            f"unexpected IGDA signature 0x{signature:08x}; expected one of [{expected}]",
        )
    record_size = record.get("record_size_bytes")
    if record_size not in VALID_IMDA_RECORD_SIZES:
        expected = ", ".join(f"0x{value:02x}" for value in sorted(VALID_IMDA_RECORD_SIZES))
        yield ("error", f"IMDA record size should be one of [{expected}], got {record_size}")


def _check_news_sections(sections: dict) -> Iterable[Tuple[str, str]]:
    ticker = sections.get("news_ticker_globals")
    if ticker is None:
        yield ("error", "news_ticker_globals section missing")
    elif ticker.get("record_count") != 4:
        yield (
            "error",
            f"news_ticker_globals must expose 4 records, got {ticker.get('record_count')}"
        )

    asset_blob = sections.get("news_asset_blob")
    if asset_blob is None:
        yield ("warning", "news_asset_blob section missing; bitmap names unavailable")
    else:
        expected_blocks = asset_blob.get(
            "raw_block_count", asset_blob.get("end_block", 0) - asset_blob.get("start_block", 0) + 1
        )
        if expected_blocks != (asset_blob.get("end_block", 0) - asset_blob.get("start_block", 0) + 1):
            yield (
                "error",
                f"news_asset_blob raw_block_count mismatch: expected {asset_blob.get('end_block', 0) - asset_blob.get('start_block', 0) + 1}, got {expected_blocks}",
            )
        entries = asset_blob.get("records", [])
        for idx, entry in enumerate(entries):
            if not isinstance(entry, dict):
                yield (
                    "error",
                    "news_asset_blob records must be structured dictionaries ({'filename','padding'})",
                )
                break
            if "filename" not in entry:
                yield ("error", f"news_asset_blob record {idx} missing filename")
        trailing = asset_blob.get("trailing_padding", [])
        if trailing is None:
            yield ("error", "news_asset_blob missing trailing_padding list")

    shadow = sections.get("news_ticker_runtime_shadow")
    if shadow is None:
        yield (
            "warning",
            "news_ticker_runtime_shadow section missing; runtime counters may not persist"
        )
    elif shadow.get("record_count") != 2:
        yield (
            "error",
            f"news_ticker_runtime_shadow requires 2 records, got {shadow.get('record_count')}"
        )


def validate_descriptor(descriptor: dict) -> List[Tuple[str, str]]:
    sections = descriptor.get("sections", {})
    findings: List[Tuple[str, str]] = []

    schema_errors = SCHEMA_VALIDATOR.validate(descriptor)
    findings.extend(("error", msg) for msg in schema_errors)

    remainder = descriptor.get("remainder", [])
    if remainder:
        findings.append(
            (
                "error",
                f"descriptor still carries {len(remainder)} remainder blocks; update SECTION_LAYOUT",
            )
        )

    header_reserved = sections.get("header_reserved")
    if header_reserved and header_reserved.get("record_count") != 1:
        findings.append(("error", "header_reserved section must contain exactly one record"))

    findings.extend(_check_shop_imda(sections))
    findings.extend(_check_news_sections(sections))

    return findings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "json",
        type=Path,
        help="Path to the JSON descriptor produced by parse_warblade_lvd.py decode",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Only print messages when validation fails",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    descriptor = _load_descriptor(args.json)
    findings = validate_descriptor(descriptor)
    errors = [msg for lvl, msg in findings if lvl == "error"]
    warnings = [msg for lvl, msg in findings if lvl == "warning"]

    if not args.quiet or findings:
        for msg in errors:
            print(f"[error] {msg}")
        for msg in warnings:
            print(f"[warn] {msg}")
        if not findings:
            print(f"[ok] {args.json} passed validation")

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
