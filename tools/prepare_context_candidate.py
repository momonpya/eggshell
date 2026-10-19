#!/usr/bin/env python3
"""Build a native complete-context candidate in its own checkout/cache."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from context_candidate import provider, warm, numerical, readonly_test_fixture, main_test_fixture

MODEL = 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2'
HELPERS = ['context_candidate.py', 'context_encoding.py', 'prepare_context_candidate.py', 'ContextWindowTests.lean']
TARGETS = '''
lean_exe context_window_tests where
  root := `tools.ContextWindowTests
'''


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda:handle.read(1048576),b''):
            digest.update(chunk)
    return digest.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value,indent=2)+'\n')


def input_manifest(support):
    runtime = support/'fastembed-0.8.0'
    sites = list((runtime/'lib').glob('python*/site-packages'))
    if len(sites)!=1:
        raise ValueError('Ambiguous numerical runtime')
    site = sites[0]
    paths = [runtime/'bin/python']
    for pattern in ['fastembed/**/*.py', 'tokenizers/*.py', 'tokenizers/*.so', 'onnxruntime/__init__.py',
                    'onnxruntime/capi/*.so', 'onnxruntime/capi/*.dylib', 'numpy/__init__.py', 'numpy/_core/*.so']:
        paths.extend(site.glob(pattern))
    model = support/'models/models--qdrant--paraphrase-multilingual-MiniLM-L12-v2-onnx-Q'
    revision = (model/'refs/main').read_text().strip()
    assets = [p for p in (model/'snapshots'/revision).rglob('*') if p.is_file()]+[model/'refs/main']
    if not assets or not any(p.suffix=='.onnx' for p in assets):
        raise ValueError('Complete pinned MiniLM assets are required')
    return dict(model=MODEL, runtimeFiles={str(p.relative_to(runtime)):sha(p) for p in sorted(set(paths))},
                modelFiles={str(p.relative_to(support/'models')):sha(p) for p in sorted(assets)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source','support','output']:
        parser.add_argument('--'+name,required=True,type=Path)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output.is_relative_to(source) or source.is_relative_to(output):
        parser.error('Use a separate experiment directory')
    output.mkdir(parents=True,exist_ok=False,mode=0o700)
    checkout=output/'checkout';checkout.mkdir()
    names = subprocess.check_output(['git','ls-files','-z'],cwd=source).decode().strip('\0').split('\0')
    names=sorted(set(names+['tools/'+n for n in HELPERS]))
    frozen={n:sha(source/n) for n in names}
    for name in names:
        path=source/name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Sources must be regular files')
        (checkout/name).parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(path,checkout/name)
    inputs=input_manifest(args.support)
    write(output/'encoder-inputs.json',inputs)
    for name, transform in [('Eggshell/SearchProvider.lean',provider),('Eggshell/Warm.lean',warm)]:
        path=checkout/name;path.write_text(transform(path.read_text()))
    test=checkout/'tests/ReadOnlyCacheTests.lean'
    test.write_text(readonly_test_fixture(test.read_text()))
    test=checkout/'TestMain.lean'
    test.write_text(main_test_fixture(test.read_text()))
    runtime=checkout/'runtime/embedding.py'
    runtime.write_text(numerical(runtime.read_text(),(source/'tools/context_encoding.py').read_text(),inputs))
    compile(runtime.read_text(),str(runtime),'exec')
    (checkout/'lakefile.lean').write_text((checkout/'lakefile.lean').read_text()+TARGETS)
    (checkout/'.lake').mkdir()
    subprocess.run(['/bin/cp','-cpR',str(source/'.lake/build'),str(checkout/'.lake/build')],check=True,timeout=60)
    binary=source/'.lake/build/bin/eggshell';original=sha(binary)
    if binary.stat().st_ino==(checkout/'.lake/build/bin/eggshell').stat().st_ino:
        raise ValueError('Candidate cache aliases production outputs')
    changed=['Eggshell/SearchProvider.lean','Eggshell/Warm.lean','runtime/embedding.py','lakefile.lean',
             'tests/ReadOnlyCacheTests.lean','TestMain.lean']
    write(output/'manifest.json',dict(sourceHashes=frozen,overlayHashes={n:sha(checkout/n) for n in changed},
        encoderInputsSha256=sha(output/'encoder-inputs.json'),productionBinarySha256=original,
        productionAdoption=False,generationModelCalls=0))
    for label,command in [('build',['lake','--no-cache','build','eggshell','context_window_tests','Eggshell.ContractAudit']),
                          ('checks',[str(checkout/'.lake/build/bin/context_window_tests')])]:
        with (output/(label+'.log')).open('w') as log:
            done=subprocess.run(command,cwd=checkout,env=dict(os.environ,LEAN_NUM_THREADS='1',HF_HUB_OFFLINE='1',
                EGGSHELL_DATA_ROOT=str(output/'check-data')),stdout=log,stderr=subprocess.STDOUT,timeout=600)
        write(output/(label+'.json'),dict(command=command,exitCode=done.returncode));done.check_returncode()
    if sha(binary)!=original or any(sha(source/n)!=v for n,v in frozen.items()):
        raise ValueError('Candidate changed production inputs')
    if input_manifest(args.support)!=inputs:
        raise ValueError('Numerical assets changed during the build')
    write(output/'result.json',dict(passed=True,candidateSha256=sha(checkout/'.lake/build/bin/eggshell'),
        productionFilesUnchanged=True,modelAssetsUnchanged=True,productionAdoption=False))
    print(json.dumps(dict(passed=True,checkout=str(checkout))))


if __name__=='__main__':
    main()
