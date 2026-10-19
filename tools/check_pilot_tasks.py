#!/usr/bin/env python3
from pathlib import Path
import json,os,shutil,subprocess,sys

if not __debug__:
    raise SystemExit('Oracle validation requires Python assertions enabled')
import argparse
parser=argparse.ArgumentParser(description='Validate the fixed task grader with positive, negative and integrity controls; no model calls')
parser.add_argument('--suite',required=True,type=Path)
parser.add_argument('--output',required=True,type=Path)
args=parser.parse_args()
suite=args.suite.resolve()
root=args.output.resolve()
root.mkdir(exist_ok=False)
manifest=json.loads((suite/'suite.json').read_text())
reports=[]

def call(label,task,candidate,expected):
    output=root/label
    result=subprocess.run([sys.executable,str(suite/'grader.py'),'grade','--suite',str(suite),'--task',task,'--candidate',str(candidate),'--output',str(output)],text=True,capture_output=True)
    (root/(label+'.stdout')).write_text(result.stdout)
    (root/(label+'.stderr')).write_text(result.stderr)
    assert (output/'grade.json').exists(),(label,result.stdout,result.stderr)
    report=json.loads((output/'grade.json').read_text())
    assert report['passed']==expected,(label,report.get('counts'),result.stdout,result.stderr)
    assert result.returncode==(0 if expected else 1)
    if report['status']=='evaluated':
        assert report['test_set_matches'] and report['protected_files_unchanged'],(label,report)
    summary=dict(label=label,expected_pass=expected,status=report['status'],counts=report.get('counts'),failed=[r['id'] for r in report.get('cases',[]) if r['failed']])
    reports.append(summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='failed'}),flush=True)
    return summary

for task in manifest['tasks']:
    call(task['id']+'-reference',task['id'],suite/'cases'/task['id']/'reference',True)
    call(task['id']+'-unchanged',task['id'],suite/'cases'/task['id']/'start',False)

def mutant(task,label,path,before,after):
    copy=root/(label+'-candidate')
    shutil.copytree(suite/'cases'/task/'reference',copy,ignore=shutil.ignore_patterns('.pytest_cache','__pycache__'))
    file=copy/path;text=file.read_text();assert text.count(before)==1,(label,text.count(before))
    file.write_text(text.replace(before,after))
    return call(label,task,copy,False)

mutant('payload-limit','disabled-limit','src/itsdangerous/serializer.py','if limit is not None and len(payload) > limit:', 'if False:')
old='''                    decoder = zlib.decompressobj()
                    json = decoder.decompress(json, min(limit + 1, sys.maxsize))
                    if len(json) > limit:
                        raise BadPayload("Payload exceeds max_payload_bytes")
                    if not decoder.eof:
                        raise BadPayload("Incomplete compressed payload")'''
new='''                    json = zlib.decompress(json)
                    if len(json) > limit:
                        raise BadPayload("Payload exceeds max_payload_bytes")'''
post=mutant('compressed-limit','unbounded-postcheck','src/itsdangerous/url_safe.py',old,new)
assert len(post['failed'])==2 and all('test_inflation_is_bounded_before_the_limit_check' in f for f in post['failed'])
chunked='''                    decoder = zlib.decompressobj()
                    first = decoder.decompress(json, min(limit + 1, sys.maxsize))
                    second = decoder.decompress(decoder.unconsumed_tail, min(limit + 1, sys.maxsize))
                    json = first + second
                    if len(json) > limit:
                        raise BadPayload("Payload exceeds max_payload_bytes")
                    if not decoder.eof:
                        raise BadPayload("Incomplete compressed payload")'''
