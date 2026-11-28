import faulthandler
import gc
import os

import pytest

import pydatachannel

HANG_TIMEOUT = 60


def pytest_configure(config):
  global _stderr
  _stderr = os.dup(2)  # the real stderr, before pytest's capture swaps fd 2


# A deadlock that holds the GIL stops every Python-level timeout. faulthandler's watchdog is a C thread that needs no
# GIL: it dumps every thread's stack and kills the process.
@pytest.fixture(autouse=True)
def hang_watchdog():
  faulthandler.dump_traceback_later(HANG_TIMEOUT, exit=True, file=_stderr)
  yield
  # cleanup() only completes once every native PeerConnection is destroyed and every libdatachannel thread has exited
  gc.collect()
  assert pydatachannel.cleanup(10)
  faulthandler.cancel_dump_traceback_later()
