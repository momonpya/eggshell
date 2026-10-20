"""Exercise aggregate limits with small processes; never allocate near four GiB."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from memory_guard import code_sha, processes, require_guard, run


class MemoryGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()

    def test_normal_completion_records_peak_and_output(self):
        path = self.base / 'normal.json'
        result = run([sys.executable, '-c', 'print("ok")'], path, self.base, disk_mib=0)
        self.assertFalse(result['guardTriggered'])
        self.assertEqual(result['exitCode'], 0)
        self.assertGreater(result['sampledPeakRssKiB'], 0)
        self.assertEqual(path.with_suffix('.stdout').read_text().strip(), 'ok')
        with self.assertRaises(ValueError):
            run([sys.executable, '-c', 'print("must not rerun")'], path, self.base, disk_mib=0)

    def test_child_and_grandchild_rss_is_counted_and_unrelated_process_survives(self):
        unrelated = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        try:
            leaf = self.base / 'leaf.py'
            leaf.write_text('import os,time\nfrom pathlib import Path\n'
                'Path("leaf.pid").write_text(str(os.getpid()))\n'
                'data=bytearray(64*1024*1024)\ntime.sleep(30)\n')
            parent = self.base / 'parent.py'
            parent.write_text('import subprocess,sys,time\n'
                'subprocess.Popen([sys.executable,"leaf.py"])\ntime.sleep(30)\n')
            result = run([sys.executable, str(parent)], self.base / 'limited.json', self.base,
                         limit_mib=48, disk_mib=0)
            self.assertTrue(result['guardTriggered'])
            self.assertEqual(result['reason'], 'aggregate-rss')
            self.assertGreaterEqual(result['sampledPeakRssKiB'], 48 * 1024)
            self.assertLess(result['sampledPeakRssKiB'], 256 * 1024)
            pid = int((self.base / 'leaf.pid').read_text())
            row = processes().get(pid)
            self.assertTrue(row is None or row['state'].startswith('Z'))
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=5)

    def test_threshold_above_three_gib_is_rejected_before_spawn(self):
        with patch('memory_guard.subprocess.Popen') as spawn:
            with self.assertRaises(ValueError):
                run(['never-start'], self.base / 'invalid.json', self.base, limit_mib=3073)
            spawn.assert_not_called()

    def test_dispatch_rejects_missing_or_stale_monitor(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                require_guard(dict(memoryGuardSha256=code_sha()))
        record = self.base / 'stale.json'
        record.write_text(json.dumps(dict(guardPid=os.getppid(), state='finished',
            limitRssKiB=3072 * 1024, guardSha256=code_sha())))
        with patch.dict(os.environ, dict(EGGSHELL_EXPERIMENT_GUARD_PID=str(os.getppid()),
                                        EGGSHELL_EXPERIMENT_GUARD_RECORD=str(record))):
            with self.assertRaises(ValueError):
                require_guard(dict(memoryGuardSha256=code_sha()))


if __name__ == '__main__':
    unittest.main()
