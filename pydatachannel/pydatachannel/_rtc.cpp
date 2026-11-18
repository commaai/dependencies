// pydatachannel: a minimal libdatachannel binding for asyncio: data channels, H264 video and Opus audio tracks.
//
// THE ONE RULE: libdatachannel threads never touch Python.
//
// Invariants:
//  1. No code running on a libdatachannel thread calls the Python C-API or takes the GIL. This file never uses
//     gil_scoped_acquire; the GIL is only ever *released* from functions called by Python.
//  2. Native callback lambdas capture only shared_ptr<EventQueue> and integer ids. Never nb::object, never `this`.
//  3. EventQueue::mutex is a leaf lock: nothing else is called while it is held.
//  4. Every Python-callable function that may touch libdatachannel copies the shared_ptrs it needs while holding the
//     GIL, then releases the GIL before calling into libdatachannel.
//  5. C++ owns every rtc:: object in an id-keyed map; close() clears it. Python holds only ints. The map is only
//     touched by Python-called functions while the GIL is held, so the GIL protects it.
//  6. No Python finalizer is required for correctness.

#include <nanobind/nanobind.h>
#include <nanobind/stl/optional.h>
#include <nanobind/stl/string.h>
#include <nanobind/stl/tuple.h>
#include <nanobind/stl/vector.h>

#include <rtc/rtc.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <fcntl.h>
#include <map>
#include <mutex>
#include <random>
#include <sstream>
#include <string_view>
#include <unistd.h>

namespace nb = nanobind;
using namespace nb::literals;

namespace {

constexpr auto GRACEFUL_CLOSE_TIMEOUT = std::chrono::seconds(2);
constexpr size_t MAX_PENDING_FRAMES_PER_TRACK = 8;
constexpr uint32_t VIDEO_CLOCK_RATE = 90000;
constexpr uint32_t AUDIO_CLOCK_RATE = 48000;

template <class T> std::string to_str(const T &v) {
  std::ostringstream s;
  s << v;
  return s.str();
}

// ---------------------------------------------------------------------------------------------------------------------
// Event queue: the only thing shared between libdatachannel threads and Python.

// Delivered to Python by poll_events(). id 0 is the PeerConnection itself.
//   ("state", 0, str)  ("gathering", 0, str)
//   ("datachannel", id, label)  ("track", id, mid, "audio" | "video")   created by the remote
//   ("open", id)  ("closed", id)  ("message", id, bytes | str)          data channels; on a send track, the remote's RTCP
//   ("keyframe_request", id)                                            PLI/FIR on a send track
//   ("frame", id, bytes, rtp_timestamp)                                 receive tracks
struct Event {
  const char *kind;
  int id = 0;
  std::optional<rtc::message_variant> payload;  // str: state / label / mid / text message, bytes: message / RTCP / frame
  std::shared_ptr<rtc::Channel> object;         // "datachannel" / "track": the remote-created object, adopted on the loop thread
  uint32_t timestamp = 0;                       // "frame": RTP timestamp
  std::string media;                            // "track": "audio" | "video"
};

class EventQueue {
 public:
  EventQueue() {
    if (::pipe(fds_) != 0) throw std::runtime_error("pipe failed");
    for (int fd : fds_) {
      ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK);
      ::fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
  }

  ~EventQueue() {
    for (int fd : fds_) ::close(fd);
  }

  EventQueue(const EventQueue &) = delete;
  EventQueue &operator=(const EventQueue &) = delete;

  int fd() const { return fds_[0]; }
  int next_id() { return next_id_++; }

  // A remote offer creates a track (onTrack, on a library thread) before we add ours with the same mid, and
  // libdatachannel reuses that underlying track, so both must share one id.
  int id_for_mid(const std::string &mid) {
    std::lock_guard lock(mutex_);
    auto [it, inserted] = mid_ids_.try_emplace(mid, 0);
    if (inserted) it->second = next_id();
    return it->second;
  }

