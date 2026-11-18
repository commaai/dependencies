"""
The binding must never deadlock. These tests have no interesting assertions: they pass by finishing. A hang is killed
by the watchdog in conftest.py, which also checks after every test that libdatachannel could shut down completely.
"""
import asyncio
import os
import threading
import time

import pytest

from pydatachannel import PeerConnection

ACCESS_UNIT = b"\x00\x00\x00\x01\x65" + b"\x01" * 3000  # H264 IDR, larger than one RTP packet
ROUNDS = 5  # deadlocks are races: every scenario runs a few times


async def connect():
  """Two connected peers over loopback: a data channel each way, and a video track from b to a."""
  a, b = PeerConnection([], 1 << 20), PeerConnection([], 1 << 20)
  remote_channels = []
  b.on_data_channel = remote_channels.append
  chan_a = a.create_data_channel("data")
  track_a = a.add_recv_track("video", "video", 96)
  track_b = None
  for src, dst, sdp_type in ((a, b, "offer"), (b, a, "answer")):
    if src is b:
      track_b = b.add_send_track("video", "video", 96, "track")
    src.set_local_description(sdp_type)
    while src.gathering_state() != "complete":
      await asyncio.sleep(0.01)
    dst.set_remote_description(src.local_description()[0], sdp_type)
  while not (remote_channels and remote_channels[0].is_open() and chan_a.is_open() and track_a.is_open() and track_b.is_open()):
    await asyncio.sleep(0.01)
  return a, b, chan_a, remote_channels[0], track_a, track_b


def hammer(*fns):
  """Call fns from a thread until the returned stop() is called. Calls on a closed peer raise, which is fine."""
  stopped = threading.Event()

  def run():
    while not stopped.is_set():
      for fn in fns:
        try:
          fn()
        except RuntimeError:
          pass
      time.sleep(0.0005)

  thread = threading.Thread(target=run)
  thread.start()
  return lambda: (stopped.set(), thread.join())


def rounds(scenario, *args):
  for _ in range(ROUNDS):
    asyncio.run(scenario(*args))


def test_library_threads_never_need_the_gil():
  async def scenario():
    a, b, _, chan_b, _, track_b = await connect()
    for i in range(100):
      chan_b.send(b"x")
      track_b.send_frame(ACCESS_UNIT, i * 3000)
    deadline = time.monotonic() + 0.5
    while time.monotonic() < deadline:  # hold the GIL and block the loop: everything must still arrive natively
      pass
    kinds = [event[0] for event in a._native.poll_events()]
    assert kinds.count("message") == 100
    assert kinds.count("frame") == 8  # the rest were dropped, the queue is bounded
    a.close()
    b.close()

  rounds(scenario)


def test_calls_and_close_from_inside_callbacks():
  async def scenario():
    a, b, chan_a, chan_b, _, _ = await connect()
    done = asyncio.get_running_loop().create_future()

    def on_message(msg):
      if int(msg) < 200:
        chan_a.send(str(int(msg) + 1))
      else:
        a.close()
        b.close()
        done.set_result(None)

    chan_a.on_message = on_message
    chan_b.on_message = chan_b.send  # echo
    chan_a.send("0")
    await done

  rounds(scenario)


@pytest.mark.parametrize("sync", [True, False])
def test_close_while_threads_call_in_and_events_flood(sync):
  async def scenario():
    a, b, chan_a, chan_b, track_a, track_b = await connect()
    stops = [hammer(lambda: chan_a.send(b"x"), lambda: chan_b.send("x"), lambda: track_b.send_frame(ACCESS_UNIT, 0),
                    chan_a.is_open, track_a.request_keyframe, a.local_description, chan_b.max_message_size) for _ in range(4)]
    await asyncio.sleep(0.2)
    if sync:
      a.close()
      b.close()
    else:
      await asyncio.gather(a.aclose(), b.aclose())
    for stop in stops:
      stop()

  rounds(scenario)


# callbacks are plain attributes: replacing one while events flood must be safe (libdatachannel-py deadlocks here)
def test_replace_callbacks_while_events_flood():
  async def scenario():
    a, b, chan_a, chan_b, _, _ = await connect()
    stop = hammer(lambda: chan_b.send(b"x"))
    received = []
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
      chan_a.on_message = received.append
      await asyncio.sleep(0)
    stop()
    assert received
    a.close()
    b.close()

  rounds(scenario)


def test_reconnect_100_times():
  async def scenario():
    for i in range(100):
      a, b, chan_a, chan_b, _, track_b = await connect()
      chan_a.send(b"x")
      chan_b.send("x")
      track_b.send_frame(ACCESS_UNIT, 0)
      if i % 2:
        a.close()
        b.close()
      else:
        await asyncio.gather(a.aclose(), b.aclose())

  asyncio.run(scenario())


def test_never_closed():
  async def scenario():
    _, _, chan_a, chan_b, _, track_b = await connect()
    stop = hammer(lambda: chan_a.send(b"x"), lambda: chan_b.send("x"), lambda: track_b.send_frame(ACCESS_UNIT, 0))
    await asyncio.sleep(0.1)
    stop()  # the peers are destroyed by the garbage collector, still connected and with events pending

  rounds(scenario)


def test_close_releases_fds_without_gc():
  async def scenario():
    kept = []  # closed peers stay referenced, as when an application holds on to them
    for i in range(21):
      if i == 1:  # after the first round initialized libdatachannel's global threads and sockets
        before = len(os.listdir("/dev/fd"))
      a, b, *_ = await connect()
      await asyncio.gather(a.aclose(), b.aclose())
      kept.append((a, b))
    assert len(os.listdir("/dev/fd")) - before < 10

  asyncio.run(scenario())
