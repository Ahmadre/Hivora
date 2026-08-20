# just_audio_linux

The Linux playback implementation of [`just_audio`](https://pub.dev/packages/just_audio), backed by GStreamer.

## Why this exists

`just_audio` endorses android, iOS, macOS and web. Windows is covered in this app by depending on `just_audio_windows`; Linux had nothing at all, so a voice comment could be **recorded** on Linux (`record_linux` works) and then never **played** — `JustAudioPlatform.instance` fell back to the default implementation, which throws.

No `just_audio_linux` is published, so this is one: the same federated shape as the Windows package — register and forget, no call site in the app changes — with GStreamer's `playbin` in place of WinRT's `MediaPlayer`.

## Why GStreamer

- It is already installed on every GTK desktop, and shipped by every Flatpak and Snap runtime — nothing to bundle, nothing to license.
- `playbin` picks the demuxer and decoder itself. The app does not know what container `record` produced on a given desktop, and with `playbin` it does not have to.
- It is the same audio stack the rest of the desktop uses, so system volume, the default sink, and Bluetooth switching all behave the way the user expects them to.

## What is implemented

`load`, `play`, `pause`, `seek`, `setVolume`, `setSpeed`, and the playback event stream (processing state, position, duration).

`setLoopMode` and `setShuffleMode` are answered too, but only for `off` and `none` — anything else is refused. They are not features this plugin has; they are on the path `just_audio` walks into *every* `load()`, and unlike `setPitch` and `setSkipSilence` it does not catch what they throw. Leaving them to the platform interface's `UnimplementedError` therefore failed every load on Linux.

`load` likewise takes the single-child `ConcatenatingAudioSourceMessage` that `just_audio` wraps a lone source in — since 0.10 every `AudioPlayer` keeps a playlist internally, so even `setFilePath` arrives in that shape.

`load` accepts **`file://` URIs only**, and that is a boundary rather than a convenience: `playbin` will take any scheme some installed GStreamer plugin claims — http, rtsp, mms — so an unfiltered URI turns an audio player into a request the app makes from inside the user's session. The app only ever points this at a temp file it wrote itself (`createPlayableSource`), so anything else is refused with `invalid`.

Everything else keeps `AudioPlayerPlatform`'s default, which throws `UnimplementedError`. That is deliberate: real playlists, clipping and audio effects are features this app never asks for, and a plugin that silently accepted them would play silence instead of saying so.

## Design

One `playbin` per player, each with its own pair of channels named after the player's id:

| Channel | Purpose |
| --- | --- |
| `hinata/just_audio_linux` | plugin-level: `init`, `disposePlayer`, `disposeAllPlayers` |
| `hinata/just_audio_linux/methods/<id>` | the player's commands |
| `hinata/just_audio_linux/events/<id>` | the player's playback events |

A channel pair per player, rather than one shared pair carrying an id: two voice bubbles can be open at once, and routing by id in Dart would mean every event waking every player.

The wire between the two halves, in one place so neither has to be read to understand the other:

| Player method | Arguments | Answer |
| --- | --- | --- |
| `load` | `uri` (`file://`), `initialPosition` µs | duration in µs, or **`-1` for "length unknown"** |
| `play`, `pause` | — | null |
| `seek` | `position` µs | null |
| `setVolume` | `volume` 0..1 | null |
| `setSpeed` | `speed` >0 | null |

Every event on the player's event channel is a map of `processingState` (the index of `ProcessingStateMessage`, so its order is load-bearing), `updatePosition` in µs, and `duration` in µs — again `-1` while the demuxer has not reported a length. A negative duration stays `null` on the Dart side rather than becoming zero: a clip of length zero draws an empty waveform and a scrub bar already at the end.

`playbin` is configured audio-only (`GST_PLAY_FLAG_AUDIO | GST_PLAY_FLAG_SOFT_VOLUME`). Its default flags also build the video and subtitle chains, and the bytes played here come from whatever someone attached to a comment — an MP4 with a video track would otherwise pop an `autovideosink` window over the app.

Positions are reported on a 200 ms timer while playing, and once more on pause, end and seek — five updates a second is smooth for a scrub bar without waking the UI thread for nothing. No event is built at all while nothing is listening.

`load` does not block. Every callback here runs on the platform thread, which is also the GLib main context and the one that dispatches channel messages, so waiting there for a pre-roll stops the whole app — measured at 4-5 ms for a voice comment, ~25 ms for the first one in a session, and unbounded for a slow source. Instead the pipeline is set to `PAUSED` and the caller is answered from the bus: `ASYNC_DONE` carries the duration, an error answers with the failure (within 2 ms for every unplayable file measured), and a five-second timer answers "length unknown" for a source that is merely slow, leaving it to finish on its own.

## Requirements

Build:

```
sudo apt install libgstreamer1.0-dev
```

Runtime — the base plugins carry `playbin` itself, `good`/`bad` carry the decoders for what the recorder produces:

```
sudo apt install gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
```

Without them `init` fails with a message naming the missing package rather than a silent dead play button.
