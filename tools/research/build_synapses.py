#!/usr/bin/env python3
"""Extract advisory derivation and coquotation from pinned exports/actual RPC.

No expected-answer file, source file, URL, embedding provider or LLM is read.
Usage event extraction is separate and uses the same Synapses core.
"""
from collections import Counter, defaultdict
from dataclasses import asdict
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
from citation_bridge import Citation, decode_layout, locate, numbered_reads, parse_citations, safe_relative
from synapse_graph import Synapses, SourceRange, consume_trace, key


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def unwrap(command):
    try:
        words=shlex.split(command)
    except ValueError:
        return command
    if len(words)==3 and Path(words[0]).name in ('sh','bash','zsh') and words[1] in ('-c','-lc'):
        return words[2]
    return command


def command(work):
    try:
        data=json.loads(work.split('\n',1)[1])
    except (ValueError,IndexError):
        return None
    if isinstance(data,dict):
        text=data.get('command',data.get('cmd'))
        return unwrap(text) if isinstance(text,str) else None
    return None


def read_rpc(path):
    calls,events={},[]
    with path.open() as stream:
        for ordinal,line in enumerate(stream):
            record=json.loads(line)
            if record['direction']!='server':continue
            message=record['message'];method=message.get('method')
            if method not in ('item/started','item/completed'):continue
            params=message['params'];item=params['item']
            if item['type']!='commandExecution':continue
            identity=params['threadId']+'/'+params['turnId']+'/'+item['id']
            row=calls.setdefault(identity,dict(occurrence=identity,command=unwrap(item['command']),
                rpc=str(path),thread=params['threadId']))
            phase='start' if method=='item/started' else 'finish'
            row[phase]=ordinal
            if phase=='finish':row['output']=item.get('aggregatedOutput') or '';row['exitCode']=item.get('exitCode')
            events.append(dict(phase=phase,occurrence=identity,ordinal=ordinal,
                text=row['command'] if phase=='start' else row['output']))
    return calls,events


def file_map(records):
    candidates=defaultdict(set)
    for record in records:
        if not record['complete'] or record['uris']:continue
        for f in record['files']:
            content=f['content']
            if safe_relative(f['relative']) and content is not None:
                try:SourceRange(f['relative'],content['root'],content['bytes'],1,1)
                except ValueError:continue
                candidates[f['relative']].add((content['root'],content['bytes']))
    return {relative:next(iter(values)) for relative,values in candidates.items() if len(values)==1}


def numbered_lines(text):
    return {tuple(match.groups()) for line in text.splitlines()
            if (match:=re.fullmatch(r' *([1-9]\d*)\t(.*)',line))}


def load_export(path):
    with path.open() as stream:rows=[json.loads(line) for line in stream]
    if rows[0]['kind']!='publication' or any(row['kind']!='outcome' for row in rows[1:]):
        raise ValueError('Expected one pinned publication and its original Outcomes')
    return rows[0],rows[1:]