  void push(Event ev) {
    bool was_empty;
    {
      std::lock_guard lock(mutex_);
      if (shut_) return;
      if (std::string_view(ev.kind) == "frame" && pending_frames_[ev.id]++ >= MAX_PENDING_FRAMES_PER_TRACK) {
        // the loop is behind: drop this track's oldest pending frame
        for (auto it = events_.begin(); it != events_.end(); ++it) {
          if (it->id == ev.id && std::string_view(it->kind) == "frame") {
            events_.erase(it);
            --pending_frames_[ev.id];
            break;
          }
        }
      }
      if (std::string_view(ev.kind) == "state" && std::get<std::string>(*ev.payload) == "closed") {
        closed_ = true;
        closed_cv_.notify_all();
      }
      was_empty = events_.empty();
      events_.push_back(std::move(ev));
    }
    char one = 1;
    if (was_empty) (void)!::write(fds_[1], &one, 1);
  }

  std::deque<Event> drain() {
    char buf[64];
    while (::read(fds_[0], buf, sizeof(buf)) > 0) {
    }
    std::deque<Event> out;
    std::lock_guard lock(mutex_);
    out.swap(events_);
    pending_frames_.clear();
    return out;
  }

  // Wait (GIL must be released by the caller) until the "closed" state event was pushed.
  void wait_closed(std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex_);
    closed_cv_.wait_for(lock, timeout, [this] { return closed_; });
  }

  // Stop accepting events and drop the undelivered ones (with any rtc:: objects they hold, outside the lock).
  void shutdown() {
    {
      std::lock_guard lock(mutex_);
      shut_ = true;
    }
    drain();
  }

 private:
  int fds_[2];  // self-pipe: readable while events are pending
  std::atomic<int> next_id_{1};
  std::mutex mutex_;  // leaf lock
  std::condition_variable closed_cv_;
  std::deque<Event> events_;
  std::map<int, size_t> pending_frames_;
  std::map<std::string, int> mid_ids_;
  bool closed_ = false;
  bool shut_ = false;
};

using QueuePtr = std::shared_ptr<EventQueue>;

// Every lambda here captures only `q` (shared_ptr<EventQueue>) and `id` (int).
// messages=false drains a track's messages without delivering them (receive tracks: frames come from onFrame).
void wire(rtc::Channel &ch, const QueuePtr &q, int id, bool messages = true) {
  ch.onOpen([q, id] { q->push({"open", id}); });
  ch.onClosed([q, id] { q->push({"closed", id}); });
  if (messages) {
    ch.onMessage([q, id](rtc::message_variant msg) { q->push({"message", id, std::move(msg)}); });
  } else {
    ch.onMessage([](rtc::message_variant) {});
  }
}

// ---------------------------------------------------------------------------------------------------------------------

class PeerConnection {
 public:
  PeerConnection(const std::vector<std::string> &ice_servers, size_t max_message_size, std::optional<std::string> bind_address)
      : q_(std::make_shared<EventQueue>()) {
    rtc::Configuration config;
    for (const auto &url : ice_servers) config.iceServers.emplace_back(url);
    config.maxMessageSize = max_message_size;
    config.bindAddress = std::move(bind_address);
    config.disableAutoNegotiation = true;  // the answer is created after the send tracks are added

    nb::gil_scoped_release release;
    auto pc = std::make_shared<rtc::PeerConnection>(config);
    QueuePtr q = q_;
    pc->onStateChange([q](rtc::PeerConnection::State s) { q->push({"state", 0, to_str(s)}); });
    pc->onGatheringStateChange([q](rtc::PeerConnection::GatheringState s) { q->push({"gathering", 0, to_str(s)}); });
    pc->onDataChannel([q](std::shared_ptr<rtc::DataChannel> dc) {
      int id = q->next_id();
      wire(*dc, q, id);
      q->push({"datachannel", id, dc->label(), dc});
    });
    pc->onTrack([q](std::shared_ptr<rtc::Track> t) {
      int id = q->id_for_mid(t->mid());
      wire(*t, q, id, false);
      Event ev{"track", id, t->mid(), t};
      ev.media = t->description().type();
      q->push(std::move(ev));
    });
    pc_ = std::move(pc);
  }

  ~PeerConnection() { close(); }  // safe with the GIL held: no libdatachannel thread ever waits on the GIL

  int event_fd() const { return q_->fd(); }

