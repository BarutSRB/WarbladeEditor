#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import tarfile
import tempfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME_ROOT = ROOT / "Game"
DEFAULT_ALLOWLIST = ROOT / "tools" / "pac_allowlist.json"
DEFAULT_FACTS = ROOT / "tools" / "known_facts.json"
DEFAULT_OUTPUT = ROOT / "assets" / "original"
DEFAULT_MANIFEST = ROOT / "docs" / "evidence" / "provenance_manifest.json"


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path):
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def relative_path(value, label):
    if (
        not isinstance(value, str)
        or not value
        or "\x00" in value
        or "\\" in value
        or any(part in ("", ".", "..") for part in value.split("/"))
    ):
        raise ValueError(f"{label} must be a normalized relative path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts:
        raise ValueError(f"{label} must be a normalized relative path: {value!r}")
    return path


def contained_path(root, value, label):
    relative = relative_path(value, label)
    candidate = root.joinpath(*relative.parts)
    resolved_root = root.resolve()
    resolved_parent = candidate.parent.resolve()
    if resolved_parent != resolved_root and resolved_root not in resolved_parent.parents:
        raise ValueError(f"{label} escapes its root: {value!r}")
    return candidate


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def normalized_entries(groups, source_key):
    entries = []
    targets = set()
    sources = set()
    for group in groups:
        destination_value = group["destination"]
        destination = (
            PurePosixPath()
            if destination_value in ("", ".")
            else relative_path(destination_value, "group destination")
        )
        category = group["category"]
        for raw_entry in group["files"]:
            if isinstance(raw_entry, str):
                source = relative_path(raw_entry, source_key)
                target_name = PurePosixPath(raw_entry).name
            else:
                source = relative_path(raw_entry["source"], source_key)
                target_name = raw_entry.get("target", PurePosixPath(raw_entry["source"]).name)
            target = destination / relative_path(target_name, "asset target")
            source_text = source.as_posix()
            target_text = target.as_posix()
            if source_text in sources:
                raise ValueError(f"duplicate allowlisted source: {source_text}")
            if target_text in targets:
                raise ValueError(f"duplicate output target: {target_text}")
            sources.add(source_text)
            targets.add(target_text)
            entries.append(
                {
                    "source": source_text,
                    "output": target_text,
                    "category": category,
                }
            )
    return entries


def validate_source_file(root, relative, label):
    path = contained_path(root, relative, label)
    if path.is_symlink():
        raise ValueError(f"{label} may not be a symlink: {relative}")
    if not path.is_file():
        raise FileNotFoundError(f"{label} is missing or not a regular file: {path}")
    resolved_root = root.resolve()
    resolved = path.resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ValueError(f"{label} resolves outside its root: {relative}")
    return path


def verify_existing_output(path, data):
    if path.is_symlink() or not path.is_file():
        raise FileNotFoundError(f"missing extracted asset: {path}")
    actual = path.read_bytes()
    if actual != data:
        raise ValueError(
            f"extracted asset drift for {path}: expected {sha256_bytes(data)}, "
            f"found {sha256_bytes(actual)}"
        )


def extract_pac(game_root, output_root, config, write_outputs=True):
    source = config["source"]
    pac_path = validate_source_file(game_root, source["path"], "PAC archive")
    actual_archive_hash = sha256_file(pac_path)
    if actual_archive_hash != source["sha256"]:
        raise ValueError(
            f"PAC SHA-256 mismatch: expected {source['sha256']}, found {actual_archive_hash}"
        )

    entries = normalized_entries(config["groups"], "PAC member")
    records = []
    with tarfile.open(pac_path, mode="r:*") as archive:
        member_index = {}
        for member in archive.getmembers():
            if member.name in member_index:
                raise ValueError(f"PAC contains duplicate member name: {member.name}")
            member_index[member.name] = member
        for entry in entries:
            member = member_index.get(entry["source"])
            if member is None:
                raise FileNotFoundError(f"allowlisted PAC member is missing: {entry['source']}")
            if not member.isfile():
                raise ValueError(f"allowlisted PAC member is not a regular file: {entry['source']}")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError(f"could not read allowlisted PAC member: {entry['source']}")
            data = stream.read()
            if len(data) != member.size:
                raise ValueError(f"truncated PAC member: {entry['source']}")
            output_path = contained_path(output_root, entry["output"], "asset output")
            if write_outputs:
                atomic_write(output_path, data)
            else:
                verify_existing_output(output_path, data)
            digest = sha256_bytes(data)
            records.append(
                {
                    "category": entry["category"],
                    "output": entry["output"],
                    "output_sha256": digest,
                    "size": len(data),
                    "source_kind": "warblade.pac",
                    "source_member": entry["source"],
                    "source_sha256": digest,
                }
            )
    return pac_path, actual_archive_hash, records


def copy_external_files(game_root, output_root, config, write_outputs=True):
    records = []
    entries = normalized_entries(config["groups"], "external source")
    for entry in entries:
        source_path = validate_source_file(game_root, entry["source"], "external source")
        data = source_path.read_bytes()
        output_path = contained_path(output_root, entry["output"], "asset output")
        if write_outputs:
            atomic_write(output_path, data)
        else:
            verify_existing_output(output_path, data)
        digest = sha256_bytes(data)
        records.append(
            {
                "category": entry["category"],
                "output": entry["output"],
                "output_sha256": digest,
                "size": len(data),
                "source_kind": "external_file",
                "source_member": entry["source"],
                "source_sha256": digest,
            }
        )
    return records


def build_manifest(allowlist_path, facts_path, game_root, pac_path, pac_hash, records):
    facts = read_json(facts_path)
    executable = validate_source_file(game_root, facts["source_files"]["executable"]["path"], "executable")
    manual = validate_source_file(game_root, facts["source_files"]["manual"]["path"], "manual")
    sources = [
        {
            "id": "warblade_executable",
            "path": facts["source_files"]["executable"]["path"],
            "sha256": sha256_file(executable),
            "size": executable.stat().st_size,
        },
        {
            "id": "warblade_pac",
            "path": pac_path.relative_to(game_root).as_posix(),
            "sha256": pac_hash,
            "size": pac_path.stat().st_size,
        },
        {
            "id": "warblade_manual",
            "path": facts["source_files"]["manual"]["path"],
            "sha256": sha256_file(manual),
            "size": manual.stat().st_size,
        },
    ]
    expected_hashes = {
        item["id"]: facts["source_files"][item["id"].removeprefix("warblade_")]["sha256"]
        for item in sources
    }
    for source in sources:
        expected = expected_hashes[source["id"]]
        if source["sha256"] != expected:
            raise ValueError(
                f"{source['id']} SHA-256 mismatch: expected {expected}, found {source['sha256']}"
            )
    return {
        "format_version": 1,
        "authorization_assumption": (
            "Assets are copied only for the user-requested local remake. "
            "This manifest does not grant redistribution rights."
        ),
        "allowlist": {
            "path": allowlist_path.relative_to(ROOT).as_posix(),
            "sha256": sha256_file(allowlist_path),
        },
        "known_facts": {
            "path": facts_path.relative_to(ROOT).as_posix(),
            "sha256": sha256_file(facts_path),
            "data": facts,
        },
        "sources": sources,
        "excluded_material": [
            {
                "path": "data/music/*.mus (12 tracker modules)",
                "reason": (
                    "Tracker-module `.mus` playback is a permanent product non-goal; "
                    "the extracted MP3 soundtrack is the final music system, so the "
                    "module files stay unextracted by policy."
                ),
            },
            {
                "path": "data/music/memorystation.mp3",
                "reason": (
                    "Byte-identical duplicate of the extracted data/music/memory.mp3 "
                    "(SHA-256 76a470bf8da6ecbb3ebe2286ff654b0dbf02ade28a1a036424fafea195165945); "
                    "the single copy covers this content."
                ),
            },
            {
                "path": "Jukebox.exe, bass.dll, fmod.dll, website.url",
                "reason": (
                    "Windows-only executables, their audio DLLs, and a website shortcut "
                    "have no asset role in the macOS remake; the jukebox feature is a "
                    "native reimplementation over the extracted soundtrack."
                ),
            },
        ],
        "assets": sorted(records, key=lambda item: item["output"]),
    }


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Extract only explicitly allowlisted Warblade assets without using tar path extraction."
    )
    parser.add_argument("--game-root", type=Path, default=DEFAULT_GAME_ROOT)
    parser.add_argument("--allowlist", type=Path, default=DEFAULT_ALLOWLIST)
    parser.add_argument("--facts", type=Path, default=DEFAULT_FACTS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify all source bytes, extracted outputs, and the manifest without writing",
    )
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    allowlist = read_json(arguments.allowlist)
    if allowlist.get("version") != 1:
        raise ValueError("unsupported allowlist version")
    game_root = arguments.game_root.resolve()
    output_root = arguments.output.resolve()
    pac_path, pac_hash, pac_records = extract_pac(
        game_root,
        output_root,
        allowlist["pac"],
        write_outputs=not arguments.check,
    )
    external_records = copy_external_files(
        game_root,
        output_root,
        allowlist["external"],
        write_outputs=not arguments.check,
    )
    manifest = build_manifest(
        arguments.allowlist.resolve(),
        arguments.facts.resolve(),
        game_root,
        pac_path,
        pac_hash,
        pac_records + external_records,
    )
    serialized = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    manifest_path = arguments.manifest.resolve()
    if arguments.check:
        verify_existing_output(manifest_path, serialized)
        print(
            f"verified {len(manifest['assets'])} allowlisted assets "
            f"({sum(item['size'] for item in manifest['assets'])} bytes)"
        )
        print(f"manifest current: {manifest_path}")
        return
    atomic_write(manifest_path, serialized)
    print(
        f"extracted {len(manifest['assets'])} allowlisted assets "
        f"({sum(item['size'] for item in manifest['assets'])} bytes)"
    )
    print(f"manifest: {manifest_path}")


if __name__ == "__main__":
    main()
