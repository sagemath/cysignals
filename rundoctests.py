#!/usr/bin/env python
#
# Run doctests for cysignals
#
# We add the ELLIPSIS flag by default and we run all tests even if
# one fails.
#

import doctest
import sys

flags = doctest.ELLIPSIS

filenames = sys.argv[1:]
print("Doctesting {} files.".format(len(filenames)))

success = True
for f in filenames:
    print(f)
    failures, _ = doctest.testfile(f, module_relative=False, optionflags=flags)
    if failures:
        success = False

sys.exit(0 if success else 1)
