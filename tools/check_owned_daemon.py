#!/usr/bin/env python3
"""Compare parent-blocked and concurrently reaped shutdown of the same binary."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

from owned_daemon import shutdown_owned


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False,mode=0o700)
    original=hashlib.sha256(args.binary.read_bytes()).hexdigest();rows=[]
    for refined in [False,True]:
        cell=args.output/('owned-reap' if refined else 'parent-blocked');cell.mkdir()
        config=cell/'config.toml';config.write_text('default = "empty"\nsemantic_matcher = false\n[profiles.empty]\nread = []\n')
        env={k:v for k,v in os.environ.items() if k in {'PATH','HOME','USER','LOGNAME','LANG','LC_ALL'}}
        env.update(EGGSHELL_DATA_ROOT=str(cell/'data'),EGGSHELL_CONFIG=str(config),LEAN_NUM_THREADS='1')
        session='owned-daemon-control'
        with (cell/'daemon.log').open('wb') as log:
            process=subprocess.Popen([str(args.binary),'codex-daemon',session],env=env,cwd=cell,
                                     stdout=log,stderr=subprocess.STDOUT)
            endpoint=cell/'data/sessions'/session/'daemon.json';expires=time.monotonic()+5
            try:
                while not endpoint.exists():
                    if process.poll() is not None or time.monotonic()>expires:
                        raise RuntimeError('Control daemon did not start')
                    time.sleep(0.005)
                if refined:
                    result=shutdown_owned(process,args.binary,env,cell,cell/'shutdown.json')
                    if result['exit_code'] or result['daemon_exit_code']:
                        raise ValueError('Concurrent reaping did not complete both processes')
                else:
                    result=subprocess.run([str(args.binary),'codex-daemon','shutdown'],env=env,cwd=cell,
                                          capture_output=True,text=True,timeout=8)
                    status=subprocess.check_output(['ps','-o','stat=','-p',str(process.pid)],text=True).strip()
                    reaped=process.wait(timeout=3)
                    result=dict(exit_code=result.returncode,stderr=result.stderr,daemon_state_before_reap=status,
                                daemon_exit_code=reaped)
                    (cell/'shutdown.json').write_text(json.dumps(result,indent=2)+'\n')
                    if (result['exit_code']!=1 or 'acknowledged shutdown but has not exited' not in result['stderr']
                            or not status.startswith('Z') or reaped!=0):
                        raise ValueError('Parent-blocked zombie counterfactual was not reproduced')
                if endpoint.exists():raise ValueError('A stopped daemon retained its endpoint')
                rows.append(dict(refined=refined,result=result))
            finally:
                if process.poll() is None:
                    process.terminate();process.wait(timeout=3)
    if hashlib.sha256(args.binary.read_bytes()).hexdigest()!=original:
        raise ValueError('Lifecycle controls changed the native binary')
    record=dict(passed=True,binary_sha256=original,conditions=rows,generationModelCalls=0)
    (args.output/'result.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record))


if __name__=='__main__':main()
