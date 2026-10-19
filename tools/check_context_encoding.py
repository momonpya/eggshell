#!/usr/bin/env python3
"""Counterfactual tokenizer-boundary checks using the installed model assets."""
import argparse
import json
from pathlib import Path

from context_encoding import Planner, positions


def main():
    from fastembed.common.preprocessor_utils import load_tokenizer
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-directory', required=True, type=Path)
    args = parser.parse_args()
    tokenizer, _ = load_tokenizer(args.model_directory)
    original = tokenizer.to_str()
    planner = Planner(tokenizer)
    controls = []
    for text in ['保存した本文を検索する。'*40, '한국어 검색 기록을 전달합니다. '*40,
                 'if packet.sequence_number >= expected_sequence:\n'*20]:
        parts, coverage = planner.plan(text)
        baseline = positions(text, [tokenizer.encode(text)])
        after = positions(text, parts)
        if not baseline < after or not coverage['completeTokenOffsets']:
            raise ValueError('A known omitted suffix was not restored')
        controls.append(dict(kind='truncated-source-and-question', characters=len(text), segments=len(parts)))
    # Unknown characters, combining sequences, controls and whitespace must not
    # be confused with context truncation. Offsets remain original characters.
    for text in ['', ' \n\t', '\x00e\u0301👨\u200d👩\u200d👧\u200d👦', '<s> <pad> </s>', 'a'*512]:
        _, coverage = planner.plan(text)
        if not coverage['completeTokenOffsets']:
            raise ValueError('An edge input lost token offsets')
        controls.append(dict(kind='offset-boundary', characters=len(text)))
    for overlap in [-1, 126, 1000]:
        try:
            Planner(tokenizer, overlap)
        except ValueError:
            controls.append(dict(kind='invalid-overlap', overlap=overlap))
        else:
            raise ValueError('Invalid overlap was admitted')
    if tokenizer.to_str() != original:
        raise ValueError('The production tokenizer was mutated')
    print(json.dumps(dict(passed=True, controls=controls, originalTokenizerUnchanged=True)))


if __name__ == '__main__':
    main()
