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
| Secure token storage (staying signed in) | ⚠️ needs a keyring (and, under snap, one permission) | ✅ | ✅ |
| Deep links `hinata://…` (SSO / invite / reset / verify) | ✅ | ✅ | ✅ |
| https Universal / App Links (`track.asta.hn`) | ❌ | ❌ | ✅ |
| Push notifications | ❌ | ✅ (WNS) | ✅ (FCM) |
| In-app + e-mail notifications | ✅ | ✅ | ✅ |
| File picking (attachments) | ✅ | ✅ | ✅ |
| Photo / video picking from disk | ✅ | ✅ | ✅ |
| Camera capture (webcam) | ❌ | ✅ | ❌ |
| Voice comments — recording | ⚠️ needs PulseAudio + FFmpeg | ✅ | ✅ |
| Voice comments — playback | ⚠️ needs GStreamer plugins | ✅ | ✅ |
| Attachment download | ⚠️ writes to Downloads | ✅ share sheet | ✅ share sheet |
| Printing / PDF & DOCX export | ✅ | ✅ | ✅ |
| Drag & drop of files into the app | ⚠️ Flatpak/snap: from the XDG folders | ✅ | ✅ |
| Rich clipboard (copy an image out of a comment) | ✅ | ✅ | ✅ |
| Opening links in the browser | ✅ | ✅ | ✅ |
| System tray icon | ❌ | ❌ | ❌ |

✅ works · ⚠️ works, with a condition on the system or the sandbox · ❌ not
available

The two ❌ rows that are Linux-only — push notifications and camera capture —
are the whole of what a Linux user gives up. Everything marked ⚠️ works on a
normal desktop install and is only listed because a minimal system (a container,
a bare window manager, a login that never unlocked a keyring) can be missing the
piece it leans on. Drag & drop is the one ⚠️ whose condition is the *sandbox*
rather than the system: in the Flatpak and the snap a drop works out of the
folders those packages are given read access to, and everything else on disk is
attached with the button instead, which goes through the portal and reaches
anywhere. Picking and dropping each get a section below, because they take
different routes into the app and only one of them has a portal on it.

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
bridge) both provide it. Three kinds of system fail, and the fixes have nothing
to do with each other:

1. **No secret service at all** — a minimal window manager, a container, an SSH
   session into a desktop that never unlocked its keyring.
2. **A strictly confined snap.** The keyring is running perfectly well on the
   session bus; the sandbox is simply not allowed to talk to it. The
   `password-manager-service` interface carries `deny-auto-connection: true`, so
   a fresh install has the permission declared and *not* connected.
3. **A keyring that is merely locked** — the daemon is there, the snap plug (if
   any) is connected, and the collection has not been unlocked this login.
   Common on machines that autolog in.

The important detail either way: libsecret does not answer `null` when it cannot
reach the service — it **throws**. Every call in `AppStorage` is therefore
guarded, and `AppStorage.restore()` (the boot sequence `main` awaits before
`runApp`) cannot throw at all. A desktop with no keyring reaches its own login
screen like any other. The environment detection is guarded for the same reason:
`Platform.environment` is not a plain getter, and a failure there must not cost
anyone their login screen over a question that only picks a sentence.

**Which advice, from what.** Two inputs, because neither alone is enough.

* The **error code** separates case 3 from cases 1 and 2. In
  `flutter_secure_storage_linux` 3.0.2 a locked collection comes back as
  `KeyringLocked` and an unreachable service as `Libsecret error`
  (`secret_service_get_sync: …`). 3.0.1 threw `KeyringLocked` for both, which is
  why this used to be treated as unknowable — the pinned version knows, and a
  snap whose plug *is* connected must never be told to connect it.
