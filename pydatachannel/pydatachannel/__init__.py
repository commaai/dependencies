"""
pydatachannel: asyncio wrapper over a minimal libdatachannel binding (pydatachannel._rtc).

The native module never calls into Python. It queues events and signals an fd; this module watches that fd with
loop.add_reader and dispatches events on the loop thread. Every callback registered here runs on the loop thread.
"""
import asyncio
import logging
from typing import Callable, Dict, List, Optional, Union

from pydatachannel._rtc import cleanup, parse_sdp
from pydatachannel import _rtc

__all__ = ["PeerConnection", "DataChannel", "Track", "Message", "parse_sdp", "cleanup"]

logger = logging.getLogger("pydatachannel")

Message = Union[bytes, str]
CLOCK_RATE = {"video": 90000, "audio": 48000}


class _Channel:
  """A data channel or track. Callbacks are plain attributes: an event "x" calls self.on_x if it is set."""

  def __init__(self, pc: "PeerConnection", oid: int):
    self._pc = pc
    self._id = oid
    self.on_open: Optional[Callable[[], None]] = None
    self.on_closed: Optional[Callable[[], None]] = None

  def is_open(self) -> bool:
    return self._pc._native.is_open(self._id)


class DataChannel(_Channel):
  def __init__(self, pc: "PeerConnection", oid: int, label: str):
    super().__init__(pc, oid)
    self.label = label
    self.on_message: Optional[Callable[[Message], None]] = None

  def send(self, data: Message) -> bool:
    return self._pc._native.send(self._id, data)

  def max_message_size(self) -> int:
    return self._pc._native.max_message_size(self._id)


class Track(_Channel):
  """An H264 video or Opus audio track, sending or receiving."""

  def __init__(self, pc: "PeerConnection", oid: int, mid: str, kind: str, ssrc: Optional[int]):
    super().__init__(pc, oid)
    self.mid = mid
    self.kind = kind
    self.ssrc = ssrc  # local SSRC, send tracks only
    # raw RTCP from the remote: receiver reports on send tracks, sender reports on receive tracks
    self.on_rtcp: Optional[Callable[[bytes], None]] = None
    # receive tracks: fn(data, rtp_timestamp) for each H264 access unit (Annex B) or Opus packet. At most 8 frames per
    # track wait for the loop; when it falls behind, newer frames are dropped.
    self.on_frame: Optional[Callable[[bytes, int], None]] = None
    # video send tracks: PLI/FIR from the remote
    self.on_keyframe_request: Optional[Callable[[], None]] = None

  def request_keyframe(self) -> bool:
    """Send a PLI to the remote, video receive tracks only."""
    return not self._pc.is_closed() and self._pc._native.request_keyframe(self._id)

  def send_frame(self, data: bytes, pts: int) -> None:
    """One H264 access unit (Annex B) or Opus packet; pts in RTP clock units (video 90 kHz, audio 48 kHz)."""
    self._pc._native.send_frame(self._id, data, pts / CLOCK_RATE[self.kind])


