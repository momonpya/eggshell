#!/usr/bin/env python3
"""Compile a legacy seed producer, then an isolated indexed 2-gram runtime."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from lexical_candidate import TRANSFORMS, FIXTURES
from prepare_context_candidate import sha,write

HELPERS=['RetrievalCategories.lean','RetrievalGrams.lean','RetrievalGramsTests.lean',
         'RetrievalIndex.lean','RetrievalIndexTests.lean','LexicalProbe.lean',
         'lexical_candidate.py','prepare_lexical_candidate.py']
TARGETS='''
lean_lib RetrievalResearch where
  roots := #[`tools.RetrievalGrams, `tools.RetrievalCategories, `tools.RetrievalIndex]

lean_exe lexical_probe where
  root := `tools.LexicalProbe

lean_exe retrieval_grams_tests where
  root := `tools.RetrievalGramsTests

lean_exe retrieval_index_tests where
  root := `tools.RetrievalIndexTests
'''


def execute(checkout,output,label,command):
    with (output/(label+'.log')).open('w') as log:
        result=subprocess.run(command,cwd=checkout,stdout=log,stderr=subprocess.STDOUT,timeout=600,
            env=dict(os.environ,LEAN_NUM_THREADS='1',HF_HUB_OFFLINE='1',EGGSHELL_DATA_ROOT=str(output/'check-data')))
    write(output/(label+'.json'),dict(command=command,exitCode=result.returncode))
    result.check_returncode()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['source','output']:parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args();source=args.source.resolve();output=args.output.resolve()
    if output.is_relative_to(source) or source.is_relative_to(output):
        parser.error('Use a separate experiment directory')
    output.mkdir(parents=True,exist_ok=False,mode=0o700);checkout=output/'checkout';checkout.mkdir()
    names=subprocess.check_output(['git','ls-files','-z'],cwd=source).decode().strip('\0').split('\0')
    names=sorted(set(names+['tools/'+n for n in HELPERS]));frozen={n:sha(source/n) for n in names}
    for name in names:
        p=source/name
        if p.is_symlink() or not p.is_file():raise ValueError('Sources must be regular files')
        (checkout/name).parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,checkout/name)
    lakefile=checkout/'lakefile.lean';lakefile.write_text(lakefile.read_text()+TARGETS)
    (checkout/'.lake').mkdir();subprocess.run(['/bin/cp','-cpR',str(source/'.lake/build'),
        str(checkout/'.lake/build')],check=True,timeout=60)
    ordinary=source/'.lake/build/bin/eggshell';original=sha(ordinary)
    if ordinary.stat().st_ino==(checkout/'.lake/build/bin/eggshell').stat().st_ino:
        raise ValueError('Candidate outputs alias production')
    write(output/'manifest.json',dict(sourceHashes=frozen,productionBinarySha256=original,
        productionAdoption=False,generationModelCalls=0))
    execute(checkout,output,'legacy-seed-build',['lake','--no-cache','build','lexical_probe'])
    shutil.copy2(checkout/'.lake/build/bin/lexical_probe',output/'legacy-seed')
    for name,transform in {**TRANSFORMS, **FIXTURES}.items():
        p=checkout/name;p.write_text(transform(p.read_text()))
    write(output/'overlays.json',{n:sha(checkout/n) for n in {**TRANSFORMS, **FIXTURES}})
    execute(checkout,output,'build',['lake','--no-cache','build','eggshell','lexical_probe',
        'retrieval_grams_tests','retrieval_index_tests','Eggshell.ContractAudit'])
    execute(checkout,output,'grammar-tests',[str(checkout/'.lake/build/bin/retrieval_grams_tests')])
    execute(checkout,output,'index-tests',[str(checkout/'.lake/build/bin/retrieval_index_tests')])
    if sha(ordinary)!=original or any(sha(source/n)!=v for n,v in frozen.items()):
        raise ValueError('Candidate changed its production source')
    write(output/'result.json',dict(passed=True,candidateSha256=sha(checkout/'.lake/build/bin/eggshell'),
        legacySeedSha256=sha(output/'legacy-seed'),productionFilesUnchanged=True,productionAdoption=False))
    print(json.dumps(dict(passed=True,checkout=str(checkout))))


if __name__=='__main__':main()
