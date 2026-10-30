"""Numerical boundary only. No retrieval, selection, storage or authority rules.

Token IDs are partitioned without truncation. Lean owns candidates, questions,
ranking and assessment. This uses the already installed ONNX/tokenizer runtime.
"""
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

model_root, input_path, output_path = map(Path, sys.argv[1:])
raw = input_path.read_bytes()
request = json.loads(raw)
started = time.monotonic()
tokenizer = Tokenizer.from_file(str(model_root / "tokenizer.json"))
tokenizer.no_truncation()
tokenizer.no_padding()
options = ort.SessionOptions()
options.intra_op_num_threads = 1
options.inter_op_num_threads = 1
session = ort.InferenceSession(str(model_root / "model.onnx"), options,
                              providers=["CPUExecutionProvider"])
initialized_ms = (time.monotonic() - started) * 1000
names = {entry.name for entry in session.get_inputs()}
cls, sep, pad = (tokenizer.token_to_id(name) for name in ("[CLS]", "[SEP]", "[PAD]"))
if any(value is None for value in (cls, sep, pad)):
    raise ValueError("Unexpected token contract")
source_ids = [tokenizer.encode(text, add_special_tokens=False).ids for text in request["texts"]]
topics = []
for question in request["questions"]:
    began = time.monotonic()
    query = tokenizer.encode(question["query"], add_special_tokens=False).ids
    budget = 512 - len(query) - 3
    if budget <= 16:
        raise ValueError("Query leaves no complete source-token segment")
    pending, owners, bounds = [], [], []
    for owner, tokens in enumerate(source_ids):
        if not tokens:
            raise ValueError("Empty tokenized source unit")
        if len(tokens) <= budget:
            reference = tokenizer.encode(question["query"], request["texts"][owner])
            if reference.ids != [cls] + query + [sep] + tokens + [sep]:
                raise ValueError("Paired token encoding differs from the model tokenizer")
        first = 0
        while first < len(tokens):
            last = min(first + budget, len(tokens))
            pending.append([cls] + query + [sep] + tokens[first:last] + [sep])
            owners.append(owner)
            bounds.append((owner, first, last, len(tokens)))
            if last == len(tokens):
                break
            first = last - 16
    scores = [None] * len(source_ids)
    inference_ms = 0
    for first in range(0, len(pending), 16):
        batch = pending[first:first + 16]
        width = max(map(len, batch))
        ids = np.full((len(batch), width), pad, dtype=np.int64)
        mask = np.zeros_like(ids)
        segments = np.zeros_like(ids)
        for index, tokens in enumerate(batch):
            ids[index, :len(tokens)] = tokens
            mask[index, :len(tokens)] = 1
            segments[index, len(query) + 2:len(tokens)] = 1
        feeds = {"input_ids": ids, "attention_mask": mask, "token_type_ids": segments}
        mark = time.monotonic()
        logits = session.run(None, {name: value for name, value in feeds.items() if name in names})[0].reshape(-1)
        inference_ms += (time.monotonic() - mark) * 1000
        if len(logits) != len(batch) or not np.isfinite(logits).all():
            raise ValueError("Invalid logits")
        for offset, score in enumerate(logits):
            owner = owners[first + offset]
            scores[owner] = float(score) if scores[owner] is None else max(scores[owner], float(score))
    topics.append(dict(topic=question["topic"], scores=scores,
                       queryTokens=len(query), sourceTokens=sum(map(len, source_ids)),
                       segments=len(pending), segmentBounds=bounds,
                       elapsedMs=(time.monotonic() - began) * 1000, inferenceMs=inference_ms))
result = dict(inputSha256=hashlib.sha256(raw).hexdigest(), initializedMs=initialized_ms,
              modelFiles={name: hashlib.sha256((model_root / name).read_bytes()).hexdigest()
                          for name in ("model.onnx", "tokenizer.json")},
              topics=topics, elapsedMs=(time.monotonic() - started) * 1000)
output_path.write_text(json.dumps(result, allow_nan=False, separators=(",", ":")))
