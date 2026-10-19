#!/usr/bin/env python3
"""Measure current tokenizer loss and an isolated complete-overflow candidate.

Controlled examples are diagnostics, never token-saving or quality adoption
evidence. No DB, provider, model asset or production executable is modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

from context_encoding import encode_groups, Planner, positions, contract

MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
CASES = {
    "japanese": "保存済みの記録から検索して元の本文を配送する。質問の意味を優先して照合する。" * 30,
    "korean": "저장된 기록에서 검색하여 원래 본문을 전달합니다. 질문의 의미를 우선하여 비교합니다. " * 30,
    "code": ("if packet.sequence_number >= expected_sequence:\n"
             "    connection.pending_frames.append(packet.payload_bytes)\n") * 20,
    "english": "Search the saved observations and deliver their original body before the deadline. " * 20,
    "cyrillic": "Поиск сохранённых записей возвращает исходный текст до истечения срока. " * 25,
}
LEXICAL = ["한국어 검색 기록", "Поиск сохранённых записей", "café résumé", "cafe\u0301 re\u0301sume\u0301",
           "ｶﾞｲﾄﾞ ﾃﾞｰﾀ", "ＡＢＣ１２３", "保存した本文を検索する", "Serializer.load_payload ./src/main.py"]


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024*1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def windows(text):
    return [(offset, text[offset:offset+512]) for offset in range(0, max(1, len(text)), 384)]


def run(args):
    import numpy as np
    from fastembed import TextEmbedding

    source = args.source.resolve()
    frozen = {name: sha(source / name) for name in ["runtime/embedding.py", "Eggshell/SearchProvider.lean",
        "Eggshell/SearchRank.lean", "Eggshell/LogicalText.lean", "Eggshell/GraphStore.lean", ".lake/build/bin/eggshell"]}
    assets = {str(p.relative_to(args.model_directory)): sha(p) for p in args.model_directory.rglob("*") if p.is_file()}
    write(args.output / "protocol.json", dict(cases=CASES, lexical=LEXICAL, windowsCharacters=512,
        strideCharacters=384, model=MODEL, overlapTokens=16, scoring="max of all original window/segment pairs",
        sourceHashes=frozen, assetHashes=assets, generationModelCalls=0, productionAdoption=False))
    started = time.perf_counter()
    active = TextEmbedding(model_name=MODEL, cache_dir=str(args.models), threads=4, local_files_only=True)
    initialize_ms = (time.perf_counter()-started)*1000
    tokenizer = active.model.tokenizer
    started = time.perf_counter()
    planner = Planner(tokenizer)
    planner_ms = (time.perf_counter()-started)*1000
    write(args.output / "contract.json", contract(active, sha(args.model_directory / "model_optimized.onnx"), planner))
    coverage = []
    all_texts = [text for case in CASES.values() for _, text in windows(case)]
    started = time.perf_counter()
    baseline = []
    for vector in active.embed(all_texts, batch_size=32):
        vector = np.asarray(vector, dtype=np.float32)
        norm = np.linalg.norm(vector)
        baseline.append(vector if norm == 0 else vector/norm)
    baseline_ms = (time.perf_counter()-started)*1000
    started = time.perf_counter()
    candidate, _ = encode_groups(active, all_texts, planner)
    candidate_ms = (time.perf_counter()-started)*1000
    pointer = 0
    for name, text in CASES.items():
        before, after = set(), set()
        rows = []
        for offset, part in windows(text):
            first = tokenizer.encode(part)
            segments, measured = planner.plan(part)
            before.update(offset+i for i in positions(part, [first]))
            after.update(offset+i for i in positions(part, segments))
            rows.append(dict(offset=offset, baselineEmbeddedCharacters=len(positions(part, [first])),
                candidate=measured, baselineTokens=sum(first.attention_mask),
                vectorCount=len(candidate[pointer])))
            pointer += 1
        visible = {i for i, char in enumerate(text) if not char.isspace()}
        coverage.append(dict(name=name, characters=len(text), visibleCharacters=len(visible),
            baselineEmbeddedCharacters=len(before & visible), candidateEmbeddedCharacters=len(after & visible),
            baselineCoverage=len(before & visible)/len(visible), candidateCoverage=len(after & visible)/len(visible),
            windows=rows))
    # Short inputs have one segment and retain the original numerical kernel.
    short = ["Where is the original saved body?", "保存した本文を検索する", "한국어 검색 기록", "", "é e\u0301 👨‍👩‍👧‍👦"]
    normal = []
    for vector in active.embed(short, batch_size=32):
        vector = np.asarray(vector, dtype=np.float32)
        norm = np.linalg.norm(vector)
        normal.append(vector if norm == 0 else vector/norm)
    expanded, _ = encode_groups(active, short, planner)
    short_equal = [len(group)==1 and np.array_equal(original, group[0]) for original, group in zip(normal, expanded)]
    if not all(short_equal):
        raise ValueError("Short-input numerical equivalence failed")
    # Queries use the same complete path; preserve every original source/window
    # and expose the complete score order instead of selecting a best example.
    queries = ["保存した本文はいつ配送されますか？", "How are pending packet payloads queued?", CASES["japanese"]]
    rankings = []
    for query in queries:
        q_windows = [part for _, part in windows(query)]
        q_base = []
        for vector in active.embed(q_windows, batch_size=32):
            vector = np.asarray(vector, dtype=np.float32)
            norm = np.linalg.norm(vector)
            q_base.append(vector if norm == 0 else vector/norm)
        q_groups, q_coverage = encode_groups(active, q_windows, planner)
        q_all = [v for group in q_groups for v in group]
        before, after, pointer = [], [], 0
        for name, text in CASES.items():
            count = len(windows(text))
            before.append((max(float(np.dot(q, v)) for q in q_base for v in baseline[pointer:pointer+count]), name))
            after.append((max(float(np.dot(q, v)) for q in q_all for group in candidate[pointer:pointer+count] for v in group), name))
            pointer += count
        rankings.append(dict(query=query, baseline=sorted(before, key=lambda row:-row[0]),
                             candidate=sorted(after, key=lambda row:-row[0]),
                             queryCoverage=q_coverage))
    write(args.output / "numerical.json", dict(coverage=coverage, rankings=rankings,
        timingsMs=dict(initialize=initialize_ms, planner=planner_ms,
            baselineEmbedding=baseline_ms, candidateEmbedding=candidate_ms),
        shortBitIdentical=short_equal, originalWindows=len(all_texts), candidateVectors=sum(map(len,candidate))))
    command = [str(args.terms_binary), *LEXICAL]
    completed = subprocess.run(command, cwd=source, text=True, capture_output=True, timeout=60)
    (args.output / "lexical.stderr").write_text(completed.stderr)
    (args.output / "lexical.stdout").write_text(completed.stdout)
    completed.check_returncode()
    lexical = [json.loads(line) for line in completed.stdout.splitlines()]
    if {str(p.relative_to(args.model_directory)): sha(p) for p in args.model_directory.rglob("*") if p.is_file()} != assets:
        raise ValueError("Audit changed model assets")
    if any(sha(source/name) != value for name, value in frozen.items()):
        raise ValueError("Audit changed production files")
    result = dict(coverage=coverage, lexical=lexical, rankings=rankings,
        timingsMs=dict(initialize=initialize_ms, planner=planner_ms,
            baselineEmbedding=baseline_ms, candidateEmbedding=candidate_ms),
        originalWindows=len(all_texts), candidateVectors=sum(map(len, candidate)), shortBitIdentical=short_equal,
        productionFilesUnchanged=True, modelAssetsUnchanged=True, generationModelCalls=0,
        productionAdoption=False, candidateIntegration=False)
    write(args.output / "result.json", result)
    print(json.dumps(dict(coverage=[{k:v for k,v in row.items() if k!="windows"} for row in coverage],
        originalWindows=len(all_texts), candidateVectors=sum(map(len,candidate)), shortBitIdentical=short_equal)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["source", "models", "model-directory", "output", "terms-binary"]:
        parser.add_argument("--"+name, required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    try:
        run(args)
    except Exception as error:
        write(args.output / "failure.json", dict(error=f"{type(error).__name__}: {error}", productionAdoption=False))
        raise


if __name__ == "__main__":
    main()
