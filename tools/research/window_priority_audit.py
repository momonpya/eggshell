#!/usr/bin/env python3
"""Join a private native selection diagnostic to its actual numerical scores.

This reads expected excerpts only after the frozen runtime has executed. No
answer model, source-file read, encoder call or alternative selector is used.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from memory_guard import require_guard, code_sha


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def merge(ranges):
    result = []
    for first, last in sorted(ranges):
        if result and first <= result[-1][1]:
            result[-1][1] = max(last, result[-1][1])
        else:
            result.append([first, last])
    return result


def covers(ranges, first, last):
    return any(a <= first and last <= b for a, b in merge(ranges))


def replay(p):
    """Independent integer replay, checked against actual native choices."""
    nodes = [set(o['closure']) for o in p['offers']]
    cues = [set(o['covers']) for o in p['offers']]
    weights = [c['weight'] for c in p['pieces']]
    selected, seen_nodes, seen_cues = [], set(), set()
    cost, benefit = tuple(p['fixed']), 0
    while True:
        best = None
        for i, (closure, value) in enumerate(zip(nodes, cues)):
            if i in selected:
                continue
            fresh = closure - seen_nodes
            delta = tuple(sum(p['nodeCosts'][n][k] for n in fresh) for k in [0, 1])
            after = tuple(cost[k] + delta[k] for k in [0, 1])
            if any(after[k] > p['limit'][k] for k in [0, 1]):
                continue
            gain = sum(weights[c] for c in value - seen_cues)
            if gain <= 0:
                continue
            charge = max(delta[0] * p['limit'][1], delta[1] * p['limit'][0])
            if best is None or (charge == 0 and (best[2] != 0 or best[1] < gain)) or (
                    charge != 0 and best[2] != 0 and best[1] * charge < gain * best[2]):
                best = i, gain, charge, fresh, after
        if best is None:
            break
        i, gain, _, fresh, cost = best
        selected.append(i)
        seen_nodes |= fresh
        seen_cues |= cues[i]
        benefit += gain
    for i, closure in enumerate(nodes):
        single_cost = tuple(p['fixed'][k] + sum(p['nodeCosts'][n][k] for n in closure)
                            for k in [0, 1])
        value = sum(weights[c] for c in cues[i])
        if all(single_cost[k] <= p['limit'][k] for k in [0, 1]) and benefit < value:
            selected, cost, benefit = [i], single_cost, value
    assert selected == p['chosen'] and list(cost) == p['modeledCost'] and benefit == p['benefit']


def decoded(raw):
    if not raw.startswith('"'):
        return raw, list(range(len(raw) + 1))
    chars, offsets, i = [], [], 1
    while i < len(raw) - 1:
        first = i
        if raw[i] == '\\':
            end = i + (6 if raw[i + 1] == 'u' else 2)
            if raw[i + 1] == 'u' and 0xd800 <= int(raw[i + 2:i + 6], 16) <= 0xdbff and raw[end:end + 2] == '\\u':
                end += 6
            char = json.loads('"' + raw[i:end] + '"')
        else:
            char, end = raw[i], i + 1
        assert len(char) == 1
        chars.append(char)
        offsets.append(first)
        i = end
    text = ''.join(chars)
    assert text == json.loads(raw)
    return text, offsets + [len(raw) - 1]


def excerpt_ranges(raw, excerpt):
    text, offsets = decoded(raw)
    lines, at = [], 0
    for line in text.splitlines(keepends=True):
        match = re.match(r'^\s*(\d+)[\t :]+(.*?)(?:\r?\n)?$', line)
        body = match[2] if match else line.rstrip('\r\n')
        left = at + (match.start(2) if match else 0)
        lines.append((body.strip(), left + len(body) - len(body.lstrip()), left + len(body.rstrip())))
        at += len(line)
    wanted = [line.strip() for line in excerpt.splitlines()]
    found = [[(offsets[a], offsets[b]) for _, a, b in lines[i:i + len(wanted)] if a < b]
             for i in range(len(lines) - len(wanted) + 1)
             if [r[0] for r in lines[i:i + len(wanted)]] == wanted]
    assert len(found) == 1, 'Missing or ambiguous original excerpt'
    return found[0]


def window_keys(record):
    prefix = len(record['work']) + 1
    text = record['work'] + '\n' + record['source']
    return tuple(hashlib.sha256(text[i:i + 512][max(0, prefix - i):].encode()).hexdigest()
                 for i in range(0, max(1, len(text)), 384))


def audit(args):
    require_guard(dict(memoryGuardSha256=code_sha()))
    verified = read(args.root / 'run-logged/result.json')
    records_path = args.root / 'source-records.json'
    records = read(records_path)['records']
    by_owner = {r['owner']: r for r in records}
    by_keys = defaultdict(list)
    for record in records:
        by_keys[window_keys(record)].append(record)
    requirements = read(args.reference / 'native-question-requirements.json')
    native = {r['stage']: r['sessions'][0]['missingRequired']
              for r in read(args.reference / 'native-result.json')['rows']}
    rows = []
    for qualification in verified['rows']:
        stage = qualification['stage']
        path = Path(qualification['audit'])
        assert qualification['sameBody'] and sha(path) == qualification['auditSha256']
        assert sha(args.root / f'run-logged/stage{stage}/body.txt') == qualification['referenceSha256']
        events = read(path)
        domains = [e['data'] for e in events if e['kind'] == 'EGGSHELL_WINDOW_DOMAIN' and e['data']['purpose'] == 'focus']
        assert len(domains) == 1
        domain = domains[0]['documents']
        selections = [e['data'] for e in events if e['kind'] == 'EGGSHELL_RANGE_SELECTION']
        assert len(selections) == 1
        p = selections[0]
        replay(p)
        admitted = {f['owner'] for f in p['families']}
        mapped = []
        for document in domain:
            # Body-only numerical views can intentionally alias (for example,
            # distinct operations whose observed result is the same string).
            # A view match is neither Work identity nor completion authority.
            found = [r for r in by_keys[tuple(document['windows'])] if r['owner'] in admitted]
            assert found, ('No original numerical view', document['id'])
            mapped.append(found)
        batches = [e['data'] for e in events if e['kind'] == 'EGGSHELL_WINDOW_SCORES' and e['data']['purpose'] == 'focus']
        assert len({b['queryVectorSha256'] for b in batches}) == 1
        scores = {}
        for batch in batches:
            for item in batch['scores']:
                key = item['document'], item['position']
                assert key not in scores and 0 <= key[0] < len(domain)
                assert 0 <= key[1] < len(domain[key[0]]['windows'])
                scores[key] = float(item['score'])
        expected = {(i, j) for i, d in enumerate(domain) for j in range(len(d['windows']))}
        assert set(scores) == expected, 'Incomplete numerical domain'
        ordered = sorted(scores, key=lambda key: (-scores[key], key))
        global_ranks, numeric = defaultdict(list), defaultdict(list)
        for rank, (i, position) in enumerate(ordered):
            for record in mapped[i]:
                key = record['owner'], position
                global_ranks[key].append(rank)
                numeric[key].append(scores[i, position])
        blocks = []
        for block in requirements['rows'][stage - 1]['blocks']:
            owners = []
            for family, f in enumerate(p['families']):
                if f['owner'] not in block['originalOwners']:
                    continue
                record = by_owner[f['owner']]
                assert hashlib.sha256(record['source'].encode()).hexdigest() == f['sourceSha256']
                required = excerpt_ranges(record['source'], block['originalExcerpt'])
                complete = [i for i, unit in enumerate(p['units']) if unit['family'] == family and
                            all(covers(unit['ranges'], a, b) for a, b in required)]
                selected = [span for i in p['chosen'] if p['units'][i]['family'] == family
                            for span in p['units'][i]['ranges']]
                offered_pieces = {c for offer in p['offers'] for c in offer['covers']}
                valued = [[c['first'], c['last']] for i, c in enumerate(p['pieces'])
                          if c['family'] == family and i in offered_pieces]
                priorities = dict(f['referenceRanks'])
                cue_rows = []
                for position in sorted(set(f['windows'] + f['references'])):
                    first = max(0, position * 384 - len(record['work']) - 1)
                    last = min(len(record['source']), max(0, position * 384 + 512 - len(record['work']) - 1))
                    if not any(max(first, a) < min(last, b) for a, b in required):
                        continue
                    key = f['owner'], position
                    ranks = global_ranks.get(key, [])
                    values = numeric.get(key, [])
                    cue_rows.append(dict(position=position, range=[first, last],
                        focusedPriority=f['windows'].index(position) if position in f['windows'] else None,
                        referencePriority=priorities.get(position), globalNumericalRank=ranks[0] if len(ranks) == 1 else None,
                        globalNumericalRankBounds=[min(ranks), max(ranks)] if ranks else None,
                        numericalScore=values[0] if len(set(values)) == 1 else None,
                        numericalScoreRange=[min(values), max(values)] if values else None,
                        coversAllRequiredLines=all(first <= a and b <= last for a, b in required)))
                owners.append(dict(owner=f['owner'], family=family, requiredRanges=required,
                    completeOffers=complete, selectedCompleteOffers=[i for i in complete if i in p['chosen']],
                    delivered=all(covers(selected, a, b) for a, b in required),
                    allRequiredCodeHasOfferedValue=all(covers(valued, a, b) for a, b in required),
                    minimumCompleteCost=min((sum(p['nodeCosts'][n][0] for n in set(p['offers'][i]['closure'])) for i in complete), default=None),
                    intersectingCues=cue_rows))
            blocks.append(dict(name=block['name'], delivered=any(o['delivered'] for o in owners), owners=owners))
        row = dict(stage=stage, originalBodyPreserved=True, nativeSelectionExactlyReplayed=True,
            focusDocuments=len(domain), focusScoredWindows=len(scores), completeScoreDomainVerified=True,
            ambiguousNumericalViews=[dict(document=domain[i]['id'], possibleOwners=[r['owner'] for r in found])
                                     for i, found in enumerate(mapped) if len(found) > 1],
            audit=str(path), auditSha256=sha(path), querySha256=domains[0]['querySha256'],
            blocks=blocks, missingRequired=[b['name'] for b in blocks if not b['delivered']])
        assert row['missingRequired'] == native[stage], 'Range audit disagrees with actual body acceptance'
        rows.append(row)
        print(json.dumps(dict(stage=stage, windows=len(scores), missing=row['missingRequired'])), flush=True)
    return dict(rows=rows, sourceRecordsSha256=sha(records_path), requirementsSha256=sha(args.reference / 'native-question-requirements.json'),
        scope='Current frozen candidate, actual scores and exact original coordinates; offline diagnostics only.',
        alternativeSelectorExecuted=False, answeringModelCalls=0, newSourceEncoding=False,
        productionAdoption=False, scriptSha256=sha(Path(__file__)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), 'Preserve prior diagnostic results'
    result = audit(args)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
