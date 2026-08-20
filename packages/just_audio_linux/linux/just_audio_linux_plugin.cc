#include "include/just_audio_linux/just_audio_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>

#include <cmath>
#include <cstring>
#include <map>
#include <memory>
#include <string>

// The Linux side of just_audio: one GStreamer `playbin` per player, addressed
// over a pair of channels named after the player's id.
//
// playbin rather than a hand-built pipeline because the app cannot know what it
// is about to play: the recorder produces whatever the platform gave it, and
// playbin picks the demuxer and decoder to match. Everything below is the
// plumbing around it — a bus watch that turns GStreamer's messages into the
// events just_audio expects, and a timer so a scrub bar has a position to draw.
//
// Threading: every callback here runs on the GLib main context, which is the
// thread the Flutter engine dispatches platform messages on. Nothing in this
// file touches a channel from anywhere else, so there is no lock.

namespace {

// How often a playing player reports its position. Fast enough that a scrub bar
// moves smoothly (five updates a second), slow enough that a voice comment does
// not wake the UI thread for nothing.
constexpr guint kPositionIntervalMs = 200;

// How long load() will wait for the pipeline to pre-roll. Reached only by a
// file GStreamer cannot make sense of — a local voice comment pre-rolls in
// milliseconds — and bounded because this runs on the platform thread.
constexpr GstClockTime kPrerollTimeout = 5 * GST_SECOND;

// playbin's `flags`, audio only. The values are GstPlayFlags, spelled out here
// because that enum lives in gst-plugins-base's headers and this plugin links
// against gstreamer-1.0 alone.
//
// This is an audio player, and playbin's default flags are not: they also
// enable the video and subtitle chains, so a "voice comment" whose bytes are
// really an MP4 with a video track would be handed to the video decoders and
// pop an autovideosink window over the app. Those bytes come from the server,
// which makes the whole video and subtitle decoding surface reachable by
// anyone who can attach a comment. Audio is the only chain this plugin has a
// use for; SOFT_VOLUME is what makes the `volume` property work regardless of
// what the audio sink supports.
constexpr guint kPlayFlagAudio = 0x002;
constexpr guint kPlayFlagSoftVolume = 0x010;
constexpr guint kAudioOnlyPlayFlags = kPlayFlagAudio | kPlayFlagSoftVolume;

// The largest position, in microseconds, that can still be converted to
// GStreamer's nanoseconds. Positions arrive over a method channel, so they are
// whatever the caller sent — and `position * GST_USECOND` past this point
// wraps around instead of seeking, which is how a scrub lands somewhere the
// caller never asked for. Roughly 292 000 years; no clip comes near it.
constexpr gint64 kMaxPositionUs = G_MAXINT64 / static_cast<gint64>(GST_USECOND);

// Speed is a seek rate. Non-finite or non-positive values are not a slower or
// faster clip, they are a malformed seek, and the ceiling keeps a stray value
// from asking the decoder for an absurd rate.
constexpr double kMaxSpeed = 16.0;

// Mirrors ProcessingStateMessage in just_audio_platform_interface. The values
// are an index into a Dart enum, so they are ordering, not decoration.
enum class ProcessingState {
  kIdle = 0,
  kLoading = 1,
  kBuffering = 2,
  kReady = 3,
  kCompleted = 4,
};

// One player: a pipeline, its two channels, and the little state the events
// need. Owned by the plugin's map and destroyed on disposePlayer.
class Player {
 public:
  Player(FlPluginRegistrar* registrar, const std::string& id)
      : messenger_(fl_plugin_registrar_get_messenger(registrar)),
        method_name_("hinata/just_audio_linux/methods/" + id),
        event_name_("hinata/just_audio_linux/events/" + id) {
    playbin_ = gst_element_factory_make("playbin", nullptr);
    if (playbin_ != nullptr) {
      g_object_set(playbin_, "flags", kAudioOnlyPlayFlags, nullptr);
    }

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    methods_ = fl_method_channel_new(messenger_, method_name_.c_str(),
                                     FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(methods_, MethodCallThunk, this,
                                              nullptr);
    events_ = fl_event_channel_new(messenger_, event_name_.c_str(),
                                   FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(events_, ListenThunk, CancelThunk, this,
                                         nullptr);

    if (playbin_ != nullptr) {
      g_autoptr(GstBus) bus = gst_element_get_bus(playbin_);
      bus_watch_id_ = gst_bus_add_watch(bus, BusThunk, this);
    }
  }

  ~Player() {
    StopTimer();
    if (bus_watch_id_ != 0) g_source_remove(bus_watch_id_);
    if (playbin_ != nullptr) {
      gst_element_set_state(playbin_, GST_STATE_NULL);
      gst_object_unref(playbin_);
    }

    // Both handlers point at `this`, so they have to go before it does. The
    // channels are then dropped from the messenger by name: releasing only our
    // own reference would leave the registration behind, and a voice bubble
    // opened and closed all afternoon would accumulate one per player.
    fl_method_channel_set_method_call_handler(methods_, nullptr, nullptr,
                                              nullptr);
    fl_event_channel_set_stream_handlers(events_, nullptr, nullptr, nullptr,
                                         nullptr);
    g_object_unref(methods_);
    g_object_unref(events_);
    fl_binary_messenger_set_message_handler_on_channel(
        messenger_, method_name_.c_str(), nullptr, nullptr, nullptr);
    fl_binary_messenger_set_message_handler_on_channel(
        messenger_, event_name_.c_str(), nullptr, nullptr, nullptr);
  }

  Player(const Player&) = delete;
  Player& operator=(const Player&) = delete;

  // False when GStreamer has no playbin to give, i.e. its base plugins are not
  // installed. The caller turns that into an error the user can act on.
  bool ok() const { return playbin_ != nullptr; }

 private:
  // --- method channel ------------------------------------------------------

  static void MethodCallThunk(FlMethodChannel* channel, FlMethodCall* call,
                              gpointer user_data) {
    static_cast<Player*>(user_data)->HandleMethodCall(call);
  }

  void HandleMethodCall(FlMethodCall* call) {
    const gchar* method = fl_method_call_get_name(call);
    FlValue* args = fl_method_call_get_args(call);

    if (strcmp(method, "load") == 0) {
      Load(args, call);
    } else if (strcmp(method, "play") == 0) {
      SetPlaying(true);
      RespondNull(call);
    } else if (strcmp(method, "pause") == 0) {
      SetPlaying(false);
      RespondNull(call);
    } else if (strcmp(method, "seek") == 0) {
      Seek(IntArg(args, "position", 0));
      RespondNull(call);
    } else if (strcmp(method, "setVolume") == 0) {
      SetVolume(FloatArg(args, "volume", 1.0));
      RespondNull(call);
    } else if (strcmp(method, "setSpeed") == 0) {
      SetSpeed(FloatArg(args, "speed", 1.0));
      RespondNull(call);
    } else {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
      fl_method_call_respond(call, response, nullptr);
    }
  }

  void Load(FlValue* args, FlMethodCall* call) {
    // The map check before the lookup, because `args` is whatever the caller
    // encoded: looking a key up in a non-map is a GLib critical, not a null.
    FlValue* uri_value = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      uri_value = fl_value_lookup_string(args, "uri");
    }
    if (uri_value == nullptr ||
        fl_value_get_type(uri_value) != FL_VALUE_TYPE_STRING) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalid", "load needs a uri", nullptr));
      fl_method_call_respond(call, response, nullptr);
      return;
    }

    // Local files only, and this is a security boundary rather than a
    // convenience check. playbin resolves a uri by asking GStreamer for a
    // source element that claims its scheme, and a desktop GStreamer install
    // claims http, https, rtsp, rtmp, mms and whatever else its plugins add —
    // so handing this property an unfiltered string turns an audio player into
    // a request the app makes from inside the user's session, to a host it was
    // told to contact. This player is only ever pointed at a temp file the app
    // wrote itself (createPlayableSource in the app writes the downloaded
    // bytes and passes back that file's URI), so anything else is either a bug
    // or a caller that should not be trusted, and both stop here.
    const gchar* uri = fl_value_get_string(uri_value);
    if (!gst_uri_is_valid(uri) || !gst_uri_has_protocol(uri, "file")) {
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "invalid", "just_audio_linux plays file:// URIs only", nullptr));
      fl_method_call_respond(call, response, nullptr);
      return;
    }