* The **environment** separates case 1 from case 2: snapd's `SNAP`,
  `SNAP_NAME` and `SNAP_INSTANCE_NAME`. Every one of those is *inherited* by
  every child process, so a `.deb`, a Flatpak, an AppImage or `flutter run`
  started from the terminal of the VS Code snap sees a full snap environment
  naming `code`. `SecretStoreEnvironment` therefore also requires
  `Platform.resolvedExecutable` to live under `$SNAP` — a confined app is
  executed out of its own mount — so nobody is ever handed a `snap connect` line
  for somebody else's snap.

**When the app finds out.** On a restart with a saved session, at boot — the
stored tokens are read, the read throws, and the user is on the login screen with
an explanation instead of a mystery. On a first run, at the first write, i.e.
the moment they sign in. There is deliberately **no** availability probe at
launch: the plugin unlocks a locked collection before *every* read, so a
throwaway read at startup raises the desktop's keyring-password dialog on every
launch of a correctly configured install whose keyring is simply locked — a
recurring password box for people with nothing wrong with their setup, in
exchange for saving one sign-in for people who have an interface to connect.

**What the user sees:** the app starts, sign-in works, and the session lasts as
long as the app is open — one glass toast, once per launch, says that it will not
outlive it and names the one fix that applies *here*: install a keyring, connect
the interface, or unlock what is already there. The toast carries a copy button
only where there is a command to copy, and (like every actionable toast) is
dismissed by tapping it.

The toast also fires when the app is *signed out* at boot — tokens written on a
previous run that cannot be read back now. That is the case users actually meet
(the app bounces to the login screen every morning) and the only thing that
connects it to its cause.

Nothing is written anywhere else as a fallback. The in-memory session is memory
and only memory: a long-lived refresh token in a plaintext file, on precisely the
systems that just said they have nowhere safe to keep one, is a worse outcome
than signing in again. The single exception is a token an older,
pre-secure-storage build already wrote to SharedPreferences: that one is lifted
into the store (and deleted from prefs) on the first launch the store will take
it, and left alone — never copied — until then, because deleting it would throw
away a session an unlocked keyring tomorrow would have kept.

```bash
# 1 — a desktop with no keyring
sudo apt install gnome-keyring        # Debian / Ubuntu
sudo dnf install gnome-keyring        # Fedora

# 2 — inside the snap (or the same toggle under Permissions in App Center)
sudo snap connect hinata:password-manager-service

# 3 — a keyring that is there but locked: unlock the "Login" collection, e.g.
seahorse                              # GNOME: right-click Login → Unlock
```

All three are one-time (3 recurs only if the login keyring's password differs
from the account password, which is what stops it unlocking at login). After any
of them, sign in once more and the session persists.

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

### File picking — the portal, not a helper program

Linux uses a different picker from every other platform, chosen in
`lib/core/util/file_pick.dart`. That file is the seam: every upload surface —
the attachments section, comment attachments, the two Markdown/Lexical image
buttons, both avatar editors, the organisation logo, the e-mail reply sheet, and
on Linux the comment composer's gallery entry — calls
`pickFilesToUpload(context, …)`, and none of them knows which package answers.
(`grep -rn 'pickFilesToUpload(' lib` is the list; this document deliberately
does not carry a count of it.)

`file_picker` — still what Android, iOS, macOS, Windows and web use — has no
native Linux plugin. Its Linux implementation is pure Dart and shells out to
`zenity`, `qarma` or, on KDE, `kdialog`. That is a hard failure under
confinement: a snap's `$PATH` is `$SNAP/usr/bin` plus the base snap's
`/usr/bin`, so none of those programs is reachable no matter what the host has
installed, and the dialog simply never appeared — no error, no window, a dead
button. Inside a Flatpak a staged copy *did* run, but inside the sandbox, so it
could only show the sandbox's view of the filesystem; that is what originally
put read access to three XDG directories in the manifest. (They are still
there — for drag & drop, which is a different mechanism with a different
answer; see below.)

