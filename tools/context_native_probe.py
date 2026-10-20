#!/usr/bin/env python3
"""Exercise complete-context caches through warm/doctor and native hooks."""
import argparse
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from pilot_memory_probe import protected_databases
from semantic_latency import execute, graph_files, hook, receipt_for, shutdown, save


def sha(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1048576),b''):
            value.update(chunk)
    return value.hexdigest()


def tree(directory):
    return {str(p.relative_to(directory)):sha(p) for p in directory.rglob('*') if p.is_file()}


def config(path, binary, database, writable):
    path.write_text('default = "probe"\nsemantic_matcher = '+json.dumps([str(binary),'search-provider'])+
        '\n[eggs]\nsource = '+json.dumps(str(database))+'\n[profiles.probe]\nread = ["source"]\n'+
        ('write = "source"\n' if writable else '')+'handoff_chars = 120000\n')


def environment(data, config_file, prefix):
    env={k:v for k,v in os.environ.items() if k in {'PATH','HOME','USER','LOGNAME','LANG','LC_ALL'}}
    env.update(EGGSHELL_DATA_ROOT=str(data),EGGSHELL_CONFIG=str(config_file),EGGSHELL_PREFIX=str(prefix),
               HF_HUB_OFFLINE='1',LEAN_NUM_THREADS='1')
    return env


def doctor(raw):
    value=json.loads(raw)
    rows=value.get('databases',[])
    if len(rows)!=1:
        raise ValueError('Doctor did not inspect exactly one DB')
    return rows[0]


def delivery(binary, cell, env, question, label, windows, successful):
    session='context-'+label
    hook(binary,cell,env,'SessionStart',session,cell/(label+'-start'))
    try:
        output,timing=hook(binary,cell,env,'UserPromptSubmit',session,cell/(label+'-hook'),question)
        json.loads(output)
        if b'CONTEXT_ORIGINAL_BODY' not in output:
            raise ValueError('Native hook did not deliver the original DB body')
        receipt=receipt_for(cell/'data',session)
        published=json.loads((receipt/'published.json').read_text())['data']
        ack=json.loads((receipt/'ack.json').read_text())['data']
        if (published['output'].encode()!=output or published['sha256']!=hashlib.sha256(output).hexdigest()
                or published['bytes']!=len(output) or not published['replyComplete'] or not ack['offerAccepted']):
            raise ValueError('Publication/stdout/ACK evidence disagrees')
        search=json.loads((receipt/'search.json').read_text())['data']
        numerical=[json.loads(p.read_text())['data'] for p in receipt.glob('numerical-*.json')]
        discovery=[row for row in numerical if row['corpus']['purpose']=='discovery']
        if successful:
            completed=[row for row in discovery if row['status']=='completed']
            if len(completed)!=1 or search['trace']['semantic']!='completed':
                raise ValueError('Native semantic search did not complete')
            counts=completed[0]['counters'];source=counts['sourceInput'];query=counts['queryInput']
            if (counts['source']['hit']!=windows or counts['scoredWindows']!=windows or source['windows']!=windows
                    or source['vectors']<=windows or source['embeddedCharacters']!=source['tokenizerMappedCharacters']
                    or query['vectors']<=query['windows'] or query['embeddedCharacters']!=query['tokenizerMappedCharacters']
                    or counts['encoder']['sourceEncodeUs']!=0):
                raise ValueError('Native discovery omitted a warmed window, segment or query suffix')
            if timing['elapsedMs']>=5000:
                raise ValueError('The focused warm hook exceeded five seconds')
        elif search['trace']['semantic']=='completed' or not any(row['status']=='failed' for row in discovery):
            raise ValueError('Changed encoder assets did not fail explicitly before lexical body delivery')
        result=dict(elapsedMs=timing['elapsedMs'],receipt=receipt.name,trace=search['trace'],
                    numerical=numerical,publishedSha256=published['sha256'],originalBody=True,accepted=True)
        save(cell/(label+'-result.json'),result)
        return result
    finally:
        shutdown(binary,cell,env,label+'-shutdown')


