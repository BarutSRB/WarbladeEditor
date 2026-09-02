#!/usr/bin/env python3
"""End-to-end smoke for the lobby server using only the standard library.

Two players register, chat, host and join a lobby, report a match, and spend
and refund talent points. Runs in about a second against a live server:

    python3 tools/lobby_smoke.py --host 127.0.0.1 --ws-port 7400

or spawn a throwaway server on high ports with a temporary database:

    python3 tools/lobby_smoke.py --spawn lobby-server/target/debug/warblade-lobby
"""

import argparse
import base64
import hashlib
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class SmokeFailure(Exception):
    pass


class MiniWs:
    """A minimal RFC 6455 client: text frames, masked sends, ping/pong, close."""

    def __init__(self, host, port, path="/ws", timeout=5.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.buffer = b""
        self.rid = 0
        self.pending = []
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, host, port, key)
        ).encode()
        self.sock.sendall(request)
        headers = self._read_until(b"\r\n\r\n")
        status_line = headers.split(b"\r\n", 1)[0]
        if b" 101 " not in status_line:
            raise SmokeFailure("websocket upgrade refused: %r" % status_line)
        expected = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        if expected.encode() not in headers:
            raise SmokeFailure("websocket accept key mismatch")

    def _read_until(self, marker):
        while marker not in self.buffer:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise SmokeFailure("connection closed during handshake")
            self.buffer += chunk
        index = self.buffer.index(marker) + len(marker)
        head, self.buffer = self.buffer[:index], self.buffer[index:]
        return head

    def _read_exact(self, count):
        while len(self.buffer) < count:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise SmokeFailure("connection closed")
            self.buffer += chunk
        data, self.buffer = self.buffer[:count], self.buffer[count:]
        return data

    def _send_frame(self, opcode, payload):
        mask = os.urandom(4)
        header = bytes([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header += bytes([0x80 | length])
        elif length < 65536:
            header += bytes([0x80 | 126]) + length.to_bytes(2, "big")
        else:
            header += bytes([0x80 | 127]) + length.to_bytes(8, "big")
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def send(self, message):
        self._send_frame(0x1, json.dumps(message).encode())

    def close(self):
        try:
            self._send_frame(0x8, (1000).to_bytes(2, "big"))
        except OSError:
            pass
        self.sock.close()

    def _read_message(self):
        while True:
            first, second = self._read_exact(2)
            opcode = first & 0x0F
            length = second & 0x7F
            if length == 126:
                length = int.from_bytes(self._read_exact(2), "big")
            elif length == 127:
                length = int.from_bytes(self._read_exact(8), "big")
            if second & 0x80:
                self._read_exact(4)
            payload = self._read_exact(length)
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x8:
                code = int.from_bytes(payload[:2], "big") if len(payload) >= 2 else 0
                raise SmokeFailure("server closed the socket (code %d %r)" % (code, payload[2:]))
            if opcode == 0x1:
                return json.loads(payload.decode())
            raise SmokeFailure("unexpected opcode %d" % opcode)

    def request(self, request_type, **fields):
        self.rid += 1
        rid = self.rid
        message = {"t": request_type, "rid": rid}
        message.update(fields)
        self.send(message)
        while True:
            incoming = self._read_message()
            if incoming.get("rid") == rid:
                return incoming
            self.pending.append(incoming)

    def expect_ok(self, request_type, **fields):
        response = self.request(request_type, **fields)
        if not response.get("ok"):
            raise SmokeFailure("%s failed: %s" % (request_type, response.get("error")))
        return response

    def expect_error(self, code, request_type, **fields):
        response = self.request(request_type, **fields)
        actual = (response.get("error") or {}).get("code")
        if response.get("ok") or actual != code:
            raise SmokeFailure("%s should fail with %s, got %s" % (request_type, code, response))
        return response

    def wait_push(self, push_type, timeout=3.0):
        for index, message in enumerate(self.pending):
            if message.get("t") == push_type and "rid" not in message:
                return self.pending.pop(index)
        deadline = time.time() + timeout
        previous_timeout = self.sock.gettimeout()
        try:
            while time.time() < deadline:
                self.sock.settimeout(max(0.05, deadline - time.time()))
                try:
                    incoming = self._read_message()
                except socket.timeout:
                    break
                if incoming.get("t") == push_type and "rid" not in incoming:
                    return incoming
                self.pending.append(incoming)
        finally:
            self.sock.settimeout(previous_timeout)
        raise SmokeFailure("no %s push within %.1fs (pending: %s)" % (push_type, timeout, [m.get("t") for m in self.pending]))


def check(condition, message):
    if not condition:
        raise SmokeFailure(message)


def connect_player(host, port, content_hash, device_key, nickname=None):
    ws = MiniWs(host, port)
    hello = ws.expect_ok("hello", protocol=1, content_hash=content_hash, client_version="smoke", platform="python")
    check(hello.get("protocol") == 1, "hello reports protocol 1")
    auth = ws.expect_ok("auth", device_key=device_key)
    ws.nickname = nickname
    if nickname is not None:
        check(not auth.get("registered"), "a fresh key is unregistered")
        registered = ws.expect_ok("register", nickname=nickname)
        check(registered["account"]["nickname"] == nickname, "registration echoes the nickname")
        check("talents" in registered, "registration carries the talent state")
    else:
        ws.nickname = (auth.get("account") or {}).get("nickname")
    return ws, auth


def run_smoke(host, ws_port, udp_port):
    content_hash = "a" * 64
    key_a = secrets.token_hex(32)
    key_b = secrets.token_hex(32)
    nick_a = "smoke_%s" % secrets.token_hex(3)
    nick_b = "smoke_%s" % secrets.token_hex(3)

    a, _ = connect_player(host, ws_port, content_hash, key_a, nick_a)
    b, _ = connect_player(host, ws_port, content_hash, key_b, nick_b)
    a.expect_error("NICKNAME_TAKEN", "set_nickname", nickname=nick_b.upper())
    a.expect_error("INVALID_NICKNAME", "set_nickname", nickname="no")

    # Reconnecting with the same key restores the account and kicks the old session.
    a2, auth = connect_player(host, ws_port, content_hash, key_a)
    check(auth.get("registered") and auth["account"]["nickname"] == nick_a, "a known key authenticates as its account")
    try:
        a.wait_push("kicked", timeout=2.0)
    except SmokeFailure:
        raise SmokeFailure("the older session was not kicked")
    a.close()
    a = a2

    # Global chat.
    sent = a.expect_ok("chat_send", body="hello from " + nick_a)
    line = b.wait_push("chat_message")
    check(line["nickname"] == nick_a and line["id"] == sent["id"], "chat reaches the other player")
    history = b.expect_ok("chat_history", limit=10)
    check(any(m["id"] == sent["id"] for m in history["messages"]), "chat history stores the line")
    a.expect_error("SCHEMA_MISMATCH", "chat_send", body="x" * 201)

    # Lobby list and creation.
    created = a.expect_ok(
        "lobby_create",
        name="SMOKE",
        mode="coop",
        difficulty="normal",
        coop_balance="classic",
        game_token="smoke-token",
        port=42000,
        lan={"ip": "127.0.0.1", "port": 42000},
        upnp_mapped=False,
    )
    lobby_id = created["lobby"]["lobby_id"]
    check(created["lobby"]["game_token"] == "smoke-token", "the host sees the game token")
    b.wait_push("lobby_list_changed")
    listed = b.expect_ok("lobby_list")
    rows = [row for row in listed["lobbies"] if row["lobby_id"] == lobby_id]
    check(len(rows) == 1 and rows[0]["state"] == "open", "the lobby is listed as open")
    check(rows[0]["content_matches"] is True, "matching content is flagged")
    check("game_token" not in rows[0], "the list never leaks the token")
    a.expect_error("ALREADY_IN_LOBBY", "lobby_create", name="X", mode="coop", difficulty="normal", coop_balance="classic", game_token="t", port=42001)
    a.expect_error("SELF_JOIN", "lobby_join_request", lobby_id=lobby_id)

    # Join handshake.
    pending = b.expect_ok("lobby_join_request", lobby_id=lobby_id, lan={"ip": "127.0.0.1", "port": 50000})
    check(pending["status"] == "pending", "join is pending until the host answers")
    offer = a.wait_push("lobby_join_offer")
    check(offer["joiner"]["nickname"] == nick_b, "the host learns who is joining")
    check(offer["joiner"]["lan"]["port"] == 50000, "the host learns the joiner's LAN endpoint")
    a.expect_ok("lobby_join_answer", join_id=offer["join_id"], accept=True)
    ready = b.wait_push("lobby_join_ready")
    check(ready["game_token"] == "smoke-token", "the joiner receives the game token")
    check(ready["host_lan"]["port"] == 42000, "the joiner receives the host LAN endpoint")
    check(ready["same_public_ip"] is True, "two loopback sessions share a public address")
    listed = b.expect_ok("lobby_list")
    rows = [row for row in listed["lobbies"] if row["lobby_id"] == lobby_id]
    check(rows and rows[0]["state"] == "full" and rows[0]["player_count"] == 2, "an accepted join fills the lobby")

    # Match records credit both players.
    before = a.expect_ok("talent_state")["state"]["wallet"]["talent_points"]
    started = a.expect_ok("match_start", kind="hosted", mode="coop", difficulty="normal", coop_balance="classic", seed="42", start_level=1, end_level=3999, content_hash=content_hash)
    ended = a.expect_ok("match_end", match_id=started["match_id"], result="game_over", score=250000, level_reached=12, duration_ticks=3600, campaign_completed=False)
    check(ended["points_awarded"] >= 15, "a 250k run earns points")
    check(ended["state"]["wallet"]["talent_points"] == before + ended["points_awarded"], "the reply carries the refreshed wallet")
    credited = b.wait_push("points_credited")
    check(credited["points"] == ended["points_awarded"], "the joiner is credited the same points")
    repeat = a.expect_ok("match_end", match_id=started["match_id"], result="game_over", score=250000, level_reached=12)
    check(repeat["already_recorded"] is True and repeat["points_awarded"] == 0, "a repeated report credits nothing")
    solo = a.expect_ok("match_end", kind="solo", mode="solo", difficulty="hard", coop_balance="classic", result="completed", score=1000000, level_reached=100, campaign_completed=True)
    check(solo["points_awarded"] >= 40, "a completed solo campaign earns the completion bonus")

    # Talents.
    state = a.expect_ok("talent_state")["state"]
    points = state["wallet"]["talent_points"]
    check(points >= 10, "enough points to buy the first talent")
    spent = a.expect_ok("talent_spend", node_id="gunnery_capacity_1")
    check(spent["state"]["talents"]["nodes"].get("gunnery_capacity_1") == 1, "the node is owned")
    check(spent["state"]["grants"]["start_state"]["bullet_capacity"] == 8, "grants recompute")
    a.expect_error("TALENT_ALREADY_OWNED", "talent_spend", node_id="gunnery_capacity_1")
    a.expect_error("TALENT_PREREQ_MISSING", "talent_spend", node_id="gunnery_capacity_3")
    a.expect_error("TALENT_UNKNOWN_NODE", "talent_spend", node_id="nope")
    refunded = a.expect_ok("talent_respec")
    check(refunded["state"]["wallet"]["talent_points"] == points, "respec refunds every point")
    check(not refunded["state"]["talents"]["nodes"], "respec clears the tree")

    # Leaving and closing.
    b.expect_ok("lobby_leave")
    left = a.wait_push("lobby_joiner_left")
    check(left["nickname"] == nick_b, "the host learns the joiner left")
    a.expect_ok("lobby_close", lobby_id=lobby_id)
    listed = b.expect_ok("lobby_list")
    check(not any(row["lobby_id"] == lobby_id for row in listed["lobbies"]), "a closed lobby disappears")
    b.expect_error("NOT_IN_LOBBY", "lobby_leave")
    b.expect_error("SCHEMA_MISMATCH", "no_such_request")

    if udp_port:
        probe_udp(host, udp_port, a)
    if ADMIN["url"]:
        probe_admin(a, b)

    a.close()
    b.close()


ADMIN = {"url": "", "token": ""}


def admin_call(path, payload=None):
    request = urllib.request.Request(ADMIN["url"] + path, method="POST" if payload is not None else "GET")
    request.add_header("Authorization", "Bearer " + ADMIN["token"])
    data = None
    if payload is not None:
        request.add_header("Content-Type", "application/json")
        data = json.dumps(payload).encode()
    try:
        with urllib.request.urlopen(request, data=data, timeout=3.0) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return json.loads(error.read().decode())


def probe_admin(a, b):
    """The owner surface: token-gated JSON, live pushes from admin actions."""
    denied = urllib.request.Request(ADMIN["url"] + "/admin/api/overview")
    try:
        urllib.request.urlopen(denied, timeout=3.0)
        raise SmokeFailure("the admin api must refuse requests without the token")
    except urllib.error.HTTPError as error:
        check(error.code == 401, "a missing token answers 401")
    overview = admin_call("/admin/api/overview")
    check(overview.get("ok") and overview["overview"]["connections"]["current"] >= 2, "the overview counts live sessions")
    sessions = admin_call("/admin/api/sessions")
    check(any(s.get("nickname") for s in sessions["sessions"]), "the session list names registered players")
    accounts = admin_call("/admin/api/accounts?query=smoke")
    check(len(accounts["accounts"]) >= 2, "the account list filters by nickname")
    account_b = next(acc for acc in accounts["accounts"] if acc["nickname"] == b_nickname(b))
    granted = admin_call("/admin/api/accounts/%d/points" % account_b["id"], {"delta": 12})
    check(granted.get("ok"), "the owner can grant points")
    credited = b.wait_push("points_credited")
    check(credited["points"] == 12 and credited["reason"] == "admin", "granted points reach the live session")
    renamed = admin_call("/admin/api/accounts/%d/rename" % account_b["id"], {"nickname": "rn_%s" % secrets.token_hex(3)})
    check(renamed.get("ok"), "the owner can rename an account")
    b.wait_push("notice")
    sent = admin_call("/admin/api/notice", {"message": "maintenance in five minutes"})
    check(sent.get("ok") and sent["recipients"] >= 2, "a notice reaches every registered session")
    a.wait_push("notice")
    matches = admin_call("/admin/api/matches?limit=10")
    check(matches.get("ok") and matches["matches"] and matches["matches"][0]["players"], "recent matches list their players")
    chat = admin_call("/admin/api/chat?limit=10")
    check(chat.get("ok") and chat["messages"], "the chat history is readable")
    page = urllib.request.urlopen(ADMIN["url"] + "/admin", timeout=3.0).read().decode()
    check("WARBLADE LOBBY ADMIN" in page, "the admin page serves")


def b_nickname(ws):
    return ws.nickname


def probe_udp(host, udp_port, ws):
    """Rendezvous: an unregistered nonce gets no echo; a registered one is
    echoed with the observed endpoint and pushed to the owning session."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.5)
    try:
        stray = os.urandom(16)
        sock.sendto(b"WBRZ" + bytes([1, 1]) + stray, (host, udp_port))
        try:
            sock.recvfrom(64)
            raise SmokeFailure("an unregistered nonce must not be echoed")
        except socket.timeout:
            pass
        nonce = os.urandom(16)
        registered = ws.expect_ok("rendezvous_register", nonce=nonce.hex())
        check(registered.get("observed") is None, "a fresh nonce has no observation yet")
        sock.sendto(b"WBRZ" + bytes([1, 1]) + nonce, (host, udp_port))
        data, _ = sock.recvfrom(64)
        check(len(data) == 28 and data[:4] == b"WBRZ" and data[5] == 2, "a registered nonce is echoed")
        check(data[6:22] == nonce, "the echo carries the nonce")
        echoed_port = int.from_bytes(data[26:28], "big")
        check(echoed_port == sock.getsockname()[1], "the echo reports the observed source port on loopback")
        observed = ws.wait_push("rendezvous_observed")
        check(observed["public"]["port"] == echoed_port, "the owning session learns the observed endpoint")
        created = ws.expect_ok(
            "lobby_create", name="UDP", mode="coop", difficulty="normal", coop_balance="classic",
            game_token="udp-token", port=echoed_port, upnp_mapped=False,
        )
        check(created["lobby"]["public"]["port"] == echoed_port, "a fresh lobby advertises the observed endpoint")
        ws.expect_ok("lobby_close", lobby_id=created["lobby"]["lobby_id"])
    finally:
        sock.close()


def wait_for_health(host, port, timeout=15.0):
    deadline = time.time() + timeout
    url = "http://%s:%d/healthz" % (host, port)
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1.0) as response:
                if response.status == 200:
                    return
        except Exception:
            time.sleep(0.1)
    raise SmokeFailure("server did not become healthy at %s" % url)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--ws-port", type=int, default=7400)
    parser.add_argument("--udp-port", type=int, default=0, help="probe the rendezvous socket (0 skips)")
    parser.add_argument("--spawn", help="path to a warblade-lobby binary to start on ports 17400/17401 with a temp database")
    parser.add_argument("--talents", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "content", "talents.json"))
    parser.add_argument("--admin-url", default="", help="admin listener, e.g. http://127.0.0.1:7402 (set with --admin-token)")
    parser.add_argument("--admin-token", default=os.environ.get("WB_ADMIN_TOKEN", ""))
    args = parser.parse_args()

    process = None
    temp_dir = None
    host, ws_port, udp_port = args.host, args.ws_port, args.udp_port
    if args.spawn:
        host, ws_port, udp_port = "127.0.0.1", 17400, 17401
        temp_dir = tempfile.mkdtemp(prefix="warblade-lobby-smoke-")
        env = dict(os.environ)
        env.update({
            "WB_WS_BIND": "%s:%d" % (host, ws_port),
            "WB_UDP_BIND": "%s:%d" % (host, udp_port),
            "WB_DB_PATH": os.path.join(temp_dir, "lobby.db"),
            "WB_TALENTS_PATH": args.talents,
            "WB_LOG": os.environ.get("WB_LOG", "warn"),
        })
        env["WB_ADMIN_BIND"] = "127.0.0.1:17402"
        env["WB_ADMIN_TOKEN"] = "smoke-admin-token-0123456789"
        ADMIN["url"] = "http://127.0.0.1:17402"
        ADMIN["token"] = env["WB_ADMIN_TOKEN"]
        process = subprocess.Popen([args.spawn], env=env)
    elif args.admin_url and args.admin_token:
        ADMIN["url"] = args.admin_url.rstrip("/")
        ADMIN["token"] = args.admin_token
    try:
        if process is not None:
            wait_for_health(host, ws_port)
        run_smoke(host, ws_port, udp_port)
        print("LOBBY SMOKE PASSED")
        return 0
    except SmokeFailure as failure:
        print("LOBBY SMOKE FAILED: %s" % failure, file=sys.stderr)
        return 1
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        if temp_dir is not None:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
