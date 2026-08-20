# Hinata on Linux

Hinata builds as a native GTK 3 desktop application: one binary (`hinata`),
application id `com.ahmadre.hinata`, the same Flutter codebase as every other
platform. This document is the honest version of what that means — which
capabilities are complete, which degrade, why, and what the user actually sees
when they do.

Everything below was derived by reading the plugin sources and the built bundle,
not from a marketing list. Where something has not been exercised on a live
desktop it says so.

---

## Capability matrix

| Capability | Linux | Windows | macOS |
| --- | :---: | :---: | :---: |
| Sign-in, SSO, multi-server | ✅ | ✅ | ✅ |
| Secure token storage (staying signed in) | ⚠️ needs a keyring | ✅ | ✅ |
| Deep links `hinata://…` (SSO / invite / reset / verify) | ✅ | ✅ | ✅ |
| https Universal / App Links (`track.asta.hn`) | ❌ | ❌ | ✅ |
| Push notifications | ❌ | ✅ (WNS) | ✅ (FCM) |
| In-app + e-mail notifications | ✅ | ✅ | ✅ |
| File picking (attachments) | ⚠️ needs zenity/kdialog | ✅ | ✅ |
| Photo / video picking from disk | ✅ | ✅ | ✅ |
| Camera capture (webcam) | ❌ | ✅ | ❌ |
| Voice comments — recording | ⚠️ needs PulseAudio + FFmpeg | ✅ | ✅ |
| Voice comments — playback | ⚠️ needs GStreamer plugins | ✅ | ✅ |
| Attachment download | ⚠️ writes to Downloads | ✅ share sheet | ✅ share sheet |
| Printing / PDF & DOCX export | ✅ | ✅ | ✅ |
| Drag & drop of files into the app | ✅ | ✅ | ✅ |
| Rich clipboard (copy an image out of a comment) | ✅ | ✅ | ✅ |
| Opening links in the browser | ✅ | ✅ | ✅ |
| System tray icon | ❌ | ❌ | ❌ |

✅ works · ⚠️ works, with a condition on the system · ❌ not available

The two ❌ rows that are Linux-only — push notifications and camera capture —
are the whole of what a Linux user gives up. Everything marked ⚠️ works on a
normal desktop install and is only listed because a minimal system (a container,
a bare window manager, a login that never unlocked a keyring) can be missing the
piece it leans on.

---

## Where Linux differs, and what the user sees

### Push notifications — not available

`firebase_messaging` has no Linux implementation, and there is no equivalent to
the WNS channel the Windows build registers instead. `FcmService` therefore
never starts on Linux: no token is registered with the server, and no OS banner
is ever shown.

**What the user sees:** notifications still arrive — in the app's own
notification centre, and by e-mail if the account's notification matrix asks for
them. Nothing appears in the desktop's notification tray, and nothing pops up
while the app is closed.

There is deliberately no `--talk-name=org.freedesktop.Notifications` in the
Flatpak manifest: with no notification path in the app, the permission would
show up in the app's permission list without ever being used.

### Camera capture — not available

`camera` ships Android, iOS and web; the Windows build only has capture because
the app depends on `camera_windows` explicitly. No package covers Linux, so
`installDesktopCameraDelegate` returns early there on purpose.

**What the user sees:** nothing broken — the camera row is simply absent from
the comment composer's "+" menu, and the attachment button opens the document
picker directly. Attaching an existing photo or video works normally. The
alternative would have been a menu entry whose only possible outcome is a dialog
saying there is no camera.

### Staying signed in — needs a secret service

`flutter_secure_storage_linux` stores tokens through libsecret, i.e. the
freedesktop Secret Service. GNOME Keyring and KWallet (with its Secret Service
bridge) both provide it; a minimal window manager or a container may not, and an
SSH session into a desktop that never unlocked its keyring will not either.

**What the user sees:** sign-in works and the session lasts as long as the app is
open, and a toast says so once — the app knows the write failed
(`AppStorage.sessionIsMemoryOnly`) rather than discovering it at the next launch.
The next start asks for the password again.

