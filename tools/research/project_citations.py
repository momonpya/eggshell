"""Project actual native nomination/citation inputs into stored scalar ranges.

Inputs are a diagnostic receipt and its source-document inventory. No oracle,
expected answer, source file, or URL is read. Unsupported mappings remain gaps.
This prepares planner inputs; it does not choose or deliver a packet.
"""
from dataclasses import asdict
import argparse
import hashlib
import json
from pathlib import Path
import re

from citation_bridge import decode_layout, locate, numbered_reads, parse_citations, safe_relative


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project(audit, documents):
    inputs = [r['data'] for r in audit if r['kind'] == 'EGGSHELL_CITATION_INPUT']
    selections = [r['data'] for r in audit if r['kind'] == 'EGGSHELL_RANGE_SELECTION']
    if len(inputs) != 1 or len(selections) != 1:
        raise ValueError('expected one actual input and one actual selector domain')
    context, problem = inputs[0], selections[0]
    docs = {d['owner']: d for d in documents}
    if len(docs) != len(documents):
        raise ValueError('duplicate source-document owner')
    families = {f['owner']: (i, f) for i, f in enumerate(problem['families'])}
    # Keep producer/position data associated with the exact unit preparation.
    # Richer context may intersect a citation without its search cue doing so;
    # such context must not acquire a new relevance hint by accident.
    demands = {}
    for record in audit:
        if record['kind'] == 'EGGSHELL_RANGE_UNIT':
            data = record['data']
            key = (data['owner'], tuple(map(tuple, data['ranges'])))
            demands.setdefault(key, []).append(data)
    observations, issues = {}, []
    for observation in context['observations']:
        owner = observation['owner']
        if owner not in families:
            issues.append(dict(owner=owner, reason='not-in-offered-domain'))
            continue
        family, descriptor = families[owner]
        doc = docs[owner]
        raw = observation['source']
        text, _ = decode_layout(raw)
        if (text != doc['evidence'] or len(doc['work']) != descriptor['workChars'] or
                hashlib.sha256(raw.encode()).hexdigest() != descriptor['sourceSha256']):
            raise ValueError('native source disagrees with immutable inventory')
        file_sets = {}
        for record in observation['records']:
            if not record['complete'] or record['uris']:
                continue
            for file in record['files']:
                content = file['content']
                if (safe_relative(file['relative']) and content is not None and content['bytes'] >= 0 and
                        re.fullmatch('[0-9a-f]{64}', content['root'])):
                    file_sets.setdefault(file['relative'], set()).add((content['root'], content['bytes']))
        # Conflicting fingerprints stay ambiguous. No path-only identity is made.
        files = {relative: next(iter(values)) for relative, values in file_sets.items() if len(values) == 1}
        reads, unsupported = numbered_reads(doc['work'], files)
        if unsupported:
            issues.append(dict(owner=owner, reason=unsupported))
        observations[owner] = dict(native=observation, family=family, files=files, reads=reads)
    adjacency = {}
    for edge in context['all']:
        adjacency.setdefault(edge['parent'], set()).update(edge['children'])

    def reached(start):
        visited, pending = set(), [start]
        while pending:
            work = pending.pop()
            if work in visited:
                continue
            visited.add(work)
            pending.extend(adjacency.get(work, ()))
        return visited

    projected, citations, parents = [], [], []
    for parent in context['parents']:
        route = reached(parent['work'])
        available = [o for o in observations.values() if o['native']['work'] in route]
        paths = sorted({p for o in available for p in o['files']})
        found, rejected = parse_citations(parent['owner'], parent['rank'], parent['text'], paths)
        parents.append(dict(owner=parent['owner'],priority=parent['rank'],reachableObservations=len(available),citations=len(found)))
        issues.extend(dict(parent=parent['owner'],ordinal=i,reason=reason) for i,reason in rejected)
        citations.extend(asdict(c) for c in found)
        for observation in available:
            native = observation['native']
            for match in locate(native['source'], observation['reads'], found):
                citation = match.citation
                ranges = [(a,b) for _,a,b in match.rows]
                def covers(unit):
                    return all(any(c<=a and b<=d for c,d in unit['ranges']) for a,b in ranges)
                complete_offers = [i for i,u in enumerate(problem['units'])
                                   if u['family']==observation['family'] and covers(u)]
                hint_offers = []
                for index, unit in enumerate(problem['units']):
                    if unit['family'] != observation['family']:
                        continue
                    key = (native['owner'], tuple(map(tuple, unit['ranges'])))
                    positions = {}
                    for demand in demands.get(key, ()):
                        rows = [(line,a,b) for line,a,b in match.rows
                                if any(c<=a and b<=d for c,d in unit['ranges']) and
                                   any(c<b and a<d for c,d in demand['requested'])]
                        if rows:
                            positions.setdefault(demand['position'], set()).update(rows)
                    if positions:
                        descriptor = problem['families'][observation['family']]
                        hint_offers.append(dict(unit=index,positions=[dict(position=position,
                            rows=sorted(rows),
                            queryChannelPriority=(descriptor['windows'].index(position)
                                                  if position in descriptor['windows'] else None),
                            priorReferencePriority=(descriptor['references'].index(position)
                                                    if position in descriptor['references'] else None))
                            for position, rows in sorted(positions.items())]))
                fingerprint = observation['files'][citation.relative]
                projected.append(dict(citation=asdict(citation),owner=native['owner'],
                    family=observation['family'],fingerprint=dict(root=fingerprint[0],bytes=fingerprint[1]),
                    rows=match.rows,complete=match.complete,completeOffers=complete_offers,
                    hintOffers=hint_offers))
    return dict(questionSha256=hashlib.sha256(context['question'].encode()).hexdigest(),
                questionCharacters=len(context['question']),parents=parents,citations=citations,
                projected=projected,issues=issues,authority='Advisory only; no file freshness, shell completion, Work equality, or answer sufficiency is inferred.',
                unnumberedOffsetsGuessed=False,readsReferencedFiles=False,oracleRead=False,
                runtimeSelectionChanged=False,plannerInputOnly=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--documents', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('preserve the existing output; select a fresh path')
    before = [digest(args.audit), digest(args.documents)]
    result = project(json.loads(args.audit.read_text()), json.loads(args.documents.read_text()))
    if before != [digest(args.audit), digest(args.documents)]:
        raise ValueError('immutable input changed during projection')
    result.update(auditSha256=before[0],documentsSha256=before[1],scriptSha256=digest(Path(__file__)),
                  bridgeSha256=digest(Path(__file__).with_name('citation_bridge.py')))
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(parents=len(result['parents']),citations=len(result['citations']),
        projected=len(result['projected']),complete=sum(p['complete'] for p in result['projected']),issues=len(result['issues']))))


if __name__ == '__main__':
    main()