    // NULL first: playbin only takes a new uri from a stopped pipeline, and a
    // bubble can be replayed after another one has already loaded here.
    gst_element_set_state(playbin_, GST_STATE_NULL);
    g_object_set(playbin_, "uri", uri, nullptr);
    completed_ = false;
    playing_ = false;
    duration_us_ = -1;

    Emit(ProcessingState::kLoading, 0);

    // PAUSED, then block until the pipeline has actually reached it: the
    // duration is what just_audio's load() answers with, and it is not knowable
    // until the demuxer has read enough of the file to say.
    gst_element_set_state(playbin_, GST_STATE_PAUSED);
    GstStateChangeReturn change =
        gst_element_get_state(playbin_, nullptr, nullptr, kPrerollTimeout);
    if (change == GST_STATE_CHANGE_FAILURE ||
        change == GST_STATE_CHANGE_ASYNC) {
      // FAILURE is a file GStreamer could not make sense of; ASYNC is the
      // pre-roll timeout above expiring with the pipeline still working on it.
      // Both mean nothing is going to play, and both have to go back to NULL:
      // a pipeline left half-open holds whatever its source opened for as long
      // as the player lives, and the next play() would look like it worked.
      gst_element_set_state(playbin_, GST_STATE_NULL);
      Emit(ProcessingState::kIdle, 0);
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "load", "GStreamer could not open the audio", nullptr));
      fl_method_call_respond(call, response, nullptr);
      return;
    }

    gint64 duration = 0;
    if (gst_element_query_duration(playbin_, GST_FORMAT_TIME, &duration) &&
        duration > 0) {
      duration_us_ = duration / GST_USECOND;
    }
    const gint64 initial = IntArg(args, "initialPosition", 0);
    if (initial > 0) Seek(initial);
    Emit(ProcessingState::kReady);

    // just_audio reads a negative duration as "unknown", which is the honest
    // answer for a stream whose length the demuxer never reported.
    g_autoptr(FlValue) result = fl_value_new_int(duration_us_);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(call, response, nullptr);
  }

  void SetPlaying(bool playing) {
    if (playing && completed_) {
      // Play after the end means play again, which is what a bubble's button
      // does once a clip has run out.
      Seek(0);
    }
    gst_element_set_state(playbin_,
                          playing ? GST_STATE_PLAYING : GST_STATE_PAUSED);
    playing_ = playing;
    if (playing) {
      StartTimer();
    } else {
      StopTimer();
      // One last event, so a paused bar sits exactly where it stopped rather
      // than where the previous tick left it.
      Emit(ProcessingState::kReady);
    }
  }

  void Seek(gint64 position_us) {
    // Clamped, not trusted: the position comes off a method channel, and the
    // conversion to nanoseconds below wraps around above kMaxPositionUs.
    if (position_us < 0) position_us = 0;
    if (position_us > kMaxPositionUs) position_us = kMaxPositionUs;
    gst_element_seek_simple(
        playbin_, GST_FORMAT_TIME,
        static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
        position_us * GST_USECOND);
    completed_ = false;
    // From the requested position, not from a query: right after a flushing
    // seek the pipeline may still report where it was.
    Emit(ProcessingState::kReady, position_us);
  }

  void SetVolume(double volume) {
    // playbin's volume is a linear 0..1 gain, the same scale just_audio uses.
    // Clamped because g_object_set validates the property itself and answers a
    // NaN or an out-of-range gain with a runtime warning rather than a value.
    if (std::isnan(volume)) return;
    if (volume < 0) volume = 0;
    if (volume > 1) volume = 1;
    g_object_set(playbin_, "volume", volume, nullptr);
  }

  void SetSpeed(double speed) {
    if (!std::isfinite(speed) || speed <= 0 || speed > kMaxSpeed) return;
    gint64 position = 0;
    if (!gst_element_query_position(playbin_, GST_FORMAT_TIME, &position)) {
      position = 0;
    }
    // A rate change is a seek in GStreamer, and it has to start from where the
    // clip currently is or changing the speed would also jump the position.
    gst_element_seek(
        playbin_, speed, GST_FORMAT_TIME,
        static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE),
        GST_SEEK_TYPE_SET, position, GST_SEEK_TYPE_END, 0);
  }

  // --- events --------------------------------------------------------------

  static FlMethodErrorResponse* ListenThunk(FlEventChannel* channel,
                                            FlValue* args,
                                            gpointer user_data) {
    Player* self = static_cast<Player*>(user_data);
    self->listening_ = true;
    // An event on subscribe, so a listener that attaches after load() learns
    // the duration instead of waiting for the first tick.
    self->Emit(self->completed_ ? ProcessingState::kCompleted
                                : ProcessingState::kReady);
    return nullptr;
  }

  static FlMethodErrorResponse* CancelThunk(FlEventChannel* channel,
                                            FlValue* args,
                                            gpointer user_data) {
    static_cast<Player*>(user_data)->listening_ = false;
    return nullptr;
  }

  void Emit(ProcessingState state) { Emit(state, CurrentPositionUs()); }

  void Emit(ProcessingState state, gint64 position_us) {
    if (!listening_) return;
    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "processingState",
                             fl_value_new_int(static_cast<int>(state)));
    fl_value_set_string_take(event, "updatePosition",
                             fl_value_new_int(position_us));
    fl_value_set_string_take(event, "duration", fl_value_new_int(duration_us_));
    fl_event_channel_send(events_, event, nullptr, nullptr);
  }

  gint64 CurrentPositionUs() {
    gint64 position = 0;
    if (playbin_ == nullptr ||
        !gst_element_query_position(playbin_, GST_FORMAT_TIME, &position)) {
      return 0;
    }
    return position / GST_USECOND;
  }

  // --- bus + timer ---------------------------------------------------------

  static gboolean BusThunk(GstBus* bus, GstMessage* message,
                           gpointer user_data) {
    return static_cast<Player*>(user_data)->HandleBusMessage(message);
  }

  gboolean HandleBusMessage(GstMessage* message) {
    switch (GST_MESSAGE_TYPE(message)) {
      case GST_MESSAGE_EOS:
        completed_ = true;
        playing_ = false;
        StopTimer();
        Emit(ProcessingState::kCompleted, duration_us_ > 0 ? duration_us_ : 0);
        break;
      case GST_MESSAGE_ERROR: {
        // Back to NULL: leaving a failed pipeline in PAUSED would make the next
        // play() look like it worked.
        g_autoptr(GError) error = nullptr;
        g_autofree gchar* debug = nullptr;
        gst_message_parse_error(message, &error, &debug);
        g_warning("just_audio_linux: %s (%s)",
                  error != nullptr ? error->message : "playback failed",
                  debug != nullptr ? debug : "no detail");
        gst_element_set_state(playbin_, GST_STATE_NULL);
        playing_ = false;
        StopTimer();
        Emit(ProcessingState::kIdle, 0);
        break;
      }
      case GST_MESSAGE_DURATION_CHANGED: {
        // Some containers only reveal their length once decoding has started.
        gint64 duration = 0;
        if (gst_element_query_duration(playbin_, GST_FORMAT_TIME, &duration) &&
            duration > 0) {
          duration_us_ = duration / GST_USECOND;
          Emit(ProcessingState::kReady);
        }
        break;
      }
      default:
        break;
    }
    return TRUE;  // stay subscribed
  }

  static gboolean TickThunk(gpointer user_data) {
    static_cast<Player*>(user_data)->Emit(ProcessingState::kReady);
    return TRUE;  // keep ticking until StopTimer removes the source
  }

  void StartTimer() {
    if (timer_id_ == 0) {
      timer_id_ = g_timeout_add(kPositionIntervalMs, TickThunk, this);
    }
  }

  void StopTimer() {
    if (timer_id_ != 0) {
      g_source_remove(timer_id_);
      timer_id_ = 0;
    }
  }

  // --- argument helpers ----------------------------------------------------

  static gint64 IntArg(FlValue* args, const char* key, gint64 fallback) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      return fallback;
    }
    FlValue* value = fl_value_lookup_string(args, key);
    return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
               ? fl_value_get_int(value)
               : fallback;
  }

  static double FloatArg(FlValue* args, const char* key, double fallback) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      return fallback;
    }
    FlValue* value = fl_value_lookup_string(args, key);
    if (value == nullptr) return fallback;
    // Dart sends a whole number as an int even where the parameter is a double,
    // so a volume of exactly 1 arrives typed differently from 0.5.
    if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
      return fl_value_get_float(value);
    }
    if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
      return static_cast<double>(fl_value_get_int(value));
    }
    return fallback;
  }

  static void RespondNull(FlMethodCall* call) {
    g_autoptr(FlValue) result = fl_value_new_null();
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(call, response, nullptr);
  }

  FlBinaryMessenger* messenger_;  // owned by the engine
  const std::string method_name_;
  const std::string event_name_;
  GstElement* playbin_ = nullptr;
  FlMethodChannel* methods_ = nullptr;
  FlEventChannel* events_ = nullptr;
  guint bus_watch_id_ = 0;
  guint timer_id_ = 0;
  gint64 duration_us_ = -1;
  bool playing_ = false;
  bool completed_ = false;
  bool listening_ = false;
};

}  // namespace

