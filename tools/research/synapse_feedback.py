"""Replay actual delivered bytes and later observed reads into private usage edges.

A missing label needs a same-fingerprint recorded range, an actual completed
read and verified earlier presentation coordinates. Unknown parsing stays unknown.
No expected answer or benchmark fact list is an input.
"""
from collections import Counter, defaultdict
import argparse
import json
from pathlib import Path
import re
from build_synapses import command, file_map, load_export, numbered_lines, read_rpc, sha
from citation_bridge import Citation, decode_layout, locate, numbered_reads, parse_citations
from synapse_graph import Synapses, SourceRange, key, observed_gaps

CAPTION=re.compile(r'(?m)^  (?:ORIGINAL )?CHARS \[([0-9]+),([0-9]+)\)( decoded)?\n(  DECODED JSON STRING DATA\n)?')


def original_rows(document):
    files=file_map(document['records'])
    reads,reason=numbered_reads(document['work'] or '',files)
    if document['source'] is None:return [],reason
    citations=[Citation('',0,i,r.relative,r.first,r.last,0,0) for i,r in enumerate(reads)]
    rows=[]
    for located in locate(document['source'],reads,citations):
        relative=located.citation.relative;fp,size=files[relative]
        rows.extend((SourceRange(relative,fp,size,number,number),a,b) for number,a,b in located.rows)
    return rows,reason


def grouped(rows):
    """One union of finite actually observed lines per file fingerprint."""
    merged=[]
    for source in sorted(set(rows),key=lambda r:(r.file,r.first,r.last)):
        if merged and merged[-1].file==source.file and source.first<=merged[-1].last+1:
            old=merged.pop();source=SourceRange(*old.file,old.first,max(old.last,source.last))
        merged.append(source)
    return merged


def presented(body,documents):
    # The transport owns these owner markers. Source bytes are then checked
    # independently, including encoded-vs-decoded coordinate presentation.
    docs={d['owner']:d for d in documents};result=[];unknown=set();issues=[]
    for part in body.split('\nWORK GRAPH '):
        if '  GROUNDED OUTCOME\n' not in part:continue
        owner=part.split('\n',1)[0];d=docs.get(owner)
        if d is None or d['source'] is None:
            issues.append(dict(owner=owner,reason='unbound-delivered-owner'));continue
        evidence=part.split('  GROUNDED OUTCOME\n',1)[1].split('  TRACE\n',1)[0]
        spans=[];bad=False;raw=d['source']
        for m in CAPTION.finditer(evidence):
            first,last=int(m[1]),int(m[2])
            if not 0<=first<last<=len(raw):bad=True;continue
            expected=raw[first:last]
            if m[3] or m[4]:
                try:expected=json.loads('"'+expected+'"')
                except ValueError:bad=True;continue
            if not evidence[m.end():].startswith(expected):bad=True;continue
            spans.append((first,last))
        if not spans:
            decoded,_=decode_layout(raw)
            if raw and (raw in evidence or decoded in evidence):spans=[(0,len(raw))]
            else:bad=True
        rows,reason=original_rows(d)
        if bad:
            unknown.update((r.file for r,_,_ in rows))
            unknown.update((relative,fp,size) for relative,(fp,size) in file_map(d['records']).items())
            issues.append(dict(owner=owner,reason='unverified-presentation-coordinate'))
        for source,a,b in rows:
            if any(c<=a and b<=e for c,e in spans):result.append(source)
    return grouped(result),unknown,issues


