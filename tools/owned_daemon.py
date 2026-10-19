"""Reap an owned native daemon while its shutdown client waits for PID exit."""
import json
from pathlib import Path
import subprocess
import time


def shutdown_owned(process,binary,env,cwd,output,timeout=15):
    command=[str(binary),'codex-daemon','shutdown']
    client=subprocess.Popen(command,env=env,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    started=time.monotonic();expires=started+timeout
    try:
        while True:
            # poll() performs waitpid(WNOHANG), releasing a completed child's
            # zombie PID. Waiting synchronously for the client first deadlocks
            # with the client's kill(pid,0) exit check.
            daemon_code=process.poll()
            client_code=client.poll()
            if daemon_code is not None and client_code is not None:
                break
            if time.monotonic()>=expires:
                raise TimeoutError('Owned daemon/client did not stop before the cleanup deadline')
            time.sleep(0.005)
        stdout,stderr=client.communicate(timeout=1)
        record=dict(command=command,exit_code=client_code,daemon_exit_code=daemon_code,
                    stdout=stdout.decode(),stderr=stderr.decode(),elapsed_seconds=time.monotonic()-started)
        Path(output).write_text(json.dumps(record,indent=2)+'\n')
        if client_code or daemon_code:
            raise RuntimeError('Owned daemon shutdown failed; see '+str(output))
        return record
    finally:
        for child in [client,process]:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill();child.wait(timeout=3)
