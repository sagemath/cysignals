"""
Fine-grained alarm function
"""

#*****************************************************************************
#       Copyright (C) 2013-2016 Jeroen Demeyer <jdemeyer@cage.ugent.be>
#
#  cysignals is free software: you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published
#  by the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  cysignals is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with cysignals.  If not, see <http://www.gnu.org/licenses/>.
#
#*****************************************************************************

from posix.time cimport (setitimer, itimerval, ITIMER_REAL,
        time_t, suseconds_t)

from .signals import AlarmInterrupt


def alarm(seconds):
    """
    Raise an :class:`AlarmInterrupt` exception in a given number of
    seconds. This is useful for automatically interrupting long
    computations and can be trapped using exception handling.

    Use :func:`cancel_alarm` to cancel a previously scheduled alarm.

    INPUT:

    -  ``seconds`` -- positive number, may be floating point

    OUTPUT: None

    EXAMPLES::

        >>> from cysignals.alarm import alarm, AlarmInterrupt
        >>> from time import sleep
        >>> try:
        ...     alarm(0.5)
        ...     sleep(2)
        ... except AlarmInterrupt:
        ...     print("alarm!")
        alarm!
        >>> alarm(0)
        Traceback (most recent call last):
        ...
        ValueError: alarm() time must be positive

    """
    if seconds <= 0:
        raise ValueError("alarm() time must be positive")
    setitimer_real(seconds)


def cancel_alarm():
    """
    Cancel a previously scheduled alarm (if any) set by :func:`alarm`.

    OUTPUT: None

    EXAMPLES::

        >>> from cysignals.alarm import alarm, cancel_alarm
        >>> from time import sleep
        >>> alarm(0.5)
        >>> cancel_alarm()
        >>> cancel_alarm()  # Calling more than once doesn't matter
        >>> sleep(0.6)      # sleep succeeds

    """
    setitimer_real(0)


cdef inline void setitimer_real(double x):
    cdef itimerval itv
    itv.it_interval.tv_sec = 0
    itv.it_interval.tv_usec = 0
    itv.it_value.tv_sec = <time_t>x  # Truncate
    itv.it_value.tv_usec = <suseconds_t>((x - itv.it_value.tv_sec) * 1e6)
    setitimer(ITIMER_REAL, &itv, NULL)