Linux now goes through `file_selector_linux`, a real plugin calling
`gtk_file_chooser_native_new`. GTK hands that to the XDG **FileChooser portal**
whenever the app is sandboxed — unconditionally inside Flatpak (`/.flatpak-info`
exists, so `gdk_should_use_portal()` is true), and via `GTK_USE_PORTAL=1` in a
snap, which the gnome extension sets and `snapcraft.yaml` sets again explicitly.
The dialog is then drawn by the *host*, browses the host's filesystem, and the
chosen file is handed back through the **document portal**: it appears inside
the sandbox at `/run/user/<uid>/doc/<hash>/<name>`.

That last detail is the one thing to keep in mind when touching upload code. The
path the app receives is **not** the path the user browsed to — only the final
segment survives, and that segment is the file's name. Everything in the app
uploads under `ChosenFile.name` and shows `ChosenFile.name` — the seam's own
type, deliberately *not* called `PickedFile`, because `image_picker` exports a
deprecated class by that name and two of these screens import it. Nothing
derives a name from a directory, which is why the remapping is invisible. Keep
it that way.

Two smaller consequences, both improvements:

- A file outside the XDG folders — `~/projects`, a mounted share, a USB stick —
  is now selectable in the sandboxed builds. It was not before.
- The image filter gained WebP. The zenity filter was `*.bmp *.gif *.jpeg *.jpg
  *.png`, so a WebP the server happily accepts was not selectable at all.

Unsandboxed (a `.deb`-style install, `flutter run`), GTK opens its own dialog as
always and nothing here applies.

Photo/video picking never had the problem: `image_picker_linux` has delegated to
`file_selector_linux` all along. The file picker has simply caught up with it.
What it does not do is speak the user's language — it passes a hard-coded
English `Images` filter and no `confirmButtonText`, so GTK labels its accept
button `_Open`. The comment composer's "Galerie" entry therefore goes through
the seam as well on Linux (`galleryIsAFileDialog` in `file_pick.dart`): the
identical dialog, with the same two translated strings the attachment button
gets. On every platform with a real photo library, `image_picker` still opens
it.

### Drag & drop — the one upload path with no portal in it

Dropping files onto the attachments section does not go through the picker, and
so does not go through the portal either. `desktop_drop`'s Linux plugin
registers plain URI targets (`gtk_drag_dest_add_uri_targets`) and reads the raw
selection, so what the app receives is the host path the file always had —
`/home/u/Documents/report.pdf` — with nothing remapping it into the sandbox.
GTK has a portal for exactly this case (`org.freedesktop.portal.FileTransfer`,
negotiated through the `application/vnd.portal.filetransfer` target); the plugin
does not ask for it.

Unsandboxed that is just a path and every drop works. Inside a sandbox the path
resolves only where a grant mounts it, which is why both packages keep read
access to the folders a drag realistically starts in: three read-only XDG
directories in the Flatpak (`xdg-documents`, `xdg-pictures`, `xdg-desktop`, plus
the Downloads grant that already exists for writing), and the `home` plug in the
snap, which has no per-directory equivalent. **Those grants are for drag & drop
alone** — the picker needs none. The Flatpak still refuses
`--filesystem=home:ro`, and the snap's `home` plug excludes every top-level
dotfile (`owner @{HOME}/[^s.]** rwkl`), so `~/.ssh`, `~/.gnupg` and browser
profiles stay out of reach of an app that decodes attachments for a living.

**What the user sees** when a drop lands outside them — a file dragged out of
`~/projects`, or a folder dropped instead of a file — is a toast saying the
dropped file could not be read, pointing at **Add files**. That button goes
through the portal and reaches the file wherever it lives. It is deliberately
*not* the picker's message: no dialog was involved, and "couldn't open the file
dialog" would send someone looking in the wrong place.

Closing that asymmetry for good needs the plugin to speak the FileTransfer
portal. Until then the grants are the honest price of a drop that works, and
they are commented as such in both manifests so nobody drops them again while
reading only the picker's half of the story.

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