chunks=mutant('compressed-limit','chunked-postcheck','src/itsdangerous/url_safe.py',old,chunked)
assert len(chunks['failed'])==2 and all('test_inflation_is_bounded_before_the_limit_check' in f for f in chunks['failed'])
salvage=mutant('timed-unsafe-limit','uncapped-salvage','src/itsdangerous/serializer.py','self.load_payload(e.payload, **load_payload_kwargs)','self.load_payload(e.payload)')
assert len(salvage['failed'])==12 and all('salvage' in f for f in salvage['failed'])
copy=root/'protected-edit-candidate'
shutil.copytree(suite/'cases/timed-unsafe-limit/reference',copy,ignore=shutil.ignore_patterns('.pytest_cache','__pycache__'))
with (copy/'pyproject.toml').open('a') as stream:stream.write('\n# changed grading configuration\n')
protected=call('protected-edit','timed-unsafe-limit',copy,False)
assert protected['status']=='invalid-edit'
# A source-only edit can still try to modify checks during import. Exercise
# a disposable suite copy, retaining the original frozen material unchanged.
tamper_suite=root/'tamper-suite'
shutil.copytree(suite,tamper_suite,ignore=shutil.ignore_patterns('.pytest_cache','__pycache__'))
tamper_candidate=root/'runtime-tamper-candidate'
shutil.copytree(suite/'cases/timed-unsafe-limit/reference',tamper_candidate,ignore=shutil.ignore_patterns('.pytest_cache','__pycache__'))
init=tamper_candidate/'src/itsdangerous/__init__.py'
target=tamper_suite/'material/checks/test_payload_limit.py'
with init.open('a') as stream:
    stream.write("\nfrom pathlib import Path as _ProbePath\n_ProbePath("+repr(str(target))+").open('a').write('\\n# integrity probe\\n')\n")
tamper_output=root/'runtime-tamper'
result=subprocess.run([sys.executable,str(tamper_suite/'grader.py'),'grade','--suite',str(tamper_suite),'--task','timed-unsafe-limit','--candidate',str(tamper_candidate),'--output',str(tamper_output)],text=True,capture_output=True)
(root/'runtime-tamper.stdout').write_text(result.stdout)
(root/'runtime-tamper.stderr').write_text(result.stderr)
report=json.loads((tamper_output/'grade.json').read_text())
assert result.returncode==1 and not report['passed'] and not report['frozen_material_unchanged']
assert report['counts']['failures']==report['counts']['errors']==report['counts']['skipped']==0,report['counts']
reports.append(dict(label='runtime-tamper',expected_pass=False,counts=report['counts'],frozen_material_unchanged=False))
for label,forbidden in [('candidate-overlap',suite/'cases/timed-unsafe-limit/reference/forbidden-output'),('suite-overlap',suite/'forbidden-output')]:
    result=subprocess.run([sys.executable,str(suite/'grader.py'),'grade','--suite',str(suite),'--task','timed-unsafe-limit','--candidate',str(suite/'cases/timed-unsafe-limit/reference'),'--output',str(forbidden)],text=True,capture_output=True)
    assert result.returncode!=0 and 'outside candidate and frozen suite' in result.stderr and not forbidden.exists()
    reports.append(dict(label=label,expected_refusal=True,input_unchanged=True))
# Ensure an accidentally imported editable base package cannot pass the boundary.
foreign=root/'foreign-import';foreign.mkdir()
env=os.environ.copy();env.update(PYTHONPATH='',PYTHONDONTWRITEBYTECODE='1',PYTEST_DISABLE_PLUGIN_AUTOLOAD='1',EGGSHELL_PILOT_SOURCE=str(suite/'cases/timed-unsafe-limit/reference'))
result=subprocess.run([manifest['python'],'-m','pytest','-q',str(suite/'material/checks/test_import_boundary.py'),'--junitxml='+str(foreign/'results.xml')],cwd=suite/'cases/timed-unsafe-limit/reference',env=env,text=True,capture_output=True)
(foreign/'stdout.log').write_text(result.stdout+result.stderr)
assert result.returncode==1 and '1 failed' in result.stdout
reports.append(dict(label='foreign-import',expected_pass=False,failed_boundary=True))

write=dict(passed=True,controls=reports,generation_model_calls=0,pilot_model_runs=0)
(root/'RESULT.json').write_text(json.dumps(write,indent=2)+'\n')
print(json.dumps(dict(passed=True,controls=len(reports),generation_model_calls=0)))