  nb::list poll_events() {
    nb::list out;
    for (auto &ev : q_->drain()) {
      if (ev.object && pc_) adopt(ev.id, std::move(ev.object));
      if (!ev.payload) {
        out.append(nb::make_tuple(ev.kind, ev.id));
      } else if (auto *s = std::get_if<std::string>(&*ev.payload)) {
        append(out, ev, *s);
      } else {
        auto &b = std::get<rtc::binary>(*ev.payload);
        append(out, ev, nb::bytes(reinterpret_cast<const char *>(b.data()), b.size()));
      }
    }
    return out;
  }

  void set_remote_description(const std::string &sdp, const std::string &type) {
    auto pc = get_pc();
    nb::gil_scoped_release release;
    pc->setRemoteDescription(rtc::Description(sdp, type));
  }

  void set_local_description(const std::string &type) {
    auto pc = get_pc();
    nb::gil_scoped_release release;
    pc->setLocalDescription(rtc::Description::stringToType(type));
  }

  std::optional<std::tuple<std::string, std::string>> local_description() { return description(true); }
  std::optional<std::tuple<std::string, std::string>> remote_description() { return description(false); }

  // An H264 video or Opus audio track. A send track packetizes what send_frame() is given, sends sender reports and
  // answers NACKs and keyframe requests; a receive track delivers depacketized frames as "frame" events.
  // Returns (id, local ssrc), ssrc 0 for a receive track.
  std::tuple<int, uint32_t> add_track(const std::string &kind, bool send, const std::string &mid, int payload_type,
                                      const std::string &track_id) {
    bool video = kind == "video";
    if (!video && kind != "audio") throw std::invalid_argument("kind must be 'video' or 'audio'");
    auto pc = get_pc();
    QueuePtr q = q_;
    int id = q->id_for_mid(mid);
    std::shared_ptr<rtc::Track> track;
    uint32_t ssrc = 0;
    {
      nb::gil_scoped_release release;
      auto direction = send ? rtc::Description::Direction::SendOnly : rtc::Description::Direction::RecvOnly;
      rtc::Description::Video video_media(mid, direction);
      rtc::Description::Audio audio_media(mid, direction);
      video_media.addH264Codec(payload_type);
      audio_media.addOpusCodec(payload_type);
      rtc::Description::Media &media = video ? static_cast<rtc::Description::Media &>(video_media) : audio_media;
      if (send) {
        ssrc = std::max<uint32_t>(1, std::random_device{}());
        media.addSSRC(ssrc, "pydatachannel", track_id, track_id);
      }
      track = pc->addTrack(media);

      std::shared_ptr<rtc::MediaHandler> handler;
      if (send) {
        // the config randomizes the initial sequence number and timestamp
        auto config = std::make_shared<rtc::RtpPacketizationConfig>(ssrc, "pydatachannel", static_cast<uint8_t>(payload_type),
                                                                    video ? VIDEO_CLOCK_RATE : AUDIO_CLOCK_RATE);
        if (video) handler = std::make_shared<rtc::H264RtpPacketizer>(rtc::NalUnit::Separator::LongStartSequence, config, 1200);
        else handler = std::make_shared<rtc::OpusRtpPacketizer>(config);
        handler->addToChain(std::make_shared<rtc::RtcpSrReporter>(config));
        handler->addToChain(std::make_shared<rtc::PliHandler>([q, id] { q->push({"keyframe_request", id}); }));
        handler->addToChain(std::make_shared<rtc::RtcpNackResponder>());
      } else {
        if (video) handler = std::make_shared<rtc::H264RtpDepacketizer>(rtc::NalUnit::Separator::StartSequence);
        else handler = std::make_shared<rtc::OpusRtpDepacketizer>();
        handler->addToChain(std::make_shared<rtc::RtcpReceivingSession>());
        track->onFrame([q, id](rtc::binary data, rtc::FrameInfo info) {
          Event ev{"frame", id, std::move(data)};
          ev.timestamp = info.timestamp;
          q->push(std::move(ev));
        });
      }
      track->setMediaHandler(handler);
      wire(*track, q, id, send);  // messages on a send track are the remote's RTCP (receiver reports etc.)
    }
    adopt(id, std::move(track), true);
    return {id, ssrc};
  }