def build(export,rpcs):
    graph=Synapses();header,documents=load_export(export)
    call_by_command=defaultdict(list);traces=[];issues=[]
    for rpc in rpcs:
        calls,events=read_rpc(rpc)
        traces.append(dict(rpc=str(rpc),sha256=sha(rpc),**consume_trace(graph,events)))
        for call in calls.values():
            if 'start' in call and 'finish' in call:
                call['numberedLines']=numbered_lines(call['output'])
                call_by_command[call['command']].append(call)
    observations={};bound=0;exact_bound=0
    for document in documents:
        if not document['native'] or document['work'] is None or document['source'] is None:continue
        files=file_map(document['records']);reads,unsupported=numbered_reads(document['work'],files)
        if unsupported:issues.append(dict(owner=document['owner'],reason=unsupported))
        decoded,_=decode_layout(document['source'])
        lines=numbered_lines(decoded);cmd=command(document['work'])
        exact_ids={row['session']+'/'+row['turn']+'/'+row['useId'] for row in document.get('occurrences',[])}
        matches=[call for call in call_by_command.get(cmd,[]) if
                 (not exact_ids or call['occurrence'] in exact_ids) and lines and lines<=call['numberedLines']]
        if exact_ids and not matches:
            issues.append(dict(owner=document['owner'],reason='exact-occurrence-not-bound-to-this-trace'))
        if matches:
            bound+=1
            exact_bound+=bool(exact_ids)
        observations[document['owner']]=dict(document=document,files=files,reads=reads,calls=matches)
        requested=[Citation('',0,index,read.relative,read.first,read.last,0,0) for index,read in enumerate(reads)]
        for located in locate(document['source'],reads,requested):
            relative=located.citation.relative;fp,size=files[relative]
            source=SourceRange(relative,fp,size,located.rows[0][0],located.rows[-1][0])
            source_id=graph.add_range(source,dict(owner=document['owner'],work=document['workKey'],rows=located.rows))
            for call in matches:graph.read_by[call['occurrence']].add(source_id)
    adjacency=defaultdict(set)
    for edge in header['all']:adjacency[edge['parent']].update(edge['children'])
    def reached(start):
        pending=[start];seen=set()
        while pending:
            work=pending.pop()
            if work in seen:continue
            seen.add(work);pending.extend(adjacency[work]-seen)
        return seen
    claims=defaultdict(set);claim_occurrences=defaultdict(set);answer_rows=[]
    for parent in documents:
        if parent['native'] or parent['source'] is None:continue
        text,_=decode_layout(parent['source']);route=reached(parent['workKey'])
        available=[o for o in observations.values() if o['document']['workKey'] in route]
        paths=sorted({p for o in available for p in o['files']})
        citations,rejected=parse_citations(parent['owner'],0,text,paths)
        issues.extend(dict(owner=parent['owner'],ordinal=index,reason=reason) for index,reason in rejected)
        supported=[]
        for observation in available:
            d=observation['document']
            for located in locate(d['source'],observation['reads'],citations):
                if not located.complete:
                    issues.append(dict(owner=d['owner'],reason='partial-stored-citation',citation=asdict(located.citation)))
                    continue
                c=located.citation;fp,size=observation['files'][c.relative]
                source=SourceRange(c.relative,fp,size,c.first,c.last)
                claim=key([parent['owner'],c.claim_first,c.claim_last])
                witness=dict(answer=parent['owner'],claimFirst=c.claim_first,claimLast=c.claim_last,
                    citation=asdict(c),binding=dict(owner=d['owner'],rows=located.rows))
                source_id=graph.support(source,claim,witness)
                claims[parent['owner']].add(claim)
                for call in observation['calls']:
                    graph.bind_support_reader(claim,source_id,call['occurrence'])
                    claim_occurrences[claim].add(call['occurrence'])
                supported.append(source)
        graph.quote_together(parent['owner'],supported)
        for claim in claims[parent['owner']]:
            graph.quote_together('claim:'+claim,[graph.ranges[s] for s in graph.supports[claim]],scope='claim')
        if citations:
            roots=sorted(set().union(*(claim_occurrences[c] for c in claims[parent['owner']]))) if claims[parent['owner']] else []
            backward=graph.backward(sorted(claims[parent['owner']]),roots)
            direct=sorted(set().union(*(graph.supports[c] for c in claims[parent['owner']]))) if claims[parent['owner']] else []
            answer_rows.append(dict(owner=parent['owner'],citations=len(citations),
                claims=sorted(claims[parent['owner']]),supportedRanges=direct,
                boundReaderOccurrences=roots,backward=backward))
    counts=Counter(edge['witness']['kind'] for edge in graph.consumed.values())
    return graph,dict(publication=header['head'],sourceDocuments=len(documents),
        observedTools=len(observations),toolsBoundToActualOccurrences=bound,
        exactOccurrenceBindings=exact_bound,legacyTextBindings=bound-exact_bound,traces=traces,
        consumedWitnesses=dict(counts),consumedPairs=len({(e['producer'],e['consumer']) for e in graph.consumed.values()}),
        answers=answer_rows,issues=issues,usageExtraction='pending separate ordered delivery/read replay',
        inputExport=dict(file=str(export),sha256=sha(export)),
        scripts={n:sha(Path(__file__).with_name(n)) for n in ['build_synapses.py','synapse_graph.py','citation_bridge.py']},
        oracleRead=False,answeringModelCalls=0,productionAdoption=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export',type=Path,required=True)
    parser.add_argument('--rpc',type=Path,action='append',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise ValueError('Keep previous extraction outputs')
    graph,report=build(args.export,args.rpc)
    args.output.mkdir(parents=True)
    (args.output/'graph.json').write_text(json.dumps(graph.export(),ensure_ascii=False,indent=2)+'\n')
    (args.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(documents=report['sourceDocuments'],toolsBound=report['toolsBoundToActualOccurrences'],
        consumedWitnesses=report['consumedWitnesses'],consumedPairs=report['consumedPairs'],
        supportedClaims=len(graph.supports),coquoteHyperedges=len(graph.coquoted),usageEvents=len(graph.usage))))