struct _JustAudioLinuxPlugin {
  GObject parent_instance;

  FlPluginRegistrar* registrar;  // owned by the engine
  std::map<std::string, std::unique_ptr<Player>>* players;
};

G_DEFINE_TYPE(JustAudioLinuxPlugin, just_audio_linux_plugin, G_TYPE_OBJECT)

static FlValue* string_arg(FlMethodCall* method_call, const char* key) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? value
             : nullptr;
}

static void respond_null(FlMethodCall* method_call) {
  g_autoptr(FlValue) result = fl_value_new_null();
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_init(JustAudioLinuxPlugin* self, FlMethodCall* method_call) {
  FlValue* id_value = string_arg(method_call, "id");
  if (id_value == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("invalid", "init needs an id", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  std::string id = fl_value_get_string(id_value);

  // Any player already registered under this id goes first, before the
  // replacement is built. Both share a channel name, and a Player's destructor
  // drops that name from the messenger — so constructing first and erasing
  // afterwards (which is what assigning into the map does) would have the old
  // player's teardown unregister the *new* player's channels on its way out,
  // leaving a live pipeline nothing can reach. The Dart side refuses a
  // duplicate id before it gets here; this is what makes that a convenience
  // rather than the only thing holding the native side together.
  self->players->erase(id);

  auto player = std::make_unique<Player>(self->registrar, id);
  if (!player->ok()) {
    // No playbin means GStreamer's base plugins are not installed. Saying so is
    // the difference between "voice comments are broken" and a package name.
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_error_response_new(
            "gstreamer",
            "GStreamer's playbin is unavailable — install "
            "gstreamer1.0-plugins-base",
            nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  (*self->players)[id] = std::move(player);
  respond_null(method_call);
}

static void just_audio_linux_plugin_handle_method_call(
    JustAudioLinuxPlugin* self, FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "init") == 0) {
    handle_init(self, method_call);
  } else if (strcmp(method, "disposePlayer") == 0) {
    FlValue* id_value = string_arg(method_call, "id");
    if (id_value != nullptr) self->players->erase(fl_value_get_string(id_value));
    // Always a success: disposing something already gone is what a second
    // dispose() looks like, and it is nothing the caller can act on.
    respond_null(method_call);
  } else if (strcmp(method, "disposeAllPlayers") == 0) {
    self->players->clear();
    respond_null(method_call);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

static void just_audio_linux_plugin_dispose(GObject* object) {
  JustAudioLinuxPlugin* self = JUST_AUDIO_LINUX_PLUGIN(object);
  delete self->players;
  self->players = nullptr;
  G_OBJECT_CLASS(just_audio_linux_plugin_parent_class)->dispose(object);
}

static void just_audio_linux_plugin_class_init(
    JustAudioLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = just_audio_linux_plugin_dispose;
}

static void just_audio_linux_plugin_init(JustAudioLinuxPlugin* self) {
  self->players = new std::map<std::string, std::unique_ptr<Player>>();
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  just_audio_linux_plugin_handle_method_call(JUST_AUDIO_LINUX_PLUGIN(user_data),
                                             method_call);
}

void just_audio_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  // Once per process, and harmless to repeat: no playbin can be created before
  // the GStreamer registry exists.
  if (!gst_is_initialized()) {
    gst_init(nullptr, nullptr);
  }

  JustAudioLinuxPlugin* plugin = JUST_AUDIO_LINUX_PLUGIN(
      g_object_new(just_audio_linux_plugin_get_type(), nullptr));
  plugin->registrar = registrar;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "hinata/just_audio_linux",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
