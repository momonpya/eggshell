#!/usr/bin/env python3
"""Synthetic transport failure controls. No Codex instance or model is started."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from pilot_server import Server
from pilot_hook_probe import native_read_result


class TransportControls(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)

    def tearDown(self):
        self.folder.cleanup()

    def server(self, code, timeout=0.3):
        return Server([sys.executable, "-u", "-c", code], self.root, os.environ.copy(),
                      self.root / "rpc", timeout=timeout)

    def stopped(self, server):
        result = json.loads((self.root / "rpc/process.json").read_text())
        self.assertTrue(result["reader_stopped"])
        self.assertIsNotNone(server.process.poll())
        with self.assertRaises(ProcessLookupError):
            os.killpg(server.process.pid, 0)

    def test_fragmented_response_and_notification(self):
        code = '''import sys,json,time
request=json.loads(sys.stdin.readline())
print(json.dumps(dict(method='status/updated',params={})),flush=True)
wire=json.dumps(dict(id=request['id'],result=dict(ok=True)))+'\\n'
sys.stdout.write(wire[:5]);sys.stdout.flush();time.sleep(.01)
sys.stdout.write(wire[5:]);sys.stdout.flush()
sys.stdin.read()
'''
        with self.server(code) as server:
            self.assertEqual(server.request("hooks/list", {}), dict(ok=True))
        self.stopped(server)

    def test_model_methods_are_rejected_before_sending(self):
        with self.server("import sys;sys.stdin.read()") as server:
            for method in ("thread/start", "turn/start", "thread/resume", "review/start", "account/login/start"):
                with self.assertRaisesRegex(ValueError, "cannot invoke"):
                    server.request(method, {})
        self.assertEqual((self.root / "rpc/exchange.jsonl").read_text(), "")
        self.stopped(server)

    def test_wrong_response_id_is_rejected(self):
        with self.server("import sys;sys.stdin.readline();print('{\"id\":99,\"result\":{}}',flush=True)") as server:
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                server.request("hooks/list", {})
        self.stopped(server)

    def test_server_request_is_never_executed(self):
        code = "import sys;sys.stdin.readline();print('{\"id\":9,\"method\":\"execute\",\"params\":{}}',flush=True)"
        with self.server(code) as server:
            with self.assertRaisesRegex(RuntimeError, "server-initiated"):
                server.request("hooks/list", {})
        self.stopped(server)

    def test_unexpected_generation_is_rejected_and_recorded(self):
        code = "import sys;sys.stdin.readline();print('{\"method\":\"turn/started\",\"params\":{}}',flush=True)"
        with self.server(code) as server:
            with self.assertRaisesRegex(RuntimeError, "generation event"):
                server.request("hooks/list", {})
        result = json.loads((self.root / "rpc/process.json").read_text())
        self.assertEqual(result["observed_generation_events"], ["turn/started"])
        self.stopped(server)

    def test_missing_response_times_out_and_cleans_process_group(self):
        code = "import sys,time;sys.stdin.readline();time.sleep(60)"
        with self.server(code, timeout=0.05) as server:
            with self.assertRaises(TimeoutError):
                server.request("hooks/list", {})
        self.stopped(server)

    def test_stalled_stdin_has_a_deadline(self):
        with self.server("import time;time.sleep(60)", timeout=0.05) as server:
            with self.assertRaisesRegex(TimeoutError, "stdin timed out"):
                server.request("config/read", dict(cwd="x" * 800000))
        self.stopped(server)

    def test_notification_before_rpc_response_is_retained(self):
        code = '''import sys,json
r=json.loads(sys.stdin.readline())
print(json.dumps(dict(method='hook/completed',params=dict(id='early'))),flush=True)
print(json.dumps(dict(id=r['id'],result={})),flush=True)
sys.stdin.read()
'''
        with self.server(code) as server:
            server.request("hooks/list", {})
            self.assertEqual(server.wait_notification("hook/completed", lambda p:p["id"] == "early"), dict(id="early"))
        self.stopped(server)

    def test_waiting_for_missing_notification_times_out(self):
        code = "import sys,json;r=json.loads(sys.stdin.readline());print(json.dumps(dict(id=r['id'],result={})),flush=True);sys.stdin.read()"
        with self.server(code, timeout=0.05) as server:
            server.request("hooks/list", {})
            with self.assertRaises(TimeoutError):
                server.wait_notification("hook/completed", lambda _:True)
        self.stopped(server)

    def test_probe_program_is_not_terminal_output_evidence(self):
        body = dict(input=[dict(type="custom_tool_call", input="PILOT_NATIVE_READ:abc\nPILOT_OUTSIDE_READ_DENIED\n")])
        with self.assertRaises(ValueError):
            native_read_result(body, "abc")

    def test_probe_uses_only_structured_terminal_output(self):
        expected = "PILOT_NATIVE_READ:abc\nPILOT_OUTSIDE_READ_DENIED\n"
        body = dict(input=[dict(type="custom_tool_call", input="PILOT_OUTSIDE_READ_ALLOWED"),
                           dict(type="custom_tool_call_output", output=[dict(type="input_text",
                                text=json.dumps(dict(exit_code=0, output=expected)))])])
        self.assertEqual(native_read_result(body, "abc"), expected)
        for code, text in ((1, expected), (0, expected.replace("DENIED", "ALLOWED")), (0, expected.replace("abc", "wrong"))):
            body["input"][1]["output"][0]["text"] = json.dumps(dict(exit_code=code, output=text))
            with self.assertRaises(ValueError):
                native_read_result(body, "abc")

    def test_eof_and_malformed_messages_fail(self):
        for wire in ("", "{", "[]\n", "broken\n"):
            with self.subTest(wire=wire):
                output = self.root / "rpc"
                if output.exists():
                    self.folder.cleanup()
                    self.folder = tempfile.TemporaryDirectory()
                    self.root = Path(self.folder.name)
                with self.server(f"import sys;sys.stdin.readline();sys.stdout.write({wire!r});sys.stdout.flush()") as server:
                    with self.assertRaises((EOFError, ValueError)):
                        server.request("hooks/list", {})
                self.stopped(server)

    def test_oversized_message_is_bounded(self):
        code = "import sys;sys.stdin.readline();sys.stdout.write('x'*(1024*1024+1));sys.stdout.flush()"
        with self.server(code) as server:
            with self.assertRaisesRegex(RuntimeError, "exceeds 1 MiB"):
                server.request("hooks/list", {})
        self.stopped(server)

    def test_configuration_responses_are_redacted(self):
        code = "import sys,json;r=json.loads(sys.stdin.readline());print(json.dumps(dict(id=r['id'],result=dict(secret='synthetic-secret'))),flush=True)"
        with self.server(code) as server:
            self.assertEqual(server.request("config/read", {})["secret"], "synthetic-secret")
        capture = (self.root / "rpc/exchange.jsonl").read_text()
        self.assertNotIn("synthetic-secret", capture)
        message = json.loads(capture.splitlines()[1])["message"]
        self.assertTrue(message["redacted"])
        self.assertEqual(len(message["response_sha256"]), 64)
        self.stopped(server)

    def test_existing_output_is_immutable_on_cli_failure(self):
        output = self.root / "prior-failure"
        output.mkdir()
        sentinel = output / "failure.json"
        sentinel.write_text('{"original":true}\n')
        command = [sys.executable, "-B", str(Path(__file__).with_name("pilot_preflight.py")),
                   "--suite", str(self.root / "missing-suite"), "--output", str(output)]
        process = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(process.returncode, 2)
        self.assertEqual(sentinel.read_text(), '{"original":true}\n')
        self.assertEqual(list(output.iterdir()), [sentinel])


if __name__ == "__main__":
    unittest.main(verbosity=2)
