#!/usr/bin/env python3
"""Prepare the fixed saved latency fixtures; never resave source observations."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np


def digest(path):
    state = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            state.update(chunk)
    return state.hexdigest()


def binary32(values):
    result = np.asarray(values, dtype=np.float32)
    # The old Lean JSON transport normalizes a JSON negative zero to zero.
    result[result == 0] = 0.0
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--helper", type=Path, required=True)
    args = parser.parse_args()
    original, root, helper = args.fixtures.resolve(), args.output.resolve(), args.helper.resolve()
    if root.is_relative_to(original):
        raise RuntimeError("new preparation must be outside the original fixtures")
    root.mkdir(parents=True, exist_ok=False)
    (root / "seeds").mkdir()
    shutil.copy2(__file__, root / "preparation.py")
    records = []
    packer = subprocess.Popen([str(helper), "pack-vectors"], text=True,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def pack(values):
        packer.stdin.write(json.dumps(values, allow_nan=False, separators=(",", ":")) + "\n")
        packer.stdin.flush()
        line = packer.stdout.readline()
        if not line:
            raise RuntimeError("native vector packer stopped")
        encoded = json.loads(line)
        expected = binary32(values)
        actual = np.frombuffer(bytes.fromhex(encoded), dtype="<f8").astype(np.float32)
        if not np.array_equal(expected.view(np.uint32), actual.view(np.uint32)):
            raise RuntimeError("native packing changed original binary32 values")
        return encoded, expected

    try:
        for count in [2, 32, 256, 1024]:
            source, seed = original / "seeds" / str(count), root / "seeds" / str(count)
            if sys.platform == "darwin":
                subprocess.run(["/bin/cp", "-cR", str(source), str(seed)], check=True)
            else:
                shutil.copytree(source, seed)
            database = seed / "source.egg"
            graph = {p.name: digest(p) for p in (source / "source.egg").iterdir() if p.is_file()}
            paths = sorted((database / "derived").glob("*/semantic/vectors/*.json"))
            if len(paths) != count:
                raise RuntimeError("saved fixture does not have the fixed original window count")
            for path in paths:
                before = digest(path)
                record = json.loads(path.read_text())
                values = record["vector"]
                if not isinstance(values, list) or len(values) != 384 or "text" in record:
                    raise RuntimeError("expected the original digest-only binary32 fixture")
                encoded, expected = pack(values)
                if not np.isfinite(expected).all():
                    raise RuntimeError("original fixture has a nonfinite numerical window")
                record["vector"] = encoded
                path.write_text(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
                records.append(dict(sources=count, path=str(path.relative_to(root)),
                                    beforeSha256=before, afterSha256=digest(path), dimensions=384,
                                    float32Sha256=hashlib.sha256(expected.tobytes()).hexdigest()))
            if any(digest(database / name) != value for name, value in graph.items()):
                raise RuntimeError("cache preparation changed a saved graph file")
            print(json.dumps(dict(sources=count, converted=len(paths), graphFilesUnchanged=True)), flush=True)

        edges = []
        for exponent in [-126, -64, -1, 0, 1, 64, 126]:
            value = np.float32(2.0 ** exponent)
            following = np.nextafter(value, np.float32(np.inf), dtype=np.float32)
            middle = (float(value) + float(following)) / 2
            for edge in [np.nextafter(middle, -np.inf), middle, np.nextafter(middle, np.inf)]:
                edges.extend([float(edge), -float(edge)])
        edges.extend([0.0, -0.0, 1e-45, -1e-45, 1e-40, -1e-40,
                      3.4028234663852886e38, -3.4028234663852886e38])
        pack(edges)
        packer.stdin.close()
        if packer.wait(timeout=3) != 0:
            raise RuntimeError(packer.stderr.read())
    finally:
        if packer.poll() is None:
            packer.kill()
            packer.wait()
    (root / "conversion.json").write_text(json.dumps(dict(
        originalFixtures=str(original), generationModelCalls=0, graphFilesUnchanged=True,
        nativeHelperSha256=digest(helper), preparationSha256=digest(Path(__file__)),
        vectors=records, decimalEdgeCases=len(edges), allFloat32BitsEqual=True), indent=2) + "\n")


if __name__ == "__main__":
    main()
