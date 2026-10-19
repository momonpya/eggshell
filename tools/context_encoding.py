"""Isolated numerical experiment: retain every tokenizer overflow segment.

Original DB windows, source bytes and equality rules are untouched. Each window
gets a bundle of vectors; retrieval compares all query/source vector pairs.
This module is not imported by the production provider.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


def positions(text, encodings):
    """Source character positions with an attended, non-special token offset.

    These are tokenizer offsets, not evidence that a model understood a fact.
    Whitespace and characters discarded by model normalization are separate.
    """
    result = set()
    for encoding in encodings:
        for span, special, attended in zip(encoding.offsets, encoding.special_tokens_mask,
                                           encoding.attention_mask):
            if not special and attended:
                start, stop = span
                if not 0 <= start <= stop <= len(text):
                    raise ValueError("Tokenizer offsets exceed the original source")
                result.update(range(start, stop))
    return result


class Planner:
    def __init__(self, tokenizer, overlap=16):
        from tokenizers import Tokenizer

        configured = tokenizer.truncation
        if configured is None:
            raise ValueError("The model must declare its context length")
        self.context = configured["max_length"]
        self.budget = self.context - tokenizer.num_special_tokens_to_add(False)
        if not 0 <= overlap < self.budget:
            raise ValueError("Overlap must leave room for new source tokens")
        self.overlap = overlap
        # Clone once per encoder, not once per window. No global assets change.
        self.complete = Tokenizer.from_str(tokenizer.to_str())
        self.complete.no_padding()
        self.complete.no_truncation()

    def plan(self, text):
        return _plan(self, text)


def _plan(planner, text):
    complete = planner.complete
    raw = complete.encode(text, add_special_tokens=False)
    reference = list(zip(raw.ids, raw.offsets, raw.special_tokens_mask))
    mapped = positions(text, [raw])
    source_tokens = len(raw.ids)
    # Split the complete encoding before adding model special tokens. The
    # installed tokenizer's encode(...).overflowing shortcut itself loses a
    # tail in some examples; token/offset equality below rejects that route.
    raw.truncate(planner.budget, stride=planner.overlap)
    raw_segments = [raw, *raw.overflowing]
    expected_segments = []
    offset = 0
    while True:
        expected_segments.append(reference[offset:offset+planner.budget])
        if offset+planner.budget >= len(reference):
            break
        offset += planner.budget-planner.overlap
    if [list(zip(part.ids, part.offsets, part.special_tokens_mask)) for part in raw_segments] != expected_segments:
        raise ValueError("Segment sequence differs from the complete source encoding")
    segments = [complete.post_process(part) for part in raw_segments]
    if any(len(part.ids) > planner.context for part in segments):
        raise ValueError("A segment exceeds the declared model context")
    # Token identity and offset are checked, not merely enclosing spans. No
    # substring decode/re-encode can silently drop boundary subword tokens.
    for segment, expected in zip(segments, expected_segments):
        present = [(i, o, s) for i, o, s in zip(segment.ids, segment.offsets,
                    segment.special_tokens_mask) if not s]
        if present != expected:
            raise ValueError("Postprocessing omits or invents original source tokens")
    embedded = positions(text, segments)
    visible = {i for i, char in enumerate(text) if not char.isspace()}
    return segments, dict(characters=len(text), visibleCharacters=len(visible),
        tokenizerMappedCharacters=len(mapped & visible),
        embeddedCharacters=len(embedded & visible), sourceTokens=source_tokens,
        segments=len(segments), contextTokens=planner.context,
        overlapTokens=planner.overlap, completeTokenOffsets=embedded == mapped)


def encode_groups(active, texts, planner=None):
    """Run the pinned FastEmbed ONNX/pooling kernel on overflow token IDs.

    Batches remain bounded to 32 segments. The model's own postprocessor is
    used; only token preparation expands from one segment to all segments.
    """
    import numpy as np
    from fastembed.common.onnx_model import OnnxOutputContext

    numerical = active.model
    if numerical.model is None or numerical.tokenizer is None:
        numerical.load_onnx_model()
    if planner is None:
        planner = Planner(numerical.tokenizer)
    planned = [planner.plan(text) for text in texts]
    segments = [(owner, part) for owner, (parts, _) in enumerate(planned) for part in parts]
    groups = [[] for _ in texts]
    names = {node.name for node in numerical.model.get_inputs()}
    padding = numerical.tokenizer.padding
    if padding is None:
        raise ValueError("The model must declare padding")
    for offset in range(0, len(segments), 32):
        batch = segments[offset:offset+32]
        width = max(len(part.ids) for _, part in batch)
        for _, part in batch:
            part.pad(width, direction=padding["direction"], pad_id=padding["pad_id"],
                     pad_type_id=padding["pad_type_id"], pad_token=padding["pad_token"])
        ids = np.asarray([part.ids for _, part in batch], dtype=np.int64)
        mask = np.asarray([part.attention_mask for _, part in batch], dtype=np.int64)
        feeds = {"input_ids": ids}
        if "attention_mask" in names:
            feeds["attention_mask"] = mask
        if "token_type_ids" in names:
            feeds["token_type_ids"] = np.zeros_like(ids)
        feeds = numerical._preprocess_onnx_input(feeds)
        output = numerical.model.run(numerical.ONNX_OUTPUT_NAMES, feeds)[0]
        context = OnnxOutputContext(model_output=output,
            attention_mask=feeds.get("attention_mask", mask), input_ids=feeds["input_ids"])
        vectors = list(numerical._post_process_onnx_output(context))
        if len(vectors) != len(batch):
            raise ValueError("Numerical segment count mismatch")
        for (owner, _), vector in zip(batch, vectors):
            vector = np.asarray(vector, dtype=np.float32)
            norm = np.linalg.norm(vector)
            normalized = vector if norm == 0 else vector / norm
            if not np.isfinite(normalized).all():
                raise ValueError("Nonfinite segment vector")
            groups[owner].append(normalized)
    return groups, [coverage for _, coverage in planned]


def contract(active, model_sha256, planner):
    """Content-derived cache identity proposal; no manually maintained version."""
    value = dict(model=active.model_name, modelSha256=model_sha256,
        tokenizerSha256=hashlib.sha256(active.model.tokenizer.to_str().encode()).hexdigest(),
        numericalClass=type(active.model).__name__, overlapTokens=planner.overlap,
        contextTokens=planner.context, sourceBudgetTokens=planner.budget,
        implementationSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    return dict(value, digest=hashlib.sha256(json.dumps(value, sort_keys=True,
                separators=(",", ":")).encode()).hexdigest())