def run(args):
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False,mode=0o700)
    checkout=args.build.resolve()/'checkout'
    built=json.loads((args.build/'result.json').read_text())
    binary=checkout/'.lake/build/bin/eggshell';helper=checkout/'.lake/build/bin/context_window_tests'
    if sha(binary)!=built['candidateSha256']:
        raise ValueError('Candidate executable changed after qualification')
    source=args.source.resolve();ordinary=source/'.lake/build/bin/eggshell'
    frozen={str(ordinary):sha(ordinary),str(binary):sha(binary)}
    original_prefix=args.prefix.resolve()
    config_file=output/'seed.toml';seed_data=output/'seed-data'
    env=environment(seed_data,config_file,original_prefix)
    prior_fixture=args.fixture.resolve() if args.fixture else None
    fixture_tree=None
    if prior_fixture:
        original_db=prior_fixture/'seed/source.egg'
        fixture_tree=tree(original_db)
        seed=json.loads((prior_fixture/'prepare/stdout').read_bytes())
        (output/'seed').mkdir()
        database=output/'seed/source.egg'
        subprocess.run(['/bin/cp','-cpR',str(original_db),str(database)],check=True,timeout=30)
        if tree(database)!=fixture_tree:
            raise ValueError('The reused legacy fixture changed while copying')
        seed['database']=str(database)
        save(output/'reused-fixture.json',dict(source=str(prior_fixture),files=fixture_tree,seed=seed))
    else:
        raw,_=execute([helper,'prepare',output/'seed'],output/'prepare',env,output)
        seed=json.loads(raw);database=Path(seed['database'])
    original_graph=graph_files(database)
    config(config_file,ordinary,database,True)
    raw,_=execute([ordinary,'egg','warm','source'],output/'legacy-warm',env,output)
    legacy=json.loads(raw)['databases'][0]
    expected_requests=0 if prior_fixture else seed['windows']
    if legacy['after']['valid']!=seed['windows'] or legacy['requested']!=expected_requests:
        raise ValueError('The common source snapshot was not fully warm under the ordinary provider')
    if graph_files(database)!=original_graph:
        raise ValueError('Legacy warming changed the saved graph')
    graph_saved=tree(database)
    question=seed['question']+'\n'+('保存済みの記録から検索して元の本文を配送する。質問の意味を優先して照合する。'*18)
    results={}
    for layout in ['database','private-overlay']:
        cell=output/layout;cell.mkdir();copied=cell/'source.egg'
        subprocess.run(['/bin/cp','-cpR',str(database),str(copied)],check=True,timeout=30)
        if tree(copied)!=graph_saved:
            raise ValueError('A trial was not copied from the identical saved warm snapshot')
        config_file=cell/'config.toml';config(config_file,binary,copied,layout=='database')
        env=environment(cell/'data',config_file,original_prefix)
        raw,_=execute([binary,'egg','doctor'],cell/'doctor-old',env,cell)
        old=doctor(raw)
        if old['state']!='cold' or old['coverage']['missing']!=seed['windows']:
            raise ValueError('Legacy single-vector files falsely certified complete context coverage')
        if args.indexed_lexical and old['lexical']['ready']:
            raise ValueError('Legacy retrieval postings falsely certified the new grammar')
        if layout=='private-overlay':
            protection=protected_databases([copied])
        else:
            protection=nullcontext()
        with protection:
            protected_before=tree(copied)
            raw,_=execute([binary,'egg','warm','source'],cell/'warm',env,cell)
            warmed=json.loads(raw)['databases'][0]
            if warmed['requested']!=seed['windows'] or warmed['after']['input']['vectors']<=seed['windows']:
                raise ValueError('Candidate warming did not rebuild every complete original window')
            if args.indexed_lexical and warmed['lexical']['added']!=seed['documents']:
                raise ValueError('Combined warm omitted original lexical owners')
            raw,_=execute([binary,'egg','warm','source'],cell/'warm-again',env,cell)
            repeated=json.loads(raw)['databases'][0]
            if repeated['requested'] or repeated['batches']:
                raise ValueError('A warm repeated candidate started indexing again')
            if args.indexed_lexical and (repeated['lexical']['added'] or repeated['lexical']['hydrated']):
                raise ValueError('Combined repeated warm rebuilt the lexical corpus')
            raw,_=execute([binary,'egg','doctor'],cell/'doctor-warm',env,cell)
            inspected=doctor(raw)
            if inspected['state']!='warm' or inspected['coverage']['valid']!=seed['windows']:
                raise ValueError('Doctor did not report complete candidate coverage')
            if args.indexed_lexical and not inspected['lexical']['ready']:
                raise ValueError('Combined doctor certified warm without complete lexical postings')
            config(config_file,binary,copied,False)
            # Both healthy deliveries are read-only; primary writes finish
            # before protection, while the overlay warms the protected DB.
            healthy_before=tree(copied)
            with protected_databases([copied]) if layout=='database' else nullcontext():
                delivered=delivery(binary,cell,env,question,layout,seed['windows'],True)
                cached=delivery(binary,cell,env,question,layout+'-cached',seed['windows'],True)
                completed=[row for row in cached['numerical'] if row['corpus']['purpose']=='discovery'
                           and row['status']=='completed'][0]['counters']
                if (completed['query']['absent'] or completed['query']['unusable'] or
                        completed['query']['hit']!=completed['queryInput']['windows'] or
                        completed['encoder']['modelLoaded'] or completed['encoder']['initializeUs'] or
                        completed['encoder']['queryEncodeUs'] or completed['encoder']['sourceEncodeUs']):
                    raise ValueError('The next chat reinitialized an encoder for fully cached input')
            if tree(copied)!=healthy_before or graph_files(copied)!=original_graph:
                raise ValueError('Read-only semantic delivery changed DB bytes')
            if layout=='private-overlay' and tree(copied)!=protected_before:
                raise ValueError('Private warming wrote into the protected shared DB')
            results[layout]=dict(oldDoctor=old,warm=warmed,repeated=repeated,doctor=inspected,
                                 delivery=delivered,cachedDelivery=cached)
    # An actual changed numerical implementation must fail before inference,
    # even when original source windows are already warm. Only this private
    # installation is altered; the shared graph stays protected.
    asset_prefix=output/'changed-assets-prefix'
    (asset_prefix/'share/eggshell').mkdir(parents=True)
    subprocess.run(['/bin/cp','-cpR',str(original_prefix/'share/eggshell/minilm'),
                    str(asset_prefix/'share/eggshell/minilm')],check=True,timeout=60)
    changed=next((asset_prefix/'share/eggshell/minilm/fastembed-0.8.0/lib').glob(
        'python*/site-packages/fastembed/text/pooled_embedding.py'))
    before=sha(changed)
    with changed.open('a') as stream:
        stream.write('\n# controlled contract-mismatch probe\n')
    cell=output/'private-overlay';copied=cell/'source.egg';config_file=cell/'config.toml'
    env=environment(cell/'data',config_file,asset_prefix)
    shared_before=tree(copied)
    with protected_databases([copied]):
        failed=delivery(binary,cell,env,question+'\n変更された埋め込み資産の検査',
                        'changed-assets',seed['windows'],False)
    if tree(copied)!=shared_before:
        raise ValueError('Failed inference changed the shared DB')
    results['changed-assets']=dict(path=str(changed.relative_to(asset_prefix)),
        originalSha256=before,changedSha256=sha(changed),delivery=failed)
    query_records=[]
    for path in output.glob('*/data/queries/vectors/*.json'):
        record=json.loads(path.read_text())
        if set(record)!={'model','window','contract','coverage','vector'} or not isinstance(record['vector'],list):
            raise ValueError('A private query record contains plaintext or has the old shape')
        query_records.append(dict(path=str(path.relative_to(output)),sha256=sha(path),segments=len(record['vector'])))
    if not query_records:
        raise ValueError('No private complete-context question records were observed')
    if tree(database)!=graph_saved or any(sha(Path(p))!=v for p,v in frozen.items()):
        raise ValueError('Trials changed their common source or executable')
    if prior_fixture and tree(prior_fixture/'seed/source.egg')!=fixture_tree:
        raise ValueError('The original legacy fixture was modified')
    save(output/'result.json',dict(passed=True,layouts=results,sourceGraph=original_graph,
        sourceSnapshotUnchanged=True,privateQueryRecords=query_records,
        generationModelCalls=0,productionAdoption=False))
    print(json.dumps(dict(passed=True,windows=seed['windows'],layouts=list(results))))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','build','prefix','output']:
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--fixture',type=Path,help='Reuse the exact saved legacy seed of an earlier probe')
    parser.add_argument('--indexed-lexical',action='store_true',help='Require complete dictionary-free lexical preparation too')
    args=parser.parse_args()
    try:
        run(args)
    except Exception as error:
        if args.output.is_dir():
            save(args.output/'failure.json',dict(error=f'{type(error).__name__}: {error}',productionAdoption=False))
        raise


if __name__=='__main__':
    main()
