# Microsoft Store — Store listing (English)

Copy-paste source for Partner Center → hinata → Store listing – English.
Kept in the repo so the listing is reviewable and reproducible.

**This listing describes a Windows app and nothing else.** Certification 10.1.4.3
failed once on copy carried over from the Apple listing, so: no other platform,
no device that is not a Windows desktop, and no "on Windows … the same" phrasing
— a comparison implies the platform it compares to. Everything below is written
as if Windows were the only place Hinata exists.

1. **Push works, but not through Firebase.** `firebase_messaging` has no Windows
   implementation; the Windows build registers a **WNS channel URI** instead and
   the Connect gateway routes to WNS. It is a build detail, not listing copy —
   the listing just says notifications work.
2. **Three capabilities.** The MSIX declares `internetClient`, `microphone` and
   `webcam` (plus the automatic `runFullTrust`). The permission block below
   matches exactly what the Store shows under "This app can" — keep the two in
   sync whenever a capability is added or removed.
3. **Ctrl + K**, never ⌘K — in the copy and in the screenshots.

---

## Product name

    hinata

## Short description  (≤ 270 characters — currently 233)

    Open-source, self-hosted project and issue tracking. Connect Hinata to your own server and keep your team's work on infrastructure you control — agile boards, sprints, Gantt timelines, reports and a built-in wiki, with no per-user pricing.

## Description

**Source of truth: `windows/store/listing.json`** — that is the text the lane
actually pushes, so it is not duplicated here. Read it there, edit it there.

**Keep every other platform out of it.** Certification **10.1.4.3 App Quality –
Description** failed on 2026-08-17 (both language listings) on two leftovers
from the Apple copy:

- *"One app, every screen: desktop, tablet and phone …"* — describes the app on
  devices nobody can buy it on here; the package targets `Windows.Desktop` only.
- *"On Windows, Hinata runs as a native desktop app with the same full feature
  set."* — "on Windows … the same" reads as a comparison with another platform.

The replacement says the same thing without the comparison: a native Windows
desktop app that lays out from a snapped window to full screen. It also drops
the four-space indentation the old copy carried into Partner Center from being
pasted out of a Markdown code block.

## What's new in this version

Microsoft's guidance: *"Leave blank if this is the first submission for this
product."* Keeping a line is fine too — this one is accurate:

    Initial Windows release.

## Product features  (bulleted list, up to 20)

    Agile boards with drag & drop and WIP limits
    Sprint planning with capacity, story points and burndown
    Epic → Story → Sub-task hierarchy with dependencies
    Gantt and Timeline views with live progress
    Reports: burndown, velocity, cycle time and distribution
    Weekly timesheets by activity
    Threaded comments with reactions and voice notes
    Drag-and-drop file, photo and video attachments
    Built-in hierarchical Markdown knowledge base
    Ctrl + K command palette with global search
    Single sign-on: OpenID Connect, OAuth 2.0, SAML, LDAP
    Two-factor authentication (TOTP)
    Multi-server support with separate secure sessions
    Light and dark theme
    Self-hosted — your data never leaves your server

## Keywords  (max 7, ≤ 40 chars each, ≤ 21 words total — this uses 12)

    project management
    issue tracker
    self-hosted
    agile boards
    sprint planning
    kanban
    open source

## Copyright and trademark info

    © 2026 com.ahmadre. Hinata is open-source software.

**Check this before saving** — it should carry the legal name you publish under,
matching `Runner.rc` (`LegalCopyright`) and the LICENSE file.

## Developed by

    com.ahmadre

Same check as above: this is displayed publicly on the listing.

## Fields to leave EMPTY

| Field | Why |
|---|---|
| Short title | Xbox-only (install screens, achievements) |
| Voice title | Xbox/Kinect-only |
| Xbox images (key art, hero art, square art) | Product is Desktop-only |
| Additional license terms | Only if you amend the Standard Application License Terms |
| Trailers | Optional; needs the 16:9 hero image to show at the top of the listing |

## Images

### Screenshots — `windows/store/screenshots/`

Six 2560 × 1440 desktop shots, in listing order, with the captions in
`captions.json` (en-us + de-de). Upload them with **Actions → "Windows listing
(screenshots)"**; `windows/store/update_listing.py` writes them into the pending
Partner Center submission through the Store submission API, for every language.

**Why they look the way they do.** The 2026-08-16 submission was rejected under
policy **10.1.1.3 Inaccurate Representation**: the images uploaded then were the
Apple-store compositions — a MacBook frame with macOS traffic lights. Store
metadata may not show another platform's UI or devices. The current set shows the
app in a plain Windows 11 window (title bar with minimize / maximize / close) on
the brand backdrop, and nothing else: Store guidance for the screenshot slots is
also explicit that they carry no extra logos, icons or marketing copy.

Two things to keep in mind when regenerating them:

- The search hint must read **Ctrl K**, not ⌘K. The app renders it per platform
  (`searchShortcutLabel` in `lib/features/shell/app_shell.dart`) — before
  2026-08-16 it was hardcoded to ⌘K on every platform, which is what the old
  screenshots showed.
- Captions are per language; the app UI in the images is English for both
  listings.

Store logos — generated from `assets/branding/app_icon.png` into
`windows/store/images/` by `windows/store/generate_images.py`:

| File | Size | Field |
|---|---|---|
| `poster-720x1080.png` | 720 × 1080 | 9:16 Poster art (main logo on Windows 10/11) |
| `box-art-1080.png` | 1080 × 1080 | 1:1 Box art |
| `tile-300.png` | 300 × 300 | Store display image — app tile icon |
| `tile-150.png` | 150 × 150 | Store display image |
| `tile-71.png` | 71 × 71 | Store display image |

The three "Store display images" are optional — without them the Store falls
back to the logos inside the package, which are already correct. The 9:16
poster is worth uploading: Partner Center marks it as the main logo shown to
Windows 10/11 customers.