Inside the snap the lookup is not asked at all, because there it does not fail —
it lies. snapd points `HOME` at the sandbox's own data directory and the `home`
interface hides `~/.config/user-dirs.dirs` (a top-level dotfile), so
`xdg-user-dir DOWNLOAD` answers with the *snap's* home and the file would land
in `~/snap/hinata/current/Downloads`, a folder no file manager bookmarks. snapd
exports `SNAP_REAL_HOME` for exactly this, so the app writes to
`$SNAP_REAL_HOME/Downloads` whenever `HOME` is not the user's real home — the
same `~/Downloads` the Flatpak reaches through `--filesystem=xdg-download:create`
and the AppImage reaches directly. If that write is refused (the `home` interface
disconnected, or Ubuntu Core), the download still lands in the confined home
directory rather than failing.

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

Three formats, one of which is the channel: the **snap** is what Hinata ships
Linux through, and the Flatpak and the AppImage are recipes anyone can build.

The Flatpak and the AppImage package the **same prebuilt bundle** rather than
building Flutter themselves, and for the same two reasons: the Flutter SDK
downloads its engine artefacts on demand (impossible in an offline Flatpak
build), and `printing` fetches pdfium during the CMake *configure* step, so even
configuring the project needs network. Building first and packaging second
sidesteps both, and pdfium ends up inside the bundle either way. The snap does
run the Flutter build itself, because a snapcraft build step has network — see
below.

The shared inputs — desktop entry, icon, AppStream metainfo — live in
`packaging/linux/` so all three formats install the identical files. They are
not in `linux/`, because that directory belongs to the Flutter tool and
`flutter create --platforms=linux .` rewrites it.

The icon is `assets/branding/app_icon_windows.png` scaled to 512×512. That file
is the rounded variant of the brand mark, made for Windows because Windows does
not mask app icons — and neither do GNOME or KDE, so it is the right source here
too. It is the real asset, scaled; the brand is never redrawn.

### Snap — the channel

`packaging/linux/snap/snapcraft.yaml`: `core24`, `confinement: strict`, the
`gnome` extension, built for `amd64` and `arm64`. It builds from source, and the
file's own header explains the one non-obvious step — snapcraft takes the
directory holding `snap/snapcraft.yaml` as the project directory, so the
repository root carries a `snap` symlink to `packaging/linux/snap` and the recipe
stays with the other packaging inputs:

```bash
ln -sfn packaging/linux/snap snap     # once, from the repository root
snapcraft
sudo snap install gnome-46-2404 mesa-2404 gtk-common-themes
sudo snap install --dangerous ./hinata_<version>_amd64.snap
sudo snap connect hinata:password-manager-service
sudo snap connect hinata:audio-record
```

The three platform snaps are only needed for a local `--dangerous` install:
snapd pulls a content snap's default provider by itself for store installs.
Neither of the two `snap connect` lines auto-connects, and that is the price of
the two features behind them — the keyring the session tokens live in, and the
microphone.

**Store status.** The name is registered and `release.yml` uploads both
architectures, but no revision has reached a channel, and a snap with no
released revision has no public listing: <https://snapcraft.io/hinata> answers
404, and the store API answers `No snap named 'hinata' found in series '16'`.
Do not link that URL anywhere until a revision is on a channel — a reader who
follows it gets a 404, not a status.

What holds a revision back is the store's own review, and the publish job is
written around it: `snapcraft release` answers `resource-not-ready` while a
revision is still being looked at, which the job reports as held instead of
failing, so the revision reaches the channel by itself once the review clears.