def replay(attempt,before_export,after_export,graph):
    _,before=load_export(before_export);_,after=load_export(after_export)
    stored=grouped([r for d in before for r,_,_ in original_rows(d)[0]])
    calls,_=read_rpc(attempt/'rpc/exchange.jsonl')
    by_command=defaultdict(list)
    for call in calls.values():
        if 'start' in call and 'finish' in call:
            call['lines']=numbered_lines(call['output']);by_command[call['command']].append(call)
    reads=defaultdict(list);issues=[]
    for d in after:
        if not d['native'] or d['source'] is None:continue
        rows,reason=original_rows(d)
        if reason:issues.append(dict(owner=d['owner'],reason=reason))
        text,_=decode_layout(d['source']);lines=numbered_lines(text)
        exact_ids={row['session']+'/'+row['turn']+'/'+row['useId'] for row in d.get('occurrences',[])}
        if not exact_ids:
            issues.append(dict(owner=d['owner'],reason='no-native-occurrence-identity'))
            continue
        for call in by_command.get(command(d['work'] or ''),[]):
            if exact_ids and call['occurrence'] not in exact_ids:continue
            if rows and lines and lines<=call['lines']:
                reads[call['occurrence']].extend(r for r,_,_ in rows)
    query=key((attempt/'prompt.txt').read_text());present=[];unknown=set();starts={};stats=Counter();events=[]
    # Earlier packets only: a PreToolUse packet delivered after the tool was
    # proposed cannot retroactively explain what the model knew at proposal.
    with (attempt/'rpc/exchange.jsonl').open() as stream:
        for ordinal,line in enumerate(stream):
            record=json.loads(line)
            if record['direction']!='server':continue
            m=record['message'];p=m.get('params',{})
            if m.get('method')=='hook/completed':
                for index,entry in enumerate(p['run']['entries']):
                    if entry['kind']!='context':continue
                    located,uncertain,rejected=presented(entry['text'],before+after)
                    present=grouped(present+located);unknown.update(uncertain);issues.extend(rejected)
                    stats['packets']+=1
            elif m.get('method')=='item/started' and p['item']['type']=='commandExecution':
                occurrence=p['threadId']+'/'+p['turnId']+'/'+p['item']['id']
                starts[occurrence]=(list(present),set(unknown))
            elif m.get('method')=='item/completed' and p['item']['type']=='commandExecution':
                occurrence=p['threadId']+'/'+p['turnId']+'/'+p['item']['id'];stats['completedCommands']+=1
                if occurrence not in starts:
                    stats['missingStart']+=1;continue
                if occurrence not in reads:
                    stats['unboundReadOrNonReadCommand']+=1;continue
                delivered,uncertain=starts[occurrence]
                for requested in grouped(reads[occurrence]):
                    if requested.file in uncertain:
                        label=graph.record_read(key([occurrence,requested.identity,'uncertain']),query,
                            requested,stored,delivered,False)
                        stats['unknownPresentationReadRanges']+=1
                        events.append(dict(occurrence=occurrence,source=requested.identity,label=label,uncertain=True))
                        continue
                    gaps=observed_gaps(requested,stored,delivered)
                    if gaps:
                        for gap in gaps:
                            label=graph.record_read(key([occurrence,gap.identity,'reread']),query,gap,stored,delivered,True)
                            assert label=='omitted_then_read'
                            events.append(dict(occurrence=occurrence,source=gap.identity,label=label,uncertain=False))
                    else:
                        label=graph.record_read(key([occurrence,requested.identity,'reread']),query,
                            requested,stored,delivered,True)
                        events.append(dict(occurrence=occurrence,source=requested.identity,label=label,uncertain=False))
    paths=sorted({r.relative for r in present});fingerprints=defaultdict(set)
    for r in present:fingerprints[r.relative].add((r.fingerprint,r.source_bytes))
    citations,rejected=parse_citations('actual-answer',0,(attempt/'answer.txt').read_text(),paths)
    cited=0
    for citation in citations:
        fprints=fingerprints[citation.relative]
        if len(fprints)!=1:continue
        fp,size=next(iter(fprints));r=SourceRange(citation.relative,fp,size,citation.first,citation.last)
        event=key([str(attempt),'cited',r.identity,citation.claim_first,citation.claim_last])
        if graph.record_citation(event,query,r,present):cited+=1
    return dict(attempt=str(attempt),queryKey=query,counts=dict(stats),
        observedReadLabels=dict(Counter(e['label'] for e in events)),readEvents=events,
        deliveredThenCitedEvents=cited,issues=issues,citationIssues=rejected,
        inputHashes={str(f):sha(f) for f in [before_export,after_export,attempt/'rpc/exchange.jsonl',attempt/'answer.txt',attempt/'prompt.txt']})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exports',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise ValueError('Keep the existing replay')
    manifest=json.loads(args.exports.read_text());graph=Synapses();reports=[]
    before={r['stage']:Path(r['export']) for r in manifest['rows'] if r['kind']=='input'}
    for row in manifest['rows']:
        if row['kind']!='output':continue
        reports.append(dict(stage=row['stage'],label=row['label'],**replay(
            Path(row['attempt']),before[row['stage']],Path(row['export']),graph)))
    args.output.mkdir(parents=True)
    (args.output/'usage-graph.json').write_text(json.dumps(graph.export(),ensure_ascii=False,indent=2)+'\n')
    report=dict(scope='Retrospective private diagnostic on candidate 13 trials only; not training data injected into frozen benchmarks',
        rows=reports,labels=dict(Counter(row['label'] for row in graph.usage.values())),
        usageEvents=len(graph.usage),oracleRead=False,answeringModelCalls=0,productionAdoption=False,
        scripts={n:sha(Path(__file__).with_name(n)) for n in ['synapse_feedback.py','synapse_graph.py','build_synapses.py','citation_bridge.py']})
    (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(trials=len(reports),events=len(graph.usage),labels=report['labels'])))
