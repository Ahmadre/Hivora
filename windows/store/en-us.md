# Microsoft Store — Store listing (English)

Copy-paste source for Partner Center → hinata → Store listing – English.
Kept in the repo so the listing is reviewable and reproducible.

**Feature parity with macOS/iOS, reached by different means — keep the wording:**

1. **Push works, but not through Firebase.** `firebase_messaging` has no Windows
   implementation; the Windows build registers a **WNS channel URI** instead and
   the Connect gateway routes to WNS. User-visible behaviour is the same, so the
   Apple wording is accurate here.
2. **Three capabilities.** The MSIX declares `internetClient`, `microphone` and
   `webcam` (plus the automatic `runFullTrust`). The permission block below
   matches exactly what the Store shows under "This app can" — keep the two in
   sync whenever a capability is added or removed.
3. **Ctrl + K**, not ⌘K — and "On Windows", not "On the Mac".

---

## Product name

    hinata

## Short description  (≤ 270 characters — currently 233)

    Open-source, self-hosted project and issue tracking. Connect Hinata to your own server and keep your team's work on infrastructure you control — agile boards, sprints, Gantt timelines, reports and a built-in wiki, with no per-user pricing.

## Description

    Hinata is an open-source, self-hosted project- and issue-tracking client. You connect it to your own Hinata Server, so your team's work stays on infrastructure you control — with no per-user pricing and no board limits.

    One app, every screen: desktop, tablet and phone share a single, fully responsive interface that adapts through golden-ratio breakpoints, in a light or dark theme.

    WHAT YOU CAN DO
    • Agile boards — drag & drop across columns, WIP limits, and Board, Backlog and Timeline views
    • Sprints — plan, run and review with capacity, story points and burndown
    • Issues — Epic → Story → Sub-task hierarchy, dependencies, labels and archiving
    • Gantt & Timeline — start/due dates, dependencies and live progress
    • Reports — burndown, velocity, cycle time and distribution charts
    • Timesheets — weekly time tracking by activity
    • Comments — threaded replies, emoji reactions and voice notes, updating live
    • Attachments — drag-and-drop files, photos and videos with a glass lightbox
    • Knowledge base — a built-in, hierarchical Markdown wiki with smart links
    • Command palette — Ctrl + K global search across everything
    • Notifications — in-app, e-mail and push for assignments, @mentions and due dates

    BUILT FOR TEAMS
    • Projects & teams with per-project workflows, keys and members
    • Sign in with local credentials and optional two-factor (TOTP), or SSO (OpenID Connect, OAuth 2.0, SAML, LDAP)
    • Self-registration with e-mail verification, and forgot-password
    • Multi-server: save several servers and switch between them, each with its own secure session

    YOUR DATA, YOUR SERVER
    Hinata collects nothing for itself. All content lives on the Hinata Server you connect to. There is no tracking and no analytics.

    On Windows, Hinata runs as a native desktop app with the same full feature set.

    Requires a Hinata Server to sign in. Learn how to self-host at hinata.ahmadre.com.

    PERMISSIONS & WHY WE NEED THEM
    • Internet — to reach the Hinata Server you connect to
    • Microphone — voice comments and sound for videos you attach
    • Camera — take a photo or record a video to attach to an issue
    We ask for each permission only when you first use the feature that needs it.

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