  bool request_keyframe(int id) {
    auto it = objects_.find(id);
    auto track = it == objects_.end() ? nullptr : std::dynamic_pointer_cast<rtc::Track>(it->second);
    if (!track) return false;
    nb::gil_scoped_release release;
    return track->requestKeyframe();
  }

  int create_data_channel(const std::string &label) {
    auto pc = get_pc();
    QueuePtr q = q_;
    int id = q->next_id();
    std::shared_ptr<rtc::DataChannel> dc;
    {
      nb::gil_scoped_release release;
      dc = pc->createDataChannel(label);
      wire(*dc, q, id);
    }
    objects_[id] = std::move(dc);
    return id;
  }

  // video: one Annex B access unit, audio: one Opus packet. pts in seconds since the start of the stream.
  void send_frame(int id, nb::bytes data, double pts) {
    auto track = get<rtc::Track>(id);
    const auto *p = reinterpret_cast<const rtc::byte *>(data.c_str());
    rtc::binary buf(p, p + data.size());
    nb::gil_scoped_release release;
    track->sendFrame(std::move(buf), rtc::FrameInfo(std::chrono::duration<double>(pts)));
  }

  bool send_bytes(int id, nb::bytes data) {
    auto dc = get<rtc::DataChannel>(id);
    const auto *p = reinterpret_cast<const rtc::byte *>(data.c_str());
    rtc::binary buf(p, p + data.size());
    nb::gil_scoped_release release;
    return dc->send(std::move(buf));
  }

  bool send_str(int id, std::string data) {
    auto dc = get<rtc::DataChannel>(id);
    nb::gil_scoped_release release;
    return dc->send(std::move(data));
  }

  size_t max_message_size(int id) {
    auto dc = get<rtc::DataChannel>(id);
    nb::gil_scoped_release release;
    return dc->maxMessageSize();
  }

  bool is_open(int id) {
    auto it = objects_.find(id);
    if (it == objects_.end()) return false;
    auto ch = it->second;
    nb::gil_scoped_release release;
    return ch->isOpen();
  }

  void close() {
    // Take ownership of everything (GIL held, so the map is ours), then tear down with the GIL released.
    auto pc = std::move(pc_);
    if (!pc) return;
    auto objects = std::move(objects_);
    auto aliases = std::move(aliases_);
    objects_.clear();
    aliases_.clear();
    QueuePtr q = q_;

    nb::gil_scoped_release release;
    pc->close();
    q->wait_closed(GRACEFUL_CLOSE_TIMEOUT);
    // Dropping the wrappers drops our callbacks (~rtc::Channel resets them on the shared impl), so no lambda or queue
    // ref outlives the session. libdatachannel resets the PeerConnection's own callbacks when it reaches Closed.
    objects.clear();
    aliases.clear();
    pc.reset();     // ~rtc::PeerConnection forces remote close if graceful close timed out
    q->shutdown();  // rtc:: objects in undelivered events are destroyed here, outside the queue lock
  }

 private:
  template <class P> static void append(nb::list &out, const Event &ev, P payload) {
    std::string_view kind(ev.kind);
    if (kind == "frame") out.append(nb::make_tuple(ev.kind, ev.id, payload, ev.timestamp));
    else if (kind == "track") out.append(nb::make_tuple(ev.kind, ev.id, payload, ev.media));
    else out.append(nb::make_tuple(ev.kind, ev.id, payload));
  }

  // Own `obj` under `id`. A remote-created track and ours for the same mid are two wrappers over one libdatachannel
  // track: ours (`replace`) takes the id, the other is kept alive in aliases_ until close(), because destroying any
  // rtc::Track wrapper resets *all* callbacks on the shared track.
  void adopt(int id, std::shared_ptr<rtc::Channel> obj, bool replace = false) {
    auto &slot = objects_[id];
    if (!slot) {
      slot = std::move(obj);
    } else if (replace) {
      aliases_.push_back(std::move(slot));
      slot = std::move(obj);
    } else {
      aliases_.push_back(std::move(obj));
    }
  }

