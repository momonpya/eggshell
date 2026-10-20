#!/usr/bin/env python3
"""Build retrieval experiments in a separate checkout and compiler cache."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HELPERS = ['RetrievalCategories.lean', 'RetrievalGrams.lean', 'RetrievalGramsTests.lean', 'RetrievalTerms.lean',
           'RetrievalIndex.lean', 'RetrievalIndexTests.lean', 'RetrievalScale.lean']
TARGETS = '''
lean_lib RetrievalResearch where
  roots := #[`tools.RetrievalGrams, `tools.RetrievalCategories, `tools.RetrievalIndex]

lean_exe retrieval_terms where
  root := `tools.RetrievalTerms

lean_exe retrieval_grams_tests where
  root := `tools.RetrievalGramsTests

lean_exe retrieval_index_tests where
  root := `tools.RetrievalIndexTests

lean_exe retrieval_scale where
  root := `tools.RetrievalScale
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output.is_relative_to(source) or source.is_relative_to(output):
        parser.error('Use a separate experiment directory')
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    checkout = output/'checkout'
    checkout.mkdir()
    names = subprocess.check_output(['git','ls-files','-z'], cwd=source).decode().strip('\0').split('\0')
    names = sorted(set(names + ['tools/'+name for name in HELPERS]))
    frozen = {name:sha(source/name) for name in names}
    for name in names:
        path = source/name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Research sources must be ordinary files')
        (checkout/name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, checkout/name)
    binary = source/'.lake/build/bin/eggshell'
    original = sha(binary)
    (checkout/'lakefile.lean').write_text((source/'lakefile.lean').read_text()+TARGETS)
    (checkout/'.lake').mkdir()
    subprocess.run(['/bin/cp','-cpR',str(source/'.lake/build'),str(checkout/'.lake/build')], check=True,timeout=60)
    if binary.stat().st_ino == (checkout/'.lake/build/bin/eggshell').stat().st_ino:
        raise ValueError('Research outputs alias the production cache')
    write(output/'manifest.json',dict(sourceHashes=frozen, productionBinarySha256=original,
        productionAdoption=False, generationModelCalls=0, helpers=HELPERS))
    for label, command in [('build',['lake','--no-cache','build','retrieval_terms','retrieval_grams_tests','retrieval_index_tests','retrieval_scale']),
                            ('tests',[str(checkout/'.lake/build/bin/retrieval_grams_tests')]),
                            ('index-tests',[str(checkout/'.lake/build/bin/retrieval_index_tests')])]:
        with (output/(label+'.log')).open('w') as log:
            completed = subprocess.run(command,cwd=checkout,stdout=log,stderr=subprocess.STDOUT,timeout=300,
                env=dict(os.environ, LEAN_NUM_THREADS='1',EGGSHELL_DATA_ROOT=str(output/'test-data')))
        write(output/(label+'.json'),dict(command=command,exitCode=completed.returncode))
        completed.check_returncode()
    if sha(binary)!=original or any(sha(source/name)!=value for name,value in frozen.items()):
        raise ValueError('Research changed production inputs')
    write(output/'result.json',dict(passed=True, productionFilesUnchanged=True,
        termsBinarySha256=sha(checkout/'.lake/build/bin/retrieval_terms'),
        scaleProducerSha256=sha(checkout/'.lake/build/bin/retrieval_scale'),productionAdoption=False))
    print(json.dumps(dict(passed=True, checkout=str(checkout))))


if __name__ == '__main__':
    main()
