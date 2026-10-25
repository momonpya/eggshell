"""Numerical boundary: original binary64 -> float32 -> per-row NumPy dot.

Lean owns source lookup, integrity, cache, framing limits, lifecycle and ranking.
No model, source persistence, routing, selection or authority lives here.
"""
import json
import sys
import time

started = time.perf_counter_ns()
import numpy as np
startup_us = (time.perf_counter_ns() - started) // 1000
first = True


def vector(raw):
    result = np.frombuffer(raw, dtype="<f8")
    if not np.isfinite(result).all():
        raise ValueError("nonfinite packed vector")
    return np.asarray(result, dtype=np.float32)


for line in sys.stdin.buffer:
    requested = time.perf_counter_ns()
    timing = {}
    try:
        header = json.loads(line)
        queries, rows, width = header["queries"], header["rows"], header["width"]
        if not (1 <= queries <= 256 and 1 <= rows <= 256 and 1 <= width <= 4096):
            raise ValueError("invalid bounded numerical frame")
        size = (queries + rows) * width * 8
        raw = sys.stdin.buffer.read(size)
        if len(raw) != size:
            raise ValueError("short numerical frame")
        step = width * 8
        inputs = [vector(memoryview(raw)[i:i + step]) for i in range(0, size, step)]
        score_started = time.perf_counter_ns()
        scores = [max(float(np.dot(q, row)) for q in inputs[:queries])
                  for row in inputs[queries:]]
        timing["scoreUs"] = (time.perf_counter_ns() - score_started) // 1000
        result = {"scores": scores}
    except Exception as error:
        result = {"error": str(error)}
    result["timing"] = dict(timing, startupUs=startup_us if first else 0,
        leaseUs=0, initializeUs=0, encodeUs=0, modelLoaded=False,
        requestUs=(time.perf_counter_ns() - requested) // 1000)
    print(json.dumps(result, allow_nan=False, separators=(",", ":")), flush=True)
    first = False
    if "error" in result:
        break