```bash
sudo apt install gnome-keyring        # Debian / Ubuntu
sudo dnf install gnome-keyring        # Fedora
```

### Deep links `hinata://`

Four pieces have to line up, and all four are in this repository:

1. **The desktop entry** (`packaging/linux/com.ahmadre.hinata.desktop`) declares
   `MimeType=x-scheme-handler/hinata;` and `Exec=hinata %u`. Without it, no
   browser, mail client or portal will ever hand a `hinata://` URI to anything.
2. **The GTK runner** (`linux/runner/my_application.cc`) runs the application as
   a *unique* GApplication with `G_APPLICATION_HANDLES_COMMAND_LINE`. The
   generated Flutter runner used `G_APPLICATION_NON_UNIQUE` and handled the
   command line locally, which meant every link started a second, empty copy of
   Hinata while the instance the user was signing in from heard nothing. Now the
   second launch forwards its argv over D-Bus to the running instance.
3. **Warm start** — `app_links_linux`, through the `gtk` package, listens on the
   resulting `GApplication::command-line` signal and hands the URI to the Dart
   side, which routes it exactly like every other platform.
4. **Cold start** — that signal is emitted *before* `activate`, so on the very
   first launch no plugin is registered yet and `app_links` sees nothing. The
   URI is still in the process arguments, though: the runner passes them on with
   `fl_dart_project_set_dart_entrypoint_arguments`, so `main(List<String> args)`
   receives them and `_launchDeepLink` picks the `hinata://` one out and hands it
   to the app as `initialLink`. Both entrances feed the same `_handleUri`, and
   the replay guard there keeps a link from being followed twice.

Worth knowing: the running window is not reliably raised to the front when a
link arrives on a warm start. `GApplication::command-line` uses
`g_signal_accumulator_first_wins`, so exactly one handler ever runs for a given
emission — and it has to be the plugin's, because the link matters more than the
window stacking.

> **Verified end to end**, in the build container under Xvfb, against a real
> server:
>
> * **Warm start (points 2 and 3).** With one instance running and signed in,
>   `./hinata 'hinata://verify-email?token=deadbeef'` exits 0 in under a second
>   having printed nothing — no second Flutter engine starts, the first instance
>   keeps running — and that instance navigates to the verify-email screen,
>   which reports the bogus token as invalid. Before the runner change the same
>   command started a whole second app and the first heard nothing.
> * **Cold start (point 4).** Launching the same URI as the *first* process
>   lands on the verify-email screen directly, which is the
>   `main(List<String> args)` → `_launchDeepLink` → `initialLink` path.
>
> What is still worth doing on a real desktop is the hop *before* all of this —
> `xdg-open` picking the desktop entry — since the tests above invoked the
> binary directly.

**Register and test the handler:**

```bash
# after installing the .desktop file (see "Installing by hand")
update-desktop-database ~/.local/share/applications
xdg-mime default com.ahmadre.hinata.desktop x-scheme-handler/hinata
xdg-mime query default x-scheme-handler/hinata      # → com.ahmadre.hinata.desktop

xdg-open 'hinata://verify-email?token=test'          # once with Hinata running,
                                                     # once with it closed
```

The https Universal / App Links that work on macOS have no Linux equivalent —
`/.well-known/apple-app-site-association` is an Apple mechanism and there is no
freedesktop counterpart, so `https://track.asta.hn/issues/HN-42` opens in the
browser. The browser's page offers the in-app route. `_launchDeepLink` matches on
the `hinata` scheme alone for the same reason.

### File picking — needs zenity or kdialog