  std::shared_ptr<rtc::PeerConnection> get_pc() {
    if (!pc_) throw std::runtime_error("PeerConnection is closed");
    return pc_;
  }

  template <class T> std::shared_ptr<T> get(int id) {
    auto it = objects_.find(id);
    auto obj = it == objects_.end() ? nullptr : std::dynamic_pointer_cast<T>(it->second);
    if (!obj) throw std::runtime_error("channel or track is closed");
    return obj;
  }

  std::optional<std::tuple<std::string, std::string>> description(bool local) {
    auto pc = pc_;
    if (!pc) return std::nullopt;
    std::optional<rtc::Description> d;
    {
      nb::gil_scoped_release release;
      d = local ? pc->localDescription() : pc->remoteDescription();
    }
    if (!d) return std::nullopt;
    return std::make_tuple(std::string(*d), d->typeString());
  }

  QueuePtr q_;
  std::shared_ptr<rtc::PeerConnection> pc_;
  std::map<int, std::shared_ptr<rtc::Channel>> objects_;  // data channels and tracks
  std::vector<std::shared_ptr<rtc::Channel>> aliases_;
};

// ---------------------------------------------------------------------------------------------------------------------

// {"media": [(kind, mid, direction, {pt: codec})], "has_application": bool}
nb::dict parse_sdp(const std::string &sdp) {
  rtc::Description desc(sdp);
  nb::list media_list;
  bool has_application = false;
  for (int i = 0; i < desc.mediaCount(); ++i) {
    auto entry = desc.media(i);
    auto *media = std::get_if<rtc::Description::Media *>(&entry);
    if (!media) {
      has_application = true;
      continue;
    }
    nb::dict codecs;
    for (int pt : (*media)->payloadTypes()) {
      try {
        codecs[nb::int_(pt)] = (*media)->rtpMap(pt)->format;
      } catch (const std::exception &) {  // payload type without an rtpmap line
      }
    }
    media_list.append(nb::make_tuple((*media)->type(), (*media)->mid(), to_str((*media)->direction()), codecs));
  }
  nb::dict out;
  out["media"] = media_list;
  out["has_application"] = has_application;
  return out;
}

bool cleanup(double timeout) {
  nb::gil_scoped_release release;
  return rtc::Cleanup().wait_for(std::chrono::duration<double>(timeout)) == std::future_status::ready;
}

}  // namespace

NB_MODULE(_rtc, m) {
  m.doc() = "Minimal libdatachannel binding. libdatachannel threads never touch Python.";

  nb::class_<PeerConnection>(m, "PeerConnection")
      .def(nb::init<const std::vector<std::string> &, size_t, std::optional<std::string>>(), "ice_servers"_a,
           "max_message_size"_a, "bind_address"_a = nb::none())
      .def_prop_ro("event_fd", &PeerConnection::event_fd)
      .def("poll_events", &PeerConnection::poll_events)
      .def("set_remote_description", &PeerConnection::set_remote_description, "sdp"_a, "sdp_type"_a)
      .def("set_local_description", &PeerConnection::set_local_description, "sdp_type"_a)
      .def("local_description", &PeerConnection::local_description)
      .def("remote_description", &PeerConnection::remote_description)
      .def("add_track", &PeerConnection::add_track, "kind"_a, "send"_a, "mid"_a, "payload_type"_a, "track_id"_a)
      .def("create_data_channel", &PeerConnection::create_data_channel, "label"_a)
      .def("send_frame", &PeerConnection::send_frame, "oid"_a, "data"_a, "pts"_a)
      .def("send", &PeerConnection::send_bytes, "oid"_a, "data"_a)
      .def("send", &PeerConnection::send_str, "oid"_a, "data"_a)
      .def("max_message_size", &PeerConnection::max_message_size, "oid"_a)
      .def("request_keyframe", &PeerConnection::request_keyframe, "oid"_a)
      .def("is_open", &PeerConnection::is_open, "oid"_a)
      .def("close", &PeerConnection::close);

  m.def("parse_sdp", &parse_sdp, "sdp"_a);
  m.def("cleanup", &cleanup, "timeout"_a = 10.0);
}