class PeerConnection:
  def __init__(self, ice_servers: List[str], max_message_size: int, bind_address: Optional[str] = None):
    self._native = _rtc.PeerConnection(ice_servers, max_message_size, bind_address)
    self._channels: Dict[int, _Channel] = {}
    self._state = "new"
    self._gathering_state = "new"
    self._closed = False
    self.on_state_change: Optional[Callable[[str], None]] = None
    self.on_gathering_state_change: Optional[Callable[[str], None]] = None
    self.on_data_channel: Optional[Callable[[DataChannel], None]] = None

    self._loop = asyncio.get_running_loop()
    self._fd = self._native.event_fd
    self._loop.add_reader(self._fd, self._drain)

  # -- signaling (full SDP, no trickle)

  def set_remote_description(self, sdp: str, sdp_type: str) -> None:
    self._native.set_remote_description(sdp, sdp_type)

  def set_local_description(self, sdp_type: str) -> None:
    self._native.set_local_description(sdp_type)

  def local_description(self) -> Optional[tuple]:
    """(sdp, type), or None."""
    return self._native.local_description()

  def remote_description(self) -> Optional[tuple]:
    return self._native.remote_description()

  # State as of the last dispatched event, so callbacks see a view consistent with event order.
  def state(self) -> str:
    return "closed" if self._closed else self._state

  def gathering_state(self) -> str:
    return self._gathering_state

  # -- channels / tracks

  def create_data_channel(self, label: str) -> DataChannel:
    channel = DataChannel(self, self._native.create_data_channel(label), label)
    self._channels[channel._id] = channel
    return channel

  # Every media section, ours or in the remote's offer (see parse_sdp), needs one of these: there is no on_track.
  def add_send_track(self, kind: str, mid: str, payload_type: int, track_id: str) -> Track:
    """kind "video": H264, kind "audio": Opus. The mid and payload type come from the remote's offer (see parse_sdp)."""
    return self._add_track(kind, True, mid, payload_type, track_id)

  def add_recv_track(self, kind: str, mid: str, payload_type: int) -> Track:
    """kind "video": H264, kind "audio": Opus. Frames arrive via Track.on_frame."""
    return self._add_track(kind, False, mid, payload_type, "")

  def _add_track(self, kind: str, send: bool, mid: str, payload_type: int, track_id: str) -> Track:
    oid, ssrc = self._native.add_track(kind, send, mid, payload_type, track_id)
    track = self._channels[oid] = Track(self, oid, mid, kind, ssrc or None)
    return track

  # -- lifecycle

  def is_closed(self) -> bool:
    return self._closed

  def _detach(self) -> bool:
    if self._closed:
      return False
    self._closed = True
    self._loop.remove_reader(self._fd)
    self._channels.clear()
    return True

  def close(self) -> None:
    """
    Close and release every native object; no callbacks run once this starts. Blocks (GIL released) for up to ~2s
    for a graceful SCTP shutdown, so messages sent just before still reach the remote.
    """
    if self._detach():
      self._native.close()

  async def aclose(self) -> None:
    """Like close(), with the blocking part in a thread so the loop keeps running."""
    if self._detach():
      await asyncio.to_thread(self._native.close)

  # -- event dispatch (loop thread only)

  def _drain(self) -> None:
    for kind, oid, *args in self._native.poll_events():
      if self._closed:  # a callback closed us: drop the rest of the batch
        return
      try:
        self._handle(kind, oid, args)
      except Exception:
        logger.exception("Error handling rtc event %s", kind)

  def _handle(self, kind: str, oid: int, args: list) -> None:
    if kind == "state":
      self._state = args[0]
      fn = self.on_state_change
    elif kind == "gathering":
      self._gathering_state = args[0]
      fn = self.on_gathering_state_change
    elif kind == "datachannel":
      args = [DataChannel(self, oid, args[0])]
      self._channels[oid] = args[0]
      fn = self.on_data_channel
    else:
      fn = getattr(self._channels.get(oid), "on_" + kind, None)
    if fn is not None:
      fn(*args)


def smoketest() -> None:
  """Two peers over loopback: a data channel opens and a message makes the round trip."""
  import gc

  async def run():
    a, b = PeerConnection([], 1 << 16), PeerConnection([], 1 << 16)
    echoed = asyncio.get_running_loop().create_future()
    b.on_data_channel = lambda channel: setattr(channel, "on_message", channel.send)  # echo
    channel = a.create_data_channel("smoketest")
    channel.on_open = lambda: channel.send(b"ping")
    channel.on_message = echoed.set_result
    for src, dst, sdp_type in ((a, b, "offer"), (b, a, "answer")):
      src.set_local_description(sdp_type)
      while src.gathering_state() != "complete":
        await asyncio.sleep(0.01)
      dst.set_remote_description(src.local_description()[0], sdp_type)
    assert await asyncio.wait_for(echoed, 10) == b"ping"
    await asyncio.gather(a.aclose(), b.aclose())

  asyncio.run(run())
  gc.collect()
  assert cleanup(10), "libdatachannel did not shut down"