The `dbus` slot is **not** the reason, whatever an earlier version of this page
said. Owning `com.ahmadre.hinata` is a privileged request in the sense that
snapd denies it without a slot — `g_application_register()` fails and nothing
starts — but snapd's base declaration lets an app snap install a *session*-bus
slot on its own. It is a system-bus slot that needs a store override and a human
(see the slot's own comment in `snapcraft.yaml`, which is the authority here).

**Which channel.** That is this workflow's decision, not the store's:
`release.yml` releases a tag build to **edge**, and switches to `stable` only
when the run is started with `submit=true` — the same gate that separates a
TestFlight drop from an App Store submission. A bare `snap install hinata` reads
`stable`, so it is not the status check. `snap info hinata` is: it lists every
channel that carries a revision, and errors with `no snap found for "hinata"`
while none does. To install what a tag published, ask for the channel:
`snap install hinata --edge`.

**Flathub is not an option.** Its
[submission requirements](https://docs.flathub.org/docs/for-app-authors/requirements)
exclude applications whose content was produced with an LLM, and Hinata's was.
The manifest below stays because it builds and installs; it is a recipe, not a
channel.

### Flatpak

`packaging/linux/flatpak/com.ahmadre.hinata.yml`, on `org.freedesktop.Platform`
25.08 (the current stable branch; 26.08 was still in beta when this was written).
That runtime happens to carry almost everything the app shells out to — gtk3,
gstreamer with base/good/bad/ugly/libav, libsecret and ffmpeg are all elements
of the platform image. The one exception is PulseAudio's *client tools*:
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
keyring, `--filesystem=xdg-download:create` for downloads, and three read-only
XDG directories for drag & drop. Each one is justified in a comment next to it,
including the ones that are deliberately absent.

**The file picker has no read grant, and does not need one.** `xdg-documents:ro`,
`xdg-pictures:ro` and `xdg-desktop:ro` were originally the picker's, because
zenity ran *inside* the sandbox and could only show the sandbox's view of the
filesystem. With the FileChooser portal the dialog runs on the host and the app
is handed exactly one file through the document portal — stricter (the app can
no longer read a directory it was never pointed at) and less restrictive in
practice (a file in `~/projects` or on a mounted share is selectable now, which
it was not before).

They stay for the two things the portal does *not* answer, both described under
"Drag & drop" above: `desktop_drop` hands the app raw host paths, and
`gtk_file_chooser_native_show` falls back to an in-process dialog that browses
the sandbox when no `xdg-desktop-portal` backend is running at all. With no
grants the first breaks outright and the second shows an empty tree with no
error — the same invisible dead end this change set out to remove. The snap
keeps its `home` plug for these two reasons, and for a third the Flatpak grants
separately: writing a downloaded attachment into the user's real `~/Downloads`.

`--filesystem=home:ro` is still refused: read access to a home directory is read
access to `~/.ssh`, `~/.gnupg` and every browser profile, none of which is ever
an attachment.

`--filesystem=xdg-download:create` stays: it is for *writing* a downloaded
attachment, which no portal is involved in — `share_plus` throws
`UnimplementedError` for files on Linux, so downloads go straight to the XDG
Downloads folder. It happens to make a just-downloaded file droppable too.

Someone who wants to widen the sandbox anyway — to drag files in out of
`~/projects`, say — can do it per machine without rebuilding, which is the right
place for that decision because it is one person's setup, not a default:

```bash
flatpak override --user --filesystem=~/projects:ro com.ahmadre.hinata
```

(or the same toggle in Flatseal). `flatpak override --user --reset
com.ahmadre.hinata` puts it back.

> **This manifest is for building it yourself.** It is not submitted anywhere,
> and it is not going to be — see "Flathub is not an option" above. The
> AppStream metainfo is still written to a store listing's standard (screenshots
> pinned to a commit, exactly one `type="default"`), because GNOME Software and
> KDE Discover read the same file for a locally installed app.

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
`hinata-appimage` artifact, alongside the raw bundle. It is not published to a
store — the store lane is the `snap` job in the same workflow, which builds both
architectures natively, installs and smoke-tests each one under Xvfb, and then
uploads them from a single publish job (the store reviews one upload per snap at
a time, so two parallel uploads race).

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