`file_picker` 8.3.7 has no native Linux plugin: its Linux implementation is pure
Dart and shells out to `zenity`, `qarma` or, on KDE, `kdialog`. There is no XDG
portal path in that version, which is also why the Flatpak needs real filesystem
access rather than relying on the portal (see the manifest's comments).

`zenity` is installed by default on Ubuntu, Fedora Workstation and most GNOME
spins; `kdialog` comes with Plasma.

**What the user sees when neither is installed:** every place that opens a file
dialog — attachments, comment attachments, the editor's image button, avatars,
the org logo, e-mail replies — reports it, and on Linux names the three programs
to install. Four of those used to fail in silence, which reads as a dead button.

Photo/video picking is a different code path and needs nothing extra:
`image_picker_linux` delegates to `file_selector_linux`, which is
`GtkFileChooserNative` — and that one *is* taken over by the desktop portal when
the app is sandboxed.

### Voice comments — recording

`record_linux` 1.3.1 does not link an audio library; it pipes `parecord` (from
`pulseaudio-utils`) into `ffmpeg`, and calls `pactl` to enumerate input devices.
Both programs are looked up on `PATH` before capture starts, and the missing one
is named — `record_linux` awaits only the first of the two, so an absent FFmpeg
would otherwise surface as a recording that produced nothing, minutes after the
user started talking.
AAC is supported, so a Linux recording plays back on every other platform.

**What the user sees when the tools are missing:** the recorder fails to start.

```bash
sudo apt install pulseaudio-utils ffmpeg       # Debian / Ubuntu
sudo dnf install pulseaudio-utils ffmpeg       # Fedora (ffmpeg via RPM Fusion)
```

PipeWire systems are fine — `pipewire-pulse` provides the PulseAudio interface
these tools speak, and most distributions install `pulseaudio-utils` alongside
it.

### Voice comments — playback

`just_audio` endorses Android, iOS, macOS and web; Windows is covered by
`just_audio_windows`, and Linux had nothing at all, so a voice comment could be
recorded and then never played. `packages/just_audio_linux` fills that hole with
GStreamer's `playbin` — see its README for the design.

```bash
sudo apt install gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
                 gstreamer1.0-plugins-bad gstreamer1.0-libav
```

`gstreamer1.0-libav` is not optional: the recorder produces AAC in an MP4
container on every desktop platform, and `avdec_aac` is the decoder for it.
`plugins-good` supplies the demuxer (`qtdemux`) but no AAC decoder, so leaving
libav out gives you a bubble that loads and then cannot play — the one shape of
failure this list exists to prevent. (Verified by listing the elements a normal
install actually provides: `playbin`, `wavparse`, `qtdemux`, `avdec_aac`,
`opusdec`, `pulsesink`.)

**What the user sees when they are missing:** playback fails with a message that
names the missing package, rather than a play button that does nothing.

### Attachment download — straight to Downloads

`share_plus` throws `UnimplementedError` for files on Linux, so there is no share
sheet to offer. Downloads are written into the XDG Downloads directory instead,
with the name made unique (`report (2).pdf`) rather than overwriting. A desktop
without `xdg-user-dirs` configured has no such directory to look up, so the app
falls back to `~/Downloads` and creates it — a file the user can find beats a
failure.

**What the user sees:** a toast naming the saved file — which is needed here in a
way it is not on the other platforms, because no dialog went by to confirm that
anything happened.

### Printing and PDF export — complete

`printing` prints through `gtk+-unix-print-3.0` and renders previews with
pdfium. The pdfium library is downloaded by the plugin's CMake at *configure*
time and ends up inside the built bundle as `lib/libpdfium.so` (5.7 MB), so a
packaged app carries it and never reaches for the network.

---

## Building

### Prerequisites

Debian / Ubuntu:

```bash
sudo apt install \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libsecret-1-dev libjsoncpp-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Fedora:

```bash
sudo dnf install \
  clang cmake ninja-build pkgconf-pkg-config \
  gtk3-devel xz-devel libsecret-devel jsoncpp-devel \
  gstreamer1-devel gstreamer1-plugins-base-devel
```

Arch:

```bash
sudo pacman -S base-devel clang cmake ninja pkgconf \
  gtk3 xz libsecret jsoncpp gstreamer gst-plugins-base
```

Each entry earns its place: `libgtk-3-dev` is the embedder (and carries
`gtk+-unix-print-3.0`, which `printing` needs), `liblzma-dev` and `libjsoncpp-dev`
belong to the Flutter Linux toolchain, `libsecret-1-dev` to
`flutter_secure_storage_linux`, and the GStreamer headers to
`packages/just_audio_linux`.

**Rust is also required.** `super_native_extensions` (rich clipboard and drag &
drop) is a Rust crate, and cargokit compiles it from source on Linux — the
project publishes precompiled binaries for Android only. Install it with
[rustup](https://rustup.rs) if `cargo` is not already on `PATH`; both CI jobs
guard for it.

### Build

```bash
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release
```

The result is a relocatable directory:

```text
build/linux/x64/release/bundle/
  hinata            the executable
  data/             flutter_assets + icudtl.dat
  lib/              the engine, every plugin, libpdfium.so
```

The first build is the slow one: it downloads pdfium and compiles the Rust crate.

CI builds the same thing on a pinned `ubuntu-22.04` and uploads it as the
`hinata-linux` artifact (`.github/workflows/ci.yml`). The image is pinned rather
than `ubuntu-latest` because a Flutter bundle is dynamically linked against the
glibc it was built on and glibc is only forward compatible — building on a newer
runner would produce a binary that refuses to start on older distributions.

---

## Running

Runtime dependencies beyond GTK itself, all present on a normal desktop:

| Package (Debian/Ubuntu names) | Needed for | Without it |
| --- | --- | --- |
| `libgtk-3-0` | the app itself | does not start |
| `libsecret-1-0` + a keyring (`gnome-keyring`, KWallet) | staying signed in | signed out on next launch |
| `zenity` or `kdialog` | attachment file picker | picker never opens |
| `pulseaudio-utils`, `ffmpeg` | recording a voice comment | recorder does not start |
| `gstreamer1.0-plugins-base/good/bad`, `gstreamer1.0-libav` | playing a voice comment | base missing: an error naming the package. libav missing: recorded AAC will not decode |
| `xdg-user-dirs` | locating the Downloads folder | the app falls back to `~/Downloads` and creates it |

### Installing by hand

For a plain system-wide install of a build (packaging formats below do this for
you):

```bash
sudo cp -a build/linux/x64/release/bundle /opt/hinata
sudo ln -sf /opt/hinata/hinata /usr/local/bin/hinata

sudo install -Dm644 packaging/linux/com.ahmadre.hinata.desktop \
  /usr/share/applications/com.ahmadre.hinata.desktop
sudo install -Dm644 packaging/linux/com.ahmadre.hinata.metainfo.xml \
  /usr/share/metainfo/com.ahmadre.hinata.metainfo.xml
sudo install -Dm644 packaging/linux/icons/hicolor/512x512/apps/com.ahmadre.hinata.png \
  /usr/share/icons/hicolor/512x512/apps/com.ahmadre.hinata.png

sudo update-desktop-database /usr/share/applications
sudo gtk-update-icon-cache /usr/share/icons/hicolor
```

The bundle has to stay together as one directory: the runner locates
`data/flutter_assets` and `lib/` relative to its own executable, and the plugin
libraries carry an RPATH of `$ORIGIN/lib`. A symlink into `PATH` is fine —
`$ORIGIN` is resolved after following it.

---

## Packaging

Both formats package the **same prebuilt bundle** rather than building Flutter
themselves, and for the same two reasons: the Flutter SDK downloads its engine
artefacts on demand (impossible in an offline Flatpak build), and `printing`
fetches pdfium during the CMake *configure* step, so even configuring the project
needs network. Building first and packaging second sidesteps both, and pdfium
ends up inside the bundle either way.

The shared inputs — desktop entry, icon, AppStream metainfo — live in
`packaging/linux/` so both formats install the identical files. They are not in
`linux/`, because that directory belongs to the Flutter tool and
`flutter create --platforms=linux .` rewrites it.

The icon is `assets/branding/app_icon_windows.png` scaled to 512×512. That file
is the rounded variant of the brand mark, made for Windows because Windows does
not mask app icons — and neither do GNOME or KDE, so it is the right source here
too. It is the real asset, scaled; the brand is never redrawn.

### Flatpak

`packaging/linux/flatpak/com.ahmadre.hinata.yml`, on `org.freedesktop.Platform`
25.08 (the current stable branch; 26.08 was still in beta when this was written).
That runtime happens to carry almost everything the app shells out to — gtk3,
zenity, gstreamer with base/good/bad/ugly/libav, libsecret and ffmpeg are all
elements of the platform image. The one exception is PulseAudio's *client tools*:
the runtime builds libpulse with the daemon disabled and ships no binaries, so
the manifest builds `parecord`/`pactl` itself as a small module. Without it the
mic button would fail to spawn anything.

```bash
flutter build linux --release
flatpak install flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08
flatpak-builder --force-clean --user --install \
  build/flatpak packaging/linux/flatpak/com.ahmadre.hinata.yml
flatpak run com.ahmadre.hinata
```

The permission set is deliberately short — `wayland` + `fallback-x11` (not a
blanket `x11`, which would be a sandbox escape on a Wayland session), `ipc`,
`dri`, `network`, `pulseaudio`, `--talk-name=org.freedesktop.secrets` for the
keyring, read-only access to the XDG documents/pictures/desktop folders for the
picker and `--filesystem=xdg-download:create` for downloads. Each one is
justified in a comment next to it, including the ones that are deliberately
absent.

Those three read-only folders are the concession the portal-less `file_picker`
forces: zenity runs *inside* the sandbox, so it only ever shows the sandbox's
view of the filesystem, and without a grant there is nothing to upload.
Deliberately not `--filesystem=home:ro`: that also hands the app ~/.ssh,
~/.gnupg and every browser profile, none of which is ever an attachment, and all
of which the sandbox exists to keep away from anything the app decodes on a
server's behalf. If `file_picker` ever grows a portal backend, all three lines
can go.

Someone who keeps the files they attach somewhere else — `~/projects`, a mounted
share — can widen it per machine without rebuilding, which is the right place
for that decision because it is one person's filesystem layout, not a default:

```bash
flatpak override --user --filesystem=~/projects:ro com.ahmadre.hinata
```

(or the same toggle in Flatseal). `flatpak override --user --reset
com.ahmadre.hinata` puts it back.

> **Not yet submitted to Flathub.** The manifest builds locally; a Flathub
> submission additionally needs a `<screenshot>` in the metainfo pointing at a
> hosted image, which is called out in a comment there rather than filled with a
> URL that would 404.

### AppImage

`packaging/linux/appimage/build-appimage.sh`:

```bash
flutter build linux --release
packaging/linux/appimage/build-appimage.sh
# → build/linux/appimage/Hinata-10.1.0-x86_64.AppImage
```

It deliberately does **not** run `linuxdeploy` and copies no system library into
the AppDir. The bundle is already self-contained for everything it owns, and is
linked against the system GTK, GStreamer and libsecret on purpose — bundling GTK
would lose the user's theme and the host's GIO/gdk-pixbuf modules, and bundling
GStreamer would lose the codecs the distribution installed.

So this AppImage is portable, not self-sufficient: it assumes the host has GTK 3,
a glibc at least as new as the build machine's, and the runtime packages in the
table above. That is true of any desktop that can run a GTK application, and it
is the honest trade for an image that behaves like a native app instead of a
frozen 1990s copy of one.

`release.yml` builds it on a `linux` platform run and attaches it as the
`hinata-appimage` artifact, alongside the raw bundle. There is no store lane:
Flathub publishes from its own repository, and nothing else asks for an account.

---

## Things to know

- **Hinata is single-instance on Linux.** A second `hinata` hands its arguments
  to the running one and exits instead of opening another window — that is what
  makes deep links work at all (see above), and it is what every GNOME
  application does. It is worth
  remembering during development: a stale instance makes a fresh
  `flutter run -d linux` exit immediately.
- **`StartupWMClass=com.ahmadre.hinata`** matches `g_set_prgname(APPLICATION_ID)`
  in the runner, which is the Wayland `app_id` and the X11 WM_CLASS instance
  name. If a shell ever shows the window as a generic icon, that pairing is the
  first thing to check.
- **`Categories=Office;ProjectManagement;`** — `ProjectManagement` is an
  *additional* category in the freedesktop menu spec and is only valid next to
  `Office` or `Development`; it must not stand alone.
