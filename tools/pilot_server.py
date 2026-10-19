#!/usr/bin/env python3
"""Zero-generation App Server preflight transport; cannot start model turns."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import queue
import select
import signal
import subprocess
import threading
import time


METHODS = {"initialize", "config/read", "configRequirements/read", "hooks/list", "skills/list",
           "mcpServerStatus/list", "permissionProfile/list", "command/exec"}
REDACT = {"config/read", "configRequirements/read"}


class Server:
    """One sequential RPC client. Metadata inspection never authorizes generation."""

    def __init__(self, command, cwd, env, output, timeout=45):
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=False)
        self.timeout = timeout
        self.messages = queue.Queue(maxsize=128)
        self.lock = threading.Lock()
        self.requests = {}
        self.next_id = 0
        self.bytes_written = 0
        self.closed = False
        self.stop = threading.Event()
        self.generation_events = []
        self.log = (self.output / "exchange.jsonl").open("w")
        self.errors = (self.output / "stderr.log").open("w")
        self.process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=self.errors,
                                        start_new_session=True)
        os.set_blocking(self.process.stdin.fileno(), False)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _record(self, direction, message):
        if direction == "server" and self.requests.get(message.get("id")) in REDACT:
            raw = json.dumps(message, sort_keys=True).encode()
            message = dict(id=message["id"], redacted=True,
                           response_sha256=hashlib.sha256(raw).hexdigest())
        encoded = json.dumps(dict(direction=direction, message=message,
                                  monotonic_ns=time.monotonic_ns())) + "\n"
        self.bytes_written += len(encoded.encode())
        if self.bytes_written > 32 * 1024 * 1024:
            raise RuntimeError("Preflight transcript exceeds 32 MiB")
        self.log.write(encoded)
        self.log.flush()

    def _read(self):
        pending = b""
        descriptor = self.process.stdout.fileno()
        try:
            while not self.stop.is_set():
                if not select.select([descriptor], [], [], 0.1)[0]:
                    continue
                chunk = os.read(descriptor, 65536)
                if not chunk:
                    raise EOFError("App Server stdout closed mid-message" if pending
                                   else "App Server stdout closed")
                pending += chunk
                while b"\n" in pending:
                    raw, pending = pending.split(b"\n", 1)
                    if len(raw) > 1024 * 1024:
                        raise RuntimeError("App Server message exceeds 1 MiB")
                    message = json.loads(raw)
                    if not isinstance(message, dict):
                        raise ValueError("App Server message must be an object")
                    with self.lock:
                        self._record("server", message)
                        if message.get("method") in {"turn/started", "thread/tokenUsage/updated"}:
                            self.generation_events.append(message["method"])
                    self.messages.put(message, timeout=1)
                if len(pending) > 1024 * 1024:
                    raise RuntimeError("App Server message exceeds 1 MiB")
        except Exception as error:
            try:
                self.messages.put(error, timeout=1)
            except queue.Full:
                pass

    def request(self, method, params):
        if method not in METHODS:
            raise ValueError(f"Preflight cannot invoke {method}")
        if self.closed:
            raise RuntimeError("App Server client is closed")
        identity = self.next_id
        self.next_id += 1
        message = dict(id=identity, method=method, params=params)
        with self.lock:
            self.requests[identity] = method
            self._record("client", message)
            self._write(message)
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"App Server {method} timed out")
            try:
                response = self.messages.get(timeout=remaining)
            except queue.Empty:
                raise TimeoutError(f"App Server {method} timed out") from None
            if isinstance(response, Exception):
                raise response
            if "id" not in response:
                if response.get("method") in {"turn/started", "thread/tokenUsage/updated"}:
                    raise RuntimeError("Unexpected generation event during preflight")
                continue
            if "method" in response:
                raise RuntimeError("Unexpected server-initiated request during preflight")
            if response["id"] != identity:
                raise RuntimeError("App Server response ID does not match active request")
            if "error" in response:
                raise RuntimeError(f"App Server {method} failed: {response['error']}")
            return response["result"]

    def _write(self, message):
        pending = memoryview((json.dumps(message) + "\n").encode())
        if len(pending) > 1024 * 1024:
            raise ValueError("Preflight request exceeds 1 MiB")
        descriptor = self.process.stdin.fileno()
        deadline = time.monotonic() + self.timeout
        while pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([], [descriptor], [], max(0, remaining))[1]:
                raise TimeoutError("App Server stdin timed out")
            try:
                pending = pending[os.write(descriptor, pending):]
            except BlockingIOError:
                continue

    def initialize(self, client_version):
        result = self.request("initialize", dict(clientInfo=dict(
            name="eggshell_pilot_preflight", version=client_version),
            capabilities=dict(experimentalApi=True)))
        with self.lock:
            message = dict(method="initialized", params={})
            self._record("client", message)
            self._write(message)
        return result

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.stop.set()
        try:
            self.process.stdin.close()
            self.process.wait(timeout=1)
        except (BrokenPipeError, subprocess.TimeoutExpired):
            pass
        finally:
            # The process can exit while children still occupy its process group.
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.wait(timeout=3)
            self.reader.join(timeout=2)
            self.process.stdout.close()
            self.log.close()
            self.errors.close()
            (self.output / "process.json").write_text(json.dumps(dict(
                pid=self.process.pid, exit_code=self.process.returncode,
                methods=list(self.requests.values()), reader_stopped=not self.reader.is_alive(),
                observed_generation_events=self.generation_events), indent=2) + "\n")

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
