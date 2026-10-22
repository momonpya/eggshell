"""Deterministic advisory associations; no Work equality or completion authority.

Derivation stores observed argument/output witnesses, coquotation stores an
incidence hypergraph, and usage stores distinct events rather than counters.
"""
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
import hashlib
import json
import re


def key(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


@dataclass(frozen=True, order=True)
class SourceRange:
    relative: str
    fingerprint: str
    source_bytes: int
    first: int
    last: int

    def __post_init__(self):
        if (not self.relative or self.relative.startswith('/') or '\0' in self.relative or
                any(p in ('', '.', '..') for p in self.relative.split('/')) or
                not re.fullmatch('[0-9a-f]{64}', self.fingerprint) or
                self.source_bytes < 0 or not 0 < self.first <= self.last):
            raise ValueError('A source range needs a safe path, recorded fingerprint and positive interval')

    @property
    def identity(self):
        return key(asdict(self))

    @property
    def file(self):
        return self.relative, self.fingerprint, self.source_bytes


def covered(wanted, ranges):
    """Union finite closed intervals, never enumerate citation-controlled lines."""
    at = wanted.first
    for row in sorted((r for r in ranges if r.file == wanted.file), key=lambda r:r.first):
        if row.first > at:
            break
        if row.last >= at:
            at = row.last + 1
            if at > wanted.last:
                return True
    return False


class Synapses:
    def __init__(self):
        self.ranges = {}
        self.bindings = defaultdict(set)
        self.consumed = {}              # witness ID -> producer/consumer/witness
        self.predecessors = defaultdict(set)
        self.supports = defaultdict(set) # claim -> source range IDs
        self.support_witnesses = {}
        self.claim_readers = defaultdict(set)
        self.read_by = defaultdict(set)  # occurrence -> source range IDs
        self.coquoted = defaultdict(set)# answer -> range IDs; no pairwise clique
        self.coquoted_by = defaultdict(set)
        self.coquote_kind = {}
        self.usage = {}                 # event ID -> query/range/observed label
        self.usage_by = defaultdict(set)

    def add_range(self, source, binding=None):
        identity = source.identity
        if identity in self.ranges and self.ranges[identity] != source:
            raise ValueError('Conflicting source range digest; never merge on hash alone')
        self.ranges[identity] = source
        if binding is not None:
            self.bindings[identity].add(json.dumps(binding, ensure_ascii=False, sort_keys=True))
        return identity

    def consume(self, producer, consumer, witness):
        if producer == consumer:
            raise ValueError('An occurrence cannot consume its own future output')
        if witness['producerFinish'] >= witness['consumerStart']:
            raise ValueError('Producer output was unavailable at consumer start')
        identity = key([producer, consumer, witness])
        row = dict(producer=producer, consumer=consumer, witness=witness)
        if identity in self.consumed and self.consumed[identity] != row:
            raise ValueError('Conflicting derivation witness digest')
        self.consumed[identity] = row
        self.predecessors[consumer].add(producer)
        return identity

    def support(self, source, claim, witness, occurrence=None):
        identity = self.add_range(source, witness.get('binding'))
        self.supports[claim].add(identity)
        self.support_witnesses[key([identity, claim, witness])] = dict(
            source=identity, claim=claim, witness=witness)
        if occurrence is not None:
            self.bind_support_reader(claim, identity, occurrence)
        return identity

    def bind_support_reader(self, claim, source, occurrence):
        if source not in self.supports[claim]:
            raise ValueError('Reader binding needs an existing support range')
        self.read_by[occurrence].add(source)
        self.claim_readers[claim].add(occurrence)

    def quote_together(self, answer, sources, scope='answer'):
        if scope not in ('answer', 'claim'):
            raise ValueError('Unknown coquotation scope')
        if answer in self.coquote_kind and self.coquote_kind[answer] != scope:
            raise ValueError('Coquotation group changed its scope')
        self.coquote_kind[answer] = scope
        for source in sources:
            identity = self.add_range(source)
            self.coquoted[answer].add(identity)
            self.coquoted_by[identity].add(answer)

    def record_read(self, event, query, requested, stored, delivered, fingerprint_checked):
        if not re.fullmatch('[0-9a-f]{64}', query):
            raise ValueError('Use an opaque question key; never store a plaintext query here')
        if not fingerprint_checked:
            label = 'reread'
        elif covered(requested, stored):
            label = 'reread' if covered(requested, delivered) else 'omitted_then_read'
        elif any(r.relative == requested.relative and r.file != requested.file for r in stored):
            label = 'source_changed'
        else:
            label = 'reread'
        identity = self.add_range(requested)
        self._use(event, query, identity, label)
        return label

    def record_citation(self, event, query, cited, delivered):
        if not re.fullmatch('[0-9a-f]{64}', query):
            raise ValueError('Use an opaque question key')
        if covered(cited, delivered):
            identity = self.add_range(cited)
            self._use(event, query, identity, 'delivered_then_cited')
            return True
        return False

    def _use(self, event, query, identity, label):
        row = dict(query=query, source=identity, label=label)
        if event in self.usage and self.usage[event] != row:
            raise ValueError('A replayed usage event changed its source or label')
        self.usage[event] = row
        self.usage_by[query].add(event)

    def backward(self, claims, occurrences=()):
        ranges = set().union(*(self.supports[c] for c in claims)) if claims else set()
        readers = set(occurrences).union(*(self.claim_readers[c] for c in claims))
        pending, seen = deque(sorted(readers)), set()
        while pending:
            occurrence = pending.popleft()
            if occurrence in seen:
                continue
            seen.add(occurrence)
            ranges.update(self.read_by[occurrence])
            pending.extend(sorted(self.predecessors[occurrence] - seen))
        return dict(ranges=sorted(ranges), occurrences=sorted(seen))

    def companions(self, sources, scope='answer'):
        groups = set().union(*(self.coquoted_by[s] for s in sources)) if sources else set()
        answers = {a for a in groups if self.coquote_kind[a] == scope}
        return {r:len(self.coquoted_by[r] & answers)
                for answer in answers for r in self.coquoted[answer]}

    def usage_counts(self, query):
        result = defaultdict(lambda:defaultdict(int))
        for event in self.usage_by[query]:
            row = self.usage[event]
            result[row['source']][row['label']] += 1
        return {source:dict(counts) for source, counts in sorted(result.items())}

    def export(self):
        return dict(ranges={k:asdict(v) for k,v in sorted(self.ranges.items())},
            bindings={k:[json.loads(v) for v in sorted(vs)] for k,vs in sorted(self.bindings.items())},
            consumed={k:v for k,v in sorted(self.consumed.items())},
            supports={k:sorted(v) for k,v in sorted(self.supports.items())},
            supportWitnesses={k:v for k,v in sorted(self.support_witnesses.items())},
            readBy={k:sorted(v) for k,v in sorted(self.read_by.items())},
            claimReaders={k:sorted(v) for k,v in sorted(self.claim_readers.items())},
            coquoted={k:sorted(v) for k,v in sorted(self.coquoted.items())},
            coquoteKinds=dict(sorted(self.coquote_kind.items())),
            usage={k:v for k,v in sorted(self.usage.items())},
            authority='advisory-only; no Union, Match, current freshness or completion assertion')


# Path-qualified terms and identifiers are kept distinct. Broad identifiers
# remain explicit heuristic witnesses; they are not presented as causal proof.
TOKEN = re.compile(r'(?:[\w.+-]+/)+[\w.+-]+(?::[1-9]\d*)?|[^\W\d]\w*', re.UNICODE)


def terms(text):
    seen = set()
    for match in TOKEN.finditer(text):
        token = match.group()
        kind = 'path-line' if re.search(r':[1-9]\d*$', token) else 'path' if '/' in token else 'identifier'
        for value, category in [(token,kind), *(([(token.rsplit(':',1)[0],'path')]) if kind == 'path-line' else [])]:
            if (category,value) not in seen:
                seen.add((category,value))
                yield (category,value), (match.start(),match.end())


def consume_trace(graph, events):
    """An inverted output index joined at actual call start, not completion order.

    events: phase(start/finish), occurrence, ordinal, text. A missing terminal
    event never becomes an indexed output. Duplicate notifications are idempotent.
    """
    outputs = defaultdict(dict)
    starts, finished, issues = {}, {}, []
    for event in events:
        identity, ordinal = event['occurrence'], event['ordinal']
        if event['phase'] == 'start':
            if identity in starts:
                if starts[identity]['text'] != event['text']:
                    raise ValueError('One occurrence has conflicting argument payloads')
                continue
            pending = []
            for term, input_span in terms(event['text']):
                for producer, (finish, output_span) in outputs.get(term, {}).items():
                    pending.append((producer,dict(kind=term[0],term=term[1],
                        inputSpan=input_span,outputSpan=output_span,
                        producerFinish=finish,consumerStart=ordinal)))
            starts[identity] = dict(text=event['text'],pending=pending)
        elif event['phase'] == 'finish':
            if identity in finished:
                if finished[identity] != event['text']:
                    raise ValueError('One occurrence has conflicting terminal output')
                continue
            if identity not in starts:
                issues.append(dict(occurrence=identity,reason='no-observed-start'))
                continue
            finished[identity] = event['text']
            for producer,witness in starts[identity]['pending']:
                graph.consume(producer,identity,witness)
            for term,span in terms(event['text']):
                outputs[term][identity] = ordinal,span
        else:
            raise ValueError('Unknown trace phase')
    return dict(started=len(starts),finished=len(finished),
                unfinished=sorted(set(starts)-set(finished)),issues=issues)


def observed_gaps(requested, stored, delivered):
    """Stored portions actually reread but not presented, using interval algebra."""
    intersections=[]
    for old in stored:
        if old.file != requested.file:continue
        first,last=max(old.first,requested.first),min(old.last,requested.last)
        if first<=last:intersections.append((first,last))
    merged=[]
    for first,last in sorted(intersections):
        if merged and first<=merged[-1][1]+1:merged[-1]=(merged[-1][0],max(last,merged[-1][1]))
        else:merged.append((first,last))
    presented=sorted((r.first,r.last) for r in delivered if r.file==requested.file)
    result=[]
    for first,last in merged:
        remaining=[(first,last)]
        for a,b in presented:
            pieces=[]
            for c,d in remaining:
                if b<c or d<a:pieces.append((c,d))
                else:
                    if c<a:pieces.append((c,a-1))
                    if b<d:pieces.append((b+1,d))
            remaining=pieces
        result.extend(SourceRange(requested.relative,requested.fingerprint,requested.source_bytes,a,b) for a,b in remaining)
    return result
