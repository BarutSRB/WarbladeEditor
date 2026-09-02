#!/usr/bin/env python3
"""Black-box runtime smokes for exported Warblade macOS app bundles."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import secrets
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


SCHEMA = "warblade.packaged_runtime_smoke.v1"
SERVER_PROBE_SCHEMA = "warblade.packaged_server_probe.v1"
SERVER_PROBE_REQUIRED_CHECKS = (
    "ok",
    "configured",
    "content_hash_matches",
    "match_contract_valid",
    "authenticated",
    "seat_claimed",
    "state_hash_valid",
    "input_submitted",
    "authoritative_tick_advanced",
    "authoritative_input_applied",
)
DEFAULT_PROCESS_TIMEOUT = 40.0
DEFAULT_STARTUP_TIMEOUT = 15.0
DEFAULT_SHUTDOWN_TIMEOUT = 8.0
DEFAULT_PROBE_TIMEOUT = 25.0
DEFAULT_END_LEVEL = 3999
DEFAULT_PROJECT = Path(__file__).resolve().parent.parent


class SmokeFailure(RuntimeError):
    """Raised when an exported runtime contract is not satisfied."""


def resolve_app_executable(value: str) -> Path:
    path = Path(value).resolve()
    if path.is_dir():
        info_path = path / "Contents" / "Info.plist"
        if not info_path.is_file():
            raise SmokeFailure(f"app bundle is missing Info.plist: {path}")
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        executable_name = str(info.get("CFBundleExecutable", ""))
        if not executable_name:
            raise SmokeFailure(f"app bundle does not name CFBundleExecutable: {path}")
        path = path / "Contents" / "MacOS" / executable_name
    if not path.is_file():
        raise SmokeFailure(f"packaged executable does not exist: {path}")
    if not os.access(path, os.X_OK):
        raise SmokeFailure(f"packaged executable is not executable: {path}")
    return path


def find_smoke_result(output: str, kind: str) -> dict[str, Any]:
    for line in reversed(output.splitlines()):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (
            isinstance(value, dict)
            and value.get("schema") == SCHEMA
            and value.get("kind") == kind
        ):
            return value
    raise SmokeFailure(f"packaged {kind} smoke did not emit its JSON result")


def run_client_smoke(
    app: str,
    timeout: float,
    end_level: int | None = None,
) -> dict[str, Any]:
    executable = resolve_app_executable(app)
    command = [str(executable), "--headless", "--", "--packaged-client-smoke"]
    if end_level is not None:
        command.append(f"--end-level={end_level}")
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            _terminate_process_group(process)
            output, _ = process.communicate()
            raise SmokeFailure(
                f"packaged client smoke exceeded {timeout:.1f}s timeout\n{output[-4000:]}"
            ) from error
        result = find_smoke_result(output, "client_self_sidecar")
        result["exit_code"] = process.returncode
        result["executable"] = str(executable)
        if process.returncode != 0:
            raise SmokeFailure(
                f"packaged client smoke exited {process.returncode}: "
                f"{result.get('error', '')}\n{output[-4000:]}"
            )
        required = (
            "ok",
            "sidecar_started",
            "authenticated",
            "match_contract_valid",
            "state_hash_valid",
            "authoritative_tick_advanced",
            "authoritative_input_applied",
            "clean_shutdown",
            "heartbeat_removed",
        )
        missing = [name for name in required if not bool(result.get(name, False))]
        if missing:
            raise SmokeFailure(
                "packaged client smoke failed checks: " + ", ".join(missing)
            )
        return result
    finally:
        _terminate_process_group(process)


def run_client_rejection_smoke(
    app: str,
    timeout: float,
    end_level: int,
) -> dict[str, Any]:
    """Prove the packaged client rejects an invalid boundary before spawning a sidecar."""
    executable = resolve_app_executable(app)
    command = [
        str(executable),
        "--headless",
        "--",
        "--packaged-client-smoke",
        f"--end-level={end_level}",
    ]
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            _terminate_process_group(process)
            output, _ = process.communicate()
            raise SmokeFailure(
                f"packaged client rejection smoke exceeded {timeout:.1f}s timeout\n"
                f"{output[-4000:]}"
            ) from error
        client_result = find_smoke_result(output, "client_self_sidecar")
        if process.returncode == 0:
            raise SmokeFailure(
                "packaged client accepted an invalid end-level boundary\n"
                + output[-4000:]
            )
        if bool(client_result.get("ok", False)):
            raise SmokeFailure("packaged client reported success for an invalid boundary")
        if bool(client_result.get("sidecar_started", False)):
            raise SmokeFailure("packaged client spawned a sidecar before rejecting the boundary")
        if int(client_result.get("requested_end_level", 0)) != end_level:
            raise SmokeFailure("packaged client did not report the rejected boundary exactly")
        if not str(client_result.get("error", "")):
            raise SmokeFailure("packaged client rejected the boundary without an error")
        return {
            "schema": SCHEMA,
            "kind": "client_boundary_rejection",
            "ok": True,
            "rejected_end_level": end_level,
            "exit_code": process.returncode,
            "executable": str(executable),
            "client_result": client_result,
        }
    finally:
        _terminate_process_group(process)


def run_server_smoke(
    app: str,
    startup_timeout: float,
    shutdown_timeout: float,
    godot: str,
    project: str,
    probe_timeout: float,
    end_level: int | None = None,
) -> dict[str, Any]:
    executable = resolve_app_executable(app)
    token = secrets.token_hex(24)
    result: dict[str, Any] = {
        "schema": SCHEMA,
        "kind": "dedicated_server",
        "ok": False,
        "error": "",
        "ready_file_published": False,
        "port_valid": False,
        "token_matches": False,
        "content_hash_valid": False,
        "probe_configured": False,
        "match_contract_valid": False,
        "authenticated": False,
        "seat_claimed": False,
        "state_hash_valid": False,
        "input_submitted": False,
        "authoritative_tick_advanced": False,
        "authoritative_input_applied": False,
        "heartbeat_shutdown": False,
        "heartbeat_removed": False,
        "exit_code": None,
        "executable": str(executable),
    }
    with tempfile.TemporaryDirectory(prefix="warblade_packaged_server_smoke_") as raw_dir:
        directory = Path(raw_dir)
        ready_path = directory / "ready.json"
        heartbeat_path = directory / "parent.heartbeat"
        _replace_text(heartbeat_path, "1")
        command = [
                str(executable),
                "--headless",
                "--",
                "--server",
                "--host=127.0.0.1",
                "--port=0",
                f"--token={token}",
                f"--ready-file={ready_path}",
                f"--parent-heartbeat={heartbeat_path}",
            ]
        if end_level is not None:
            command.append(f"--end-level={end_level}")
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
        try:
            response = _wait_for_ready_file(process, ready_path, startup_timeout)
            result["ready_file_published"] = True
            if not bool(response.get("ok", False)):
                raise SmokeFailure(
                    "packaged dedicated server rejected startup: "
                    + str(response.get("error", "unknown error"))
                )
            port = int(response.get("port", 0))
            result["port"] = port
            result["port_valid"] = 1024 <= port <= 65535
            result["token_matches"] = str(response.get("token", "")) == token
            result["content_hash_valid"] = len(str(response.get("content_hash", ""))) == 64
            if not bool(result["port_valid"]):
                raise SmokeFailure("packaged dedicated server returned an invalid port")
            if not bool(result["token_matches"]):
                raise SmokeFailure("packaged dedicated server returned a different token")
            if not bool(result["content_hash_valid"]):
                raise SmokeFailure("packaged dedicated server returned an invalid content hash")

            _replace_text(heartbeat_path, "protocol-probe-started")
            probe = _run_server_probe(
                godot,
                project,
                "127.0.0.1",
                port,
                token,
                str(response.get("content_hash", "")),
                probe_timeout,
                heartbeat_path,
                end_level if end_level is not None else DEFAULT_END_LEVEL,
            )
            result["probe"] = probe
            for source_name, result_name in (
                ("configured", "probe_configured"),
                ("match_contract_valid", "match_contract_valid"),
                ("authenticated", "authenticated"),
                ("seat_claimed", "seat_claimed"),
                ("state_hash_valid", "state_hash_valid"),
                ("input_submitted", "input_submitted"),
                ("authoritative_tick_advanced", "authoritative_tick_advanced"),
                ("authoritative_input_applied", "authoritative_input_applied"),
            ):
                result[result_name] = bool(probe.get(source_name, False))
            if not bool(probe.get("ok", False)):
                raise SmokeFailure(
                    "packaged dedicated server protocol probe failed: "
                    + str(probe.get("error", "unknown error"))
                )

            _replace_text(heartbeat_path, "protocol-probe-complete")
            if process.poll() is not None:
                raise SmokeFailure("packaged dedicated server exited before heartbeat shutdown")
            _replace_text(heartbeat_path, "shutdown")
            try:
                output, _ = process.communicate(timeout=shutdown_timeout)
            except subprocess.TimeoutExpired as error:
                raise SmokeFailure(
                    "packaged dedicated server did not honor heartbeat shutdown "
                    f"within {shutdown_timeout:.1f}s"
                ) from error
            result["exit_code"] = process.returncode
            result["heartbeat_shutdown"] = process.returncode == 0
            result["heartbeat_removed"] = not heartbeat_path.exists()
            if process.returncode != 0:
                raise SmokeFailure(
                    f"packaged dedicated server exited {process.returncode}\n{output[-4000:]}"
                )
            if not bool(result["heartbeat_removed"]):
                raise SmokeFailure("packaged dedicated server left its heartbeat file behind")
            result["ok"] = True
            return result
        except SmokeFailure as error:
            result["error"] = str(error)
            raise
        finally:
            _terminate_process_group(process)


def _run_server_probe(
    godot: str,
    project: str,
    host: str,
    port: int,
    token: str,
    content_hash: str,
    timeout: float,
    heartbeat_path: Path | None = None,
    end_level: int = DEFAULT_END_LEVEL,
) -> dict[str, Any]:
    project_path = Path(project).resolve()
    probe_path = project_path / "tools" / "packaged_server_runtime_probe.gd"
    if not probe_path.is_file():
        raise SmokeFailure(f"packaged server protocol probe is missing: {probe_path}")
    process = subprocess.Popen(
        [
            godot,
            "--headless",
            "--path",
            str(project_path),
            "--script",
            "res://tools/packaged_server_runtime_probe.gd",
            "--",
            f"--host={host}",
            f"--port={port}",
            f"--token={token}",
            f"--content-hash={content_hash}",
            f"--end-level={end_level}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        try:
            output, _ = _communicate_with_heartbeat(
                process,
                timeout,
                heartbeat_path,
            )
        except subprocess.TimeoutExpired as error:
            _terminate_process_group(process)
            output, _ = process.communicate()
            raise SmokeFailure(
                f"packaged server protocol probe exceeded {timeout:.1f}s timeout\n"
                f"{output[-4000:]}"
            ) from error
        try:
            result = _find_json_result(output, "schema", SERVER_PROBE_SCHEMA)
        except SmokeFailure as error:
            raise SmokeFailure(f"{error}\n{output[-4000:]}") from error
        result["exit_code"] = process.returncode
        if process.returncode != 0:
            raise SmokeFailure(
                f"packaged server protocol probe exited {process.returncode}: "
                f"{result.get('error', '')}\n{output[-4000:]}"
            )
        missing = missing_server_probe_checks(result)
        if missing:
            raise SmokeFailure(
                "packaged server protocol probe failed checks: " + ", ".join(missing)
            )
        return result
    finally:
        _terminate_process_group(process)


def _communicate_with_heartbeat(
    process: subprocess.Popen[str],
    timeout: float,
    heartbeat_path: Path | None,
) -> tuple[str, str | None]:
    deadline = time.monotonic() + timeout
    generation = 1
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0.0:
            raise subprocess.TimeoutExpired(process.args, timeout)
        try:
            return process.communicate(timeout=min(1.0, remaining))
        except subprocess.TimeoutExpired:
            if heartbeat_path is not None:
                _replace_text(heartbeat_path, f"protocol-probe-{generation}")
                generation += 1


def _find_json_result(output: str, key: str, expected: str) -> dict[str, Any]:
    for line in reversed(output.splitlines()):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and value.get(key) == expected:
            return value
    raise SmokeFailure(f"process did not emit {expected} JSON")


def missing_server_probe_checks(result: dict[str, Any]) -> list[str]:
    return [
        name
        for name in SERVER_PROBE_REQUIRED_CHECKS
        if not bool(result.get(name, False))
    ]


def _wait_for_ready_file(
    process: subprocess.Popen[str],
    ready_path: Path,
    timeout: float,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last_decode_error = ""
    while time.monotonic() < deadline:
        if ready_path.is_file():
            try:
                value = json.loads(ready_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                last_decode_error = str(error)
            else:
                if isinstance(value, dict):
                    return value
                last_decode_error = "ready-file JSON is not an object"
        if process.poll() is not None:
            output, _ = process.communicate()
            raise SmokeFailure(
                f"packaged dedicated server exited {process.returncode} before ready-file startup"
                f"\n{output[-4000:]}"
            )
        time.sleep(0.05)
    detail = f": {last_decode_error}" if last_decode_error else ""
    raise SmokeFailure(
        f"packaged dedicated server did not publish a valid ready file within {timeout:.1f}s{detail}"
    )


def _replace_text(path: Path, value: str) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(value, encoding="utf-8")
    os.replace(temporary, path)


def _terminate_process_group(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return
        except PermissionError:
            if process.poll() is not None:
                return
            raise
        time.sleep(0.05)
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    if process.poll() is None:
        process.wait(timeout=3.0)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    client = subparsers.add_parser("client", help="exercise a client's self-spawned sidecar")
    client.add_argument("--app", required=True, help="client .app bundle or executable")
    client.add_argument("--timeout", type=float, default=DEFAULT_PROCESS_TIMEOUT)
    client.add_argument(
        "--end-level", type=int, choices=range(1, DEFAULT_END_LEVEL + 1)
    )
    client_reject = subparsers.add_parser(
        "client-reject",
        help="prove an exported client rejects an invalid campaign boundary",
    )
    client_reject.add_argument("--app", required=True, help="client .app bundle or executable")
    client_reject.add_argument("--timeout", type=float, default=DEFAULT_PROCESS_TIMEOUT)
    client_reject.add_argument("--end-level", type=int, required=True)
    server = subparsers.add_parser("server", help="exercise a dedicated server app")
    server.add_argument("--app", required=True, help="server .app bundle or executable")
    server.add_argument("--startup-timeout", type=float, default=DEFAULT_STARTUP_TIMEOUT)
    server.add_argument("--shutdown-timeout", type=float, default=DEFAULT_SHUTDOWN_TIMEOUT)
    server.add_argument("--probe-timeout", type=float, default=DEFAULT_PROBE_TIMEOUT)
    server.add_argument(
        "--end-level", type=int, choices=range(1, DEFAULT_END_LEVEL + 1)
    )
    server.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    server.add_argument("--project", default=str(DEFAULT_PROJECT))
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        if args.command == "client":
            result = run_client_smoke(args.app, args.timeout, args.end_level)
        elif args.command == "client-reject":
            result = run_client_rejection_smoke(args.app, args.timeout, args.end_level)
        else:
            result = run_server_smoke(
                args.app,
                args.startup_timeout,
                args.shutdown_timeout,
                args.godot,
                args.project,
                args.probe_timeout,
                args.end_level,
            )
    except (OSError, SmokeFailure, subprocess.SubprocessError) as error:
        result = {
            "schema": SCHEMA,
            "kind": (
                "client_self_sidecar"
                if args.command == "client"
                else "client_boundary_rejection"
                if args.command == "client-reject"
                else "dedicated_server"
            ),
            "ok": False,
            "error": str(error),
        }
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
        return 2
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
