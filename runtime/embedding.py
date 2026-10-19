"""Numerical boundary only: FastEmbed inference and the existing NumPy kernels.

Selection, identity, windows, persistence, ranking, and protocol supervision are Lean.
"""
import time

process_started = time.perf_counter_ns()

import json
import sys
import fcntl

import numpy as np

encoder = None
lease = None
startup_us = (time.perf_counter_ns() - process_started) // 1000
first_reply = True
timing = {}


def elapsed_us(started):
    return (time.perf_counter_ns() - started) // 1000


def reply(result, requested):
    global first_reply
    result["timing"] = dict(timing, startupUs=startup_us if first_reply else 0,
                            requestUs=elapsed_us(requested), modelLoaded=encoder is not None)
    print(json.dumps(result, allow_nan=False, separators=(",", ":")), flush=True)
    first_reply = False

def model():
    global encoder, lease
    if encoder is None:
        # Cache-only scoring needs no encoder. A real encoder owns this lease
        # throughout its lifetime; the caller's process-group deadline also
        # stops its own waiting child without cancelling the current holder.
        lease = open(sys.argv[4], "a")
        started = time.perf_counter_ns()
        fcntl.flock(lease.fileno(), fcntl.LOCK_EX)
        timing["leaseUs"] = elapsed_us(started)
        started = time.perf_counter_ns()
        try:
            from fastembed import TextEmbedding
            encoder = TextEmbedding(model_name=sys.argv[1], cache_dir=sys.argv[2], threads=int(sys.argv[3]))
        finally:
            timing["initializeUs"] = elapsed_us(started)
    return encoder


def packed_vector(encoded):
    if not isinstance(encoded, str) or not 0 < len(encoded) <= 4096 * 16 or len(encoded) % 16:
        raise ValueError("invalid packed vector dimension")
    raw = bytes.fromhex(encoded)
    if len(raw) * 2 != len(encoded):
        raise ValueError("noncanonical packed vector")
    vector = np.frombuffer(raw, dtype="<f8")
    if not np.isfinite(vector).all():
        raise ValueError("nonfinite packed vector")
    return np.asarray(vector, dtype=np.float32)

if sys.argv[6:] == ["--preload"]:
    next(model().embed(["eggshell"], batch_size=1))
    raise SystemExit(0)
for line in sys.stdin:
    requested = time.perf_counter_ns()
    timing = dict(leaseUs=0, initializeUs=0, encodeUs=0, scoreUs=0)
    try:
        request = json.loads(line)
        if "texts" in request:
            vectors = []
            active = model()
            started = time.perf_counter_ns()
            try:
                for vector in active.embed(request["texts"], batch_size=32):
                    vector = np.asarray(vector, dtype=np.float32)
                    norm = np.linalg.norm(vector)
                    vectors.append((vector if norm == 0 else vector / norm).tolist())
            finally:
                timing["encodeUs"] = elapsed_us(started)
            result = {"vectors": vectors}
        else:
            started = time.perf_counter_ns()
            queries = [packed_vector(v) for v in request["queries"]]
            result = {"scores": [max(float(np.dot(q, packed_vector(v)))
                for q in queries for v in windows) for windows in request["candidates"]]}
            timing["scoreUs"] = elapsed_us(started)
        reply(result, requested)
    except Exception as error:
        reply({"error": str(error)}, requested)
