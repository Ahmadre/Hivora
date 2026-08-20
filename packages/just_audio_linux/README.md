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

Everything else keeps `AudioPlayerPlatform`'s default, which throws `UnimplementedError`. That is deliberate: playlists, clipping, looping modes and audio effects are features this app never asks for, and a plugin that silently accepted them would play silence instead of saying so.

## Design

One `playbin` per player, each with its own pair of channels named after the player's id:

| Channel | Purpose |
| --- | --- |
| `hinata/just_audio_linux` | plugin-level: `init`, `disposePlayer`, `disposeAllPlayers` |
| `hinata/just_audio_linux/methods/<id>` | the player's commands |
| `hinata/just_audio_linux/events/<id>` | the player's playback events |

A channel pair per player, rather than one shared pair carrying an id: two voice bubbles can be open at once, and routing by id in Dart would mean every event waking every player.

Positions are reported on a 200 ms timer while playing, and once more on pause, end and seek — five updates a second is smooth for a scrub bar without waking the UI thread for nothing.

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
