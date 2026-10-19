"""Local deterministic Responses fixture. No model, credentials or forwarding."""
from __future__ import annotations

import json
from pathlib import Path
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class ScriptedProvider:
    def __init__(self, output, program):
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=False)
        self.program = program
        self.requests = []
        self.condition = None
        self.final_only = False
        self.error = None
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_POST(self):
                try:
                    length = int(self.headers.get("Content-Length", 0))
                    if self.path != "/v1/responses" or not 0 < length <= 2 * 1024 * 1024:
                        raise ValueError("Unexpected fixture endpoint or request size")
                    if self.headers.get("Authorization"):
                        raise ValueError("Fixture received an unexpected credential")
                    self.connection.settimeout(5)
                    body = json.loads(self.rfile.read(length))
                    if body["model"] != "gpt-5.6-sol" or not body["stream"] or owner.condition is None:
                        raise ValueError("Unexpected fixture request")
                    phase = sum(row["condition"] == owner.condition for row in owner.requests)
                    if phase >= (1 if owner.final_only else 2):
                        raise ValueError("Fixture received an unplanned extra request")
                    record = dict(condition=owner.condition, final_only=owner.final_only, body=body)
                    owner.requests.append(record)
                    index = len(owner.requests)
                    (owner.output / f"request-{index}.json").write_text(json.dumps(record, indent=2) + "\n")
                    if phase == 0 and not owner.final_only:
                        item = dict(type="custom_tool_call", id=f"ct_fixture_{index}",
                                    call_id=f"call_fixture_{index}", name="exec", input=owner.program)
                    else:
                        item = dict(type="message", id=f"msg_fixture_{index}", role="assistant",
                                    status="completed", phase="final_answer", content=[dict(
                                        type="output_text", text="SCRIPTED HOOK PROBE COMPLETE", annotations=[])])
                    response = dict(id=f"resp_fixture_{index}", object="response", created_at=int(time.time()),
                                    status="in_progress", model=body["model"], output=[],
                                    error=None, incomplete_details=None, usage=None)
                    events = [dict(type="response.created", response=response),
                              dict(type="response.output_item.added", output_index=0, item=item),
                              dict(type="response.output_item.done", output_index=0, item=item),
                              dict(type="response.completed", response={
                                  **response, "status": "completed", "output": [item]})]
                    data = "".join("event: " + event["type"] + "\ndata: " +
                                   json.dumps(dict(**event, sequence_number=i)) + "\n\n"
                                   for i, event in enumerate(events)).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except Exception as error:
                    owner.error = f"{type(error).__name__}: {error}"
                    self.send_error(400, "Scripted fixture rejected request")

        self.http = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.http.daemon_threads = True
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)

    @property
    def url(self):
        return f"http://127.0.0.1:{self.http.server_port}/v1"

    def begin(self, condition, final_only=False):
        if any(row["condition"] == condition for row in self.requests):
            raise ValueError("Fixture condition already ran")
        self.condition = condition
        self.final_only = final_only

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join(timeout=2)
        (self.output / "result.json").write_text(json.dumps(dict(
            error=self.error, requests=len(self.requests), listener_stopped=not self.thread.is_alive(),
            scripted=True, generation_model_calls=0, pilot_model_runs=0), indent=2) + "\n")
