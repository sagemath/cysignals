.. _section_debug:

Debugging Python crashes
========================

If ``cysignals`` is imported, it sets up a hook which triggers when
Python crashes. For example, it would be triggered on a segmentation
fault outside a ``sig_on()`` block.

When a crash happens, first a simple C backtrace is printed if supported
by the C library on the system.
Then GDB is run to print a much more complete backtrace
(except on OS X, where running a debugger requires special privileges).
For your convenience, these GDB backtraces are also saved to a logfile.

Finally, this familiar message is shown::

    This probably occurred because a *compiled* module has a bug
    in it and is not properly wrapped with sig_on(), sig_off().
    Python will now terminate.

Environment variables
---------------------

There are several environment variables which influence this:

.. envvar:: CYSIGNALS_CRASH_QUIET

    If set, be completely quiet whenever a crash happens.
    No backtrace or other message is shown and GDB is not run.

.. envvar:: CYSIGNALS_CRASH_NDEBUG

    If set, disable the GDB backtrace.
    The simple backtrace is still shown.

.. envvar:: CYSIGNALS_CRASH_LOGS

    The directory where the logs of the crashes are stored.
    If this is empty, disable storing of crash logs.
    The default is ``cysignals_crash_logs`` in the current directory.

.. envvar:: CYSIGNALS_CRASH_DAYS

    Automatically delete crash logs older than this many days
    in the directory where crash logs are stored.
    A negative value means that logs are never deleted.
    The default is 7 days if ``CYSIGNALS_CRASH_LOGS`` is unset
    and -1 days (never delete) otherwise.
