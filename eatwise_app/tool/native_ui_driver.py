#!/usr/bin/env python3
"""Local command/ack transport for RunnerUITests; it never talks to the App API."""

import argparse
import base64
import ipaddress
import json
import math
import os
from pathlib import Path
import secrets
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

MAX_BODY = 16 * 1024 * 1024
ACTIONS = {
    "noop", "quit", "activate", "tap", "tapLabel", "tapElement", "swipeUp", "swipeDown",
    "back", "type", "typeFocused", "assertKeyboard", "assertValue", "assertVisible",
    "assertAboveKeyboard", "dump", "screenshot",
}


def local_address(value):
    value = "127.0.0.1" if value == "localhost" else value
    address = ipaddress.ip_address(value)
    if address.version != 4 or address.is_unspecified or address.is_multicast:
        raise ValueError("Use a specific localhost or private LAN IPv4 address")
    if not (address.is_loopback or address.is_private):
        raise ValueError("The driver must stay on localhost/private LAN")
    return value


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def serve(args):
    bind = local_address(args.bind)
    if args.directory:
        directory = Path(args.directory).resolve()
        roots = [Path(tempfile.gettempdir()).resolve(), Path("/tmp").resolve()]
        if not any(directory.is_relative_to(root) and directory != root for root in roots):
            raise ValueError("Artifacts must use a dedicated directory under the system temp directory")
        if directory.exists() and any(directory.iterdir()):
            raise ValueError("Use a fresh empty QA directory; existing artifacts will not be overwritten")
        directory.mkdir(parents=True, exist_ok=True)
    else:
        directory = Path(tempfile.mkdtemp(prefix="eatwise-native-qa-"))
    os.chmod(directory, 0o700)
    token = secrets.token_urlsafe(32)
    token_path = directory / "access-token"
    token_path.write_text(token, encoding="utf-8")
    os.chmod(token_path, 0o600)
    session = secrets.token_hex(12)
    lock = threading.Lock()
    state = {"seq": 0, "pending": None, "acks": {}}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Commands may contain QA passwords; never log request bodies/tokens.

        def respond(self, status, body):
            payload = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def authorized(self):
            expected = f"Bearer {token}"
            if not secrets.compare_digest(self.headers.get("Authorization", ""), expected):
                self.respond(401, {"error": "Driver token required"})
                return False
            return True

        def do_GET(self):
            if not self.authorized():
                return
            with lock:
                if self.path == "/cmd.json":
                    body = state["pending"] or {"seq": 0, "action": "noop", "session": session}
                    self.respond(200, body)
                elif self.path.startswith("/acks/") and self.path.removeprefix("/acks/").isdigit():
                    ack = state["acks"].get(int(self.path.removeprefix("/acks/")))
                    self.respond(200 if ack is not None else 404, ack or {"pending": True})
                elif self.path == "/status":
                    self.respond(200, {"session": session, "lastSeq": state["seq"],
                                       "pendingSeq": (state["pending"] or {}).get("seq")})
                else:
                    self.respond(404, {"error": "Not found"})

        def do_POST(self):
            if not self.authorized():
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= MAX_BODY:
                    raise ValueError("Invalid request size")
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError("Expected a JSON object")
                with lock:
                    if self.path == "/command":
                        if body.get("action") not in ACTIONS:
                            raise ValueError("Unknown action")
                        pending = state["pending"]
                        if pending and pending["expiresAt"] > time.time():
                            self.respond(409, {"error": "Wait for the previous command acknowledgement"})
                            return
                        ttl = min(max(float(body.pop("ttlSeconds", 60)), 5), 120)
                        if not math.isfinite(ttl):
                            raise ValueError("Command TTL must be finite")
                        state["seq"] += 1
                        body.update(seq=state["seq"], session=session, expiresAt=time.time() + ttl)
                        state["pending"] = body
                        write_json(directory / f"command-{state['seq']:04d}.json", body)
                        self.respond(200, {"seq": state["seq"], "session": session})
                    elif self.path == "/ack":
                        seq = body.get("seq")
                        if type(seq) is not int or body.get("session") != session:
                            raise ValueError("Invalid acknowledgement identity")
                        if seq in state["acks"]:
                            self.respond(200, {"stored": True})
                            return
                        if not state["pending"] or state["pending"]["seq"] != seq:
                            raise ValueError("Acknowledgement does not match pending command")
                        if type(body.get("ok")) is not bool:
                            raise ValueError("Acknowledgement needs a boolean ok")
                        image = body.pop("screenshotBase64", None)
                        if image is not None:
                            png = base64.b64decode(image, validate=True)
                            if not png.startswith(b"\x89PNG\r\n\x1a\n"):
                                raise ValueError("Screenshot is not a PNG")
                            destination = directory / f"screenshot-{seq:04d}.png"
                            destination.write_bytes(png)
                            body["screenshotPath"] = str(destination)
                        tree = body.pop("tree", None)
                        if tree is not None:
                            if not isinstance(tree, str):
                                raise ValueError("UI tree must be text")
                            destination = directory / f"tree-{seq:04d}.txt"
                            destination.write_text(tree, encoding="utf-8")
                            body["treePath"] = str(destination)
                        body["receivedAt"] = time.time()
                        write_json(directory / f"ack-{seq:04d}.json", body)
                        state["acks"][seq] = body
                        state["pending"] = None
                        self.respond(200, {"stored": True})
                    else:
                        self.respond(404, {"error": "Not found"})
            except (ValueError, TypeError, OSError) as error:
                self.respond(400, {"error": str(error)})

    server = ThreadingHTTPServer((bind, args.port), Handler)
    print(json.dumps({"url": f"http://{bind}:{args.port}", "directory": str(directory),
                      "tokenFile": str(token_path), "session": session}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def send(args):
    url = args.url.rstrip("/")
    parsed = urlparse(url)
    local_address(parsed.hostname or "")
    if parsed.scheme != "http" or parsed.path or parsed.username or parsed.password:
        raise ValueError("Use the local driver origin, for example http://127.0.0.1:8899")
    token = Path(args.token_file).read_text(encoding="utf-8").strip()
    raw = Path(args.command_file).read_text(encoding="utf-8") if args.command_file else args.json
    command = json.loads(raw)
    if not isinstance(command, dict):
        raise ValueError("Command must be a JSON object")
    command["ttlSeconds"] = args.timeout + 10

    def request(path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = Request(url + path, data=data, headers={"Authorization": f"Bearer {token}",
                      "Content-Type": "application/json"})
        with urlopen(req, timeout=10) as response:
            return json.load(response)

    submitted = request("/command", command)
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            ack = request(f"/acks/{submitted['seq']}")
            print(json.dumps(ack, ensure_ascii=False, indent=2))
            return 0 if ack["ok"] else 1
        except HTTPError as error:
            if error.code != 404:
                raise
        time.sleep(0.2)
    raise TimeoutError(f"No acknowledgement for command {submitted['seq']}; no success assumed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    server = commands.add_parser("serve")
    server.add_argument("--bind", required=True, help="Explicit localhost/private LAN IPv4; never 0.0.0.0")
    server.add_argument("--port", type=int, default=8899)
    server.add_argument("--directory", help="Fresh artifact directory under /tmp or the system temp directory")
    client = commands.add_parser("send")
    client.add_argument("--url", required=True)
    client.add_argument("--token-file", required=True)
    payload = client.add_mutually_exclusive_group(required=True)
    payload.add_argument("--json", help="One JSON command")
    payload.add_argument("--command-file", help="JSON command file; useful for multiline text")
    client.add_argument("--timeout", type=float, default=40)
    args = parser.parse_args()
    try:
        if args.command == "serve":
            serve(args)
            return 0
        if not 0 < args.timeout <= 110:
            raise ValueError("timeout must be greater than zero and at most 110 seconds")
        return send(args)
    except (ValueError, OSError, TimeoutError, HTTPError) as error:
        parser.exit(1, f"native-ui-driver: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
