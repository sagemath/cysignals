#!/usr/bin/env python
#
# Test interaction with gdb, i.e. the cysignals-CSI script
#
# NOTE: this test is known to be broken in some cases, see
# https://github.com/sagemath/cysignals/pull/52
#

import unittest

import os
import sys
from subprocess import Popen, PIPE
from tempfile import mkdtemp
from shutil import rmtree

class TestGDB(unittest.TestCase):
    def setUp(self):
        # Store crash logs in a temporary directory
        self.crash_dir = mkdtemp()
        self.env = dict(os.environ)
        self.env["CYSIGNALS_CRASH_LOGS"] = self.crash_dir

    def tearDown(self):
        rmtree(self.crash_dir)

    def test_gdb(self):
        # Run a Python subprocess which we intentionally crash to inspect the
        # crash logfile.
        p = Popen([sys.executable], stdin=PIPE, env=self.env)
        with p.stdin as stdin:
            stdin.write(b"from cysignals.tests import *\n")
            stdin.write(b"unguarded_dereference_null_pointer()\n")

        ret = p.wait()
        self.assertLess(ret, 0)

        # Check crash log
        logs = [os.path.join(self.crash_dir, fn)
                for fn in os.listdir(self.crash_dir) if fn.endswith(".log")]
        self.assertEqual(len(logs), 1)
        log = open(logs[0]).read()

        self.assertIn(b"Stack backtrace", log)
        self.assertIn(b"Cython backtrace", log)
        self.assertIn(b"__pyx_pf_9cysignals_5tests_46unguarded_dereference_null_pointer()", log)
        self.assertIn(b"cdef void dereference_null_pointer() nogil:", log)


if __name__ == '__main__':
    unittest.main()
