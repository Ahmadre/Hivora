#!/usr/bin/env python3
"""Generate the store "What's New" notes for a release and write them into every
store's metadata.

    tool/gen_changelog.py <versionCode> [--version X.Y.Z] [--since <ref>] [--write]
    tool/gen_changelog.py --check                 # audit what is already on disk

Writes (with --write):
  android/fastlane/metadata/android/{en-US,de-DE}/changelogs/<versionCode>.txt
  ios/fastlane/metadata/{en-US,de-DE}/release_notes.txt
  macos/fastlane/metadata/{en-US,de-DE}/release_notes.txt
  windows/store/listing.json  →  releaseNotes per listing language

Where the text comes from, best source first:

  1. ``release/notes/<version>.json`` — release notes written by a human, in
     both languages. This is the intended source for anything that ships: a
     commit subject is written for the next developer, a release note is
     written for the person deciding whether to update.
  2. Claude, when ANTHROPIC_API_KEY is set — commit subjects turned into
     user-facing copy in both languages.
  3. A deterministic fallback derived from the commits themselves.

**Every** source then goes through the same two gates, because the last two can
produce anything and the first one is still written by somebody in a hurry:

  * :func:`_scrub` strips what is addressed to developers — ticket ids, PR
    numbers, Conventional-Commit prefixes — and drops reverts together with the
    commits they revert.
  * :func:`_channel_safe` drops any line naming a platform other than the store
    it is being written for.

That second gate is not a style preference. A release note in the Mac App Store
that advertises what changed on Android reads as a pointer to a competing
storefront (App Review Guideline 2.3.10), and it is why 10.2.0 was rejected on
macOS. The same text also went to Google Play naming iOS and macOS, and to the
Microsoft Store naming all four. One release, four listings, one class of
mistake — so the rule lives in one place and every write goes through it.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- what a store will and will not accept ---------------------------------

# Per store: where its notes live, how long they may be, and which words may not
# appear in them. The limits are each store's own, minus a margin: Play cuts at
# 500 characters, Apple at 4000, Partner Center at 1500.
#
# The forbidden lists are deliberately asymmetric. Apple's stores must not be
# told about Android, Windows or Linux; Play must not be told about Apple's
# platforms. iOS and macOS are separated from each other as well — Hinata does
# ship on both, so naming one in the other's listing would probably pass review,
# but "probably passes review" is not worth a rejection that costs a week.
CHANNELS = {
    "ios": {
        "limit": 3800,
        "forbidden": ["android", "google play", "play store", "google",
                      "windows", "microsoft", "msix", "linux", "snap",
                      "flatpak", "appimage", "ubuntu",
                      "macos", "mac app store", "osx"],
    },
    "macos": {
        "limit": 3800,
        "forbidden": ["android", "google play", "play store", "google",
                      "windows", "microsoft", "msix", "linux", "snap",
                      "flatpak", "appimage", "ubuntu",
                      "ios", "ipados", "iphone", "ipad"],
    },
    "play": {
        "limit": 480,
        "forbidden": ["ios", "ipados", "iphone", "ipad", "macos", "mac app store",
                      "app store", "testflight", "apple", "osx",
                      "windows", "microsoft", "msix", "linux", "snap",
                      "flatpak", "appimage", "ubuntu"],
    },
    "windows": {
        "limit": 1400,
        "forbidden": ["ios", "ipados", "iphone", "ipad", "macos", "mac app store",
                      "app store", "testflight", "apple", "osx",
                      "android", "google play", "play store", "google",
                      "linux", "snap", "flatpak", "appimage", "ubuntu"],
    },
}

# Matched on word boundaries so "snapshot" is not "snap" and "Googlebot" would
# be, which is the safe direction. Built once per channel.
_FORBIDDEN_RE = {
    name: re.compile(r"\b(" + "|".join(re.escape(w) for w in cfg["forbidden"]) + r")\b",
                     re.I)
    for name, cfg in CHANNELS.items()
}

# Conventional-Commit types and scopes that never describe something a user of
# the app can notice. The scope matters as much as the type: a release-plumbing
# change is spelled `fix(release):` or `feat(ci):` — a real type over an
# internal scope — and matching the type alone let "Stop re-queueing the iOS
# version on every publish" through to a store listing.
_SKIP_TYPES = {"release", "chore", "ci", "build", "doc", "docs", "test", "tests",
               "style", "refactor", "merge", "bump", "wip", "revert"}
_SKIP_SCOPES = {"release", "ci", "build", "deps", "docs", "doc", "test", "tests",
                "packaging", "store", "fastlane", "workflow", "workflows"}

# The same set, anchored — for a subject that carries no Conventional prefix at
# all ("Merge pull request …", "Bump the Flutter version").
_SKIP = re.compile(r"^(" + "|".join(sorted(_SKIP_TYPES)) + r")\b", re.I)

# The type and scope of a Conventional subject, once the ticket id is out of the
# way: "HIN-59 fix(release): …" → ("fix", "release").
_TYPE_SCOPE = re.compile(r"^(?P<type>[a-z]+)(\((?P<scope>[^)]*)\))?!?:", re.I)

# "Revert "feat: …"" — git's own wording, and the subject it undid.
_REVERT = re.compile(r'^revert\s+"(?P<subject>.*)"\s*$', re.I | re.S)

# "This reverts commit 0123abc." in a revert commit's body.
_REVERTS_SHA = re.compile(r"^This reverts commit ([0-9a-f]{7,40})\.?\s*$", re.M)

# Developer addressing, removed wherever it appears rather than only at the
# front: "Revert "HIN-59 feat(release): …"" hid the ticket id behind a quote and
# a prefix, which is exactly how HIN-59 reached three storefronts.
_TICKET = re.compile(r"\[?\b[A-Z][A-Z0-9]{1,9}-\d+\b\]?[:\-–—\s]*")
_PR_REF = re.compile(r"\s*\(#\d+\)")
_CONV = re.compile(r"^(feat|feature|fix|bugfix|perf|improvement|improve|add|update|"
                   r"chore|refactor|docs?|tests?|style|build|ci|revert)"
                   r"(\([^)]*\))?!?:\s*", re.I)

# What a channel says when the release genuinely has nothing to announce to it,
# or when the gates removed everything. Honest and, being fixed text, incapable
# of failing review.
GENERIC = {
    "en": "• Improvements and bug fixes.",
    "de": "• Verbesserungen und Fehlerbehebungen.",
}


def sh(cmd: str) -> str:
    return subprocess.run(cmd, shell=True, capture_output=True, text=True,
                          cwd=ROOT).stdout.strip()


# --- reading the history ---------------------------------------------------

def _subject_of(sha: str) -> str:
    return sh(f"git log -1 --pretty=%s {sha} 2>/dev/null")


def commits_since(since: str | None) -> list[str]:
    """User-facing commit subjects since [since], reverts already cancelled out.

    A revert and the commit it undid describe a change the release does not
    contain, so both leave. 10.2.0's notes carried the pair — "Revert "…press
    the App Store release button…"" directly above "Press the App Store release
    button…" — which told readers the app both gained and lost a feature it
    never had.
    """
    if not since:
        since = sh("git describe --tags --abbrev=0 2>/dev/null")
    rng = f"{since}..HEAD" if since else "HEAD"
    # A record separator, so a body containing blank lines stays one record.
    raw = sh(f"git log {rng} --no-merges --pretty=format:'%H%x1f%s%x1f%b%x1e'")

    entries: list[tuple[str, str]] = []          # (sha, subject)
    reverted: set[str] = set()                   # normalised subjects to drop
    for record in raw.split("\x1e"):
        record = record.strip().strip("'")
        if not record:
            continue
        parts = record.split("\x1f")
        if len(parts) < 2:
            continue
        sha, subject, body = parts[0], parts[1].strip(), (parts[2] if len(parts) > 2 else "")
        match = _REVERT.match(subject)
        if match:
            reverted.add(_key(match.group("subject")))
            for undone in _REVERTS_SHA.findall(body):
                undone_subject = _subject_of(undone)
                if undone_subject:
                    reverted.add(_key(undone_subject))
            continue                              # the revert itself never ships
        entries.append((sha, subject))

    out: list[str] = []
    seen: set[str] = set()
    for _, subject in entries:
        key = _key(subject)
        if key in reverted or key in seen or _internal(subject):
            continue
        seen.add(key)
        cleaned = _scrub(subject)
        if cleaned:
            out.append(cleaned)
    return out


def _internal(subject: str) -> str | bool:
    """Whether [subject] describes work no user of the app can see."""
    stripped = _TICKET.sub("", subject.strip().strip('"')).strip()
    if _SKIP.match(stripped):
        return True
    match = _TYPE_SCOPE.match(stripped)
    if not match:
        return False
    return (match.group("type").lower() in _SKIP_TYPES
            or (match.group("scope") or "").lower() in _SKIP_SCOPES)


def _key(subject: str) -> str:
    """A subject reduced to what identifies it, so a revert finds its target.

    The two spellings are never identical: the revert quotes the subject as it
    was, while the original may have been merged with a PR number appended. So
    both sides are scrubbed and case-folded before they are compared.
    """
    return re.sub(r"\s+", " ", _scrub(subject)).strip().lower()


def _scrub(subject: str) -> str:
    """A commit subject with everything addressed to developers taken out."""
    text = subject.strip().strip('"')
    text = _CONV.sub("", text)
    text = _PR_REF.sub("", text)
    text = _TICKET.sub("", text)
    text = _CONV.sub("", text.strip())          # "HIN-59 feat(x): …" needs both
    text = re.sub(r"\s+", " ", text).strip(" .;:-–—")
    return (text[0].upper() + text[1:]) if text else ""


# --- the platform gate -----------------------------------------------------

def bullets(text: str) -> list[str]:
    """The lines of a note, however the source spelled its bullets."""
    out = []
    for line in text.splitlines():
        line = line.strip().lstrip("•-*–— ").strip()
        if line:
            out.append(line)
    return out


def _channel_safe(lines: list[str], channel: str) -> tuple[list[str], list[str]]:
    """[lines] minus every line naming a platform this store must not hear about.

    Returns (kept, dropped). Dropping the whole line rather than editing the
    word out is deliberate: "Lift the floating nav out of Android's navigation
    bar" with the word removed is not a sentence, and a change that is only
    about another platform is not news to this store's customers in any case.
    """
    pattern = _FORBIDDEN_RE[channel]
    kept, dropped = [], []
    for line in lines:
        (dropped if pattern.search(line) else kept).append(line)
    return kept, dropped


def render(lines: list[str], channel: str, language: str) -> str:
    """The finished note for one store in one language, gates applied."""
    kept, dropped = _channel_safe(lines, channel)
    for line in dropped:
        print(f"  [{channel}/{language}] dropped (other platform): {line}",
              file=sys.stderr)
    if not kept:
        return GENERIC[language]
    return _fit("\n".join(f"• {line}" for line in kept), CHANNELS[channel]["limit"])


def _fit(text: str, limit: int) -> str:
    """[text] cut to [limit], on a bullet boundary — never mid-sentence."""
    if len(text) <= limit:
        return text
    cut = text[:limit]
    return cut[:cut.rfind("\n")].rstrip() if "\n" in cut else cut.rstrip()


# --- the three sources -----------------------------------------------------

def handwritten(version: str | None) -> dict | None:
    """Release notes somebody wrote for this version, if the file exists."""
    if not version:
        return None
    path = os.path.join(ROOT, "release", "notes", f"{version}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        notes = json.load(f)
    if not (notes.get("en") and notes.get("de")):
        print(f"  ({path} has no en/de pair — ignoring it)", file=sys.stderr)
        return None
    print(f"  using hand-written notes from release/notes/{version}.json")
    return {"en": bullets(notes["en"]), "de": bullets(notes["de"])}


def llm_notes(subjects: list[str]) -> dict | None:
    """Commit subjects turned into user-facing copy, when a key is configured.

    The output is not trusted: it goes through the same platform gate as every
    other source, which is why the prompt asking for the same thing is a
    convenience rather than the safeguard.
    """
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key or not subjects:
        return None
    model = os.environ.get("CHANGELOG_MODEL", "claude-sonnet-5")
    prompt = (
        "You write 'What's New' release notes for Hinata, an open-source, "
        "self-hosted project & issue-tracking app (boards, sprints, Gantt, "
        "reports, wiki, comments).\n\nTurn these commit messages since the last "
        "release into concise, friendly, USER-FACING notes. A few bullet points, "
        "new features first, then improvements, then fixes. Drop internal-only, "
        "dev and CI churn, ticket IDs and jargon. No headings, no markdown.\n\n"
        "NEVER name an operating system, a device family or an app store "
        "(no iOS, iPadOS, macOS, Android, Windows, Linux, App Store, Google "
        "Play, Microsoft Store). The same text goes to four different stores and "
        "each one rejects a mention of the others. Describe the change itself.\n\n"
        "One line per bullet, no leading bullet character. Keep EACH language "
        "under 440 characters in total.\n\n"
        "Return STRICT JSON only: {\"en\": \"...\", \"de\": \"...\"} — English (US) "
        "and German (Deutschland, du-Form). Commits:\n- " + "\n- ".join(subjects)
    )
    body = json.dumps({
        "model": model,
        "max_tokens": 700,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                 "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)
        text = "".join(b.get("text", "") for b in data.get("content", []))
        notes = json.loads(re.search(r"\{.*\}", text, re.S).group(0))
        if notes.get("en") and notes.get("de"):
            print("  using Claude-written notes")
            return {"en": bullets(notes["en"]), "de": bullets(notes["de"])}
    except Exception as e:                                   # noqa: BLE001
        print(f"  (LLM changelog failed, using the deterministic fallback: {e})",
              file=sys.stderr)
    return None


def fallback_notes(subjects: list[str]) -> dict:
    """Notes derived from the commits alone.

    English is the commit subjects, scrubbed — they are terse but they are true,
    and the platform gate has already taken out the ones that belong to another
    store.

    German is deliberately generic. There is no translator on this path, and the
    alternative to a generic German line is an English one in the German
    listing, which is what 10.2.0 shipped. A reader who is told "Verbesserungen
    und Fehlerbehebungen" learns little; a reader shown English bullets under
    "Neues in dieser Version" learns the same little and sees a broken
    localisation. Write release/notes/<version>.json to do better than this —
    that is what the file is for.
    """
    if not subjects:
        return {"en": [], "de": []}
    print("  using the deterministic fallback (no ANTHROPIC_API_KEY, no "
          "release/notes/<version>.json)", file=sys.stderr)
    return {"en": subjects, "de": []}


# --- writing ---------------------------------------------------------------

def write_all(code: int, notes: dict) -> None:
    """One note per store per language, each rendered through its own gate."""
    plain = {}
    for lang, loc in (("en", "en-US"), ("de", "de-DE")):
        for channel, targets in (
            ("play", [f"android/fastlane/metadata/android/{loc}/changelogs/{code}.txt"]),
            ("ios", [f"ios/fastlane/metadata/{loc}/release_notes.txt"]),
            ("macos", [f"macos/fastlane/metadata/{loc}/release_notes.txt"]),
        ):
            text = render(notes[lang], channel, lang)
            for rel in targets:
                path = os.path.join(ROOT, rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text + "\n")
                print("  wrote", rel)
        plain[lang] = render(notes[lang], "windows", lang)
    _write_windows_listing(plain)


def _write_windows_listing(text_by_language: dict) -> None:
    """The Microsoft Store's own "What's new in this version", in listing.json.

    Written here rather than left to be pasted into Partner Center by hand,
    because a field that is filled in by hand is the field that carried a
    "Revert "…"" line into a live listing. ``windows/store/update_listing.py``
    pushes whatever keys this file holds, so adding the value is all that is
    needed for the next listing run to publish it.
    """
    path = os.path.join(ROOT, "windows", "store", "listing.json")
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        listing = json.load(f)
    for key, lang in (("en-us", "en"), ("de-de", "de")):
        if key in listing:
            listing[key]["releaseNotes"] = text_by_language[lang]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(listing, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("  wrote windows/store/listing.json (releaseNotes)")


# --- auditing what is already on disk ---------------------------------------

def check() -> int:
    """Report every store note on disk that names a platform it must not.

    A second pair of eyes on files that are generated but also editable, and the
    check a release can be gated on. Exit status is the number of offending
    files.
    """
    bad = 0
    roots = [("ios", "ios/fastlane/metadata"), ("macos", "macos/fastlane/metadata"),
             ("play", "android/fastlane/metadata/android")]
    for channel, base in roots:
        for dirpath, _, files in os.walk(os.path.join(ROOT, base)):
            for name in files:
                if name != "release_notes.txt" and not re.fullmatch(r"\d+\.txt", name):
                    continue
                path = os.path.join(dirpath, name)
                with open(path, encoding="utf-8") as f:
                    content = f.read()
                for line in bullets(content):
                    hit = _FORBIDDEN_RE[channel].search(line)
                    if hit:
                        rel = os.path.relpath(path, ROOT)
                        print(f"✗ {rel}: names '{hit.group(0)}' — {line}")
                        bad += 1
                    elif line.lower().startswith("revert"):
                        rel = os.path.relpath(path, ROOT)
                        print(f"✗ {rel}: is a revert — {line}")
                        bad += 1
    print("✓ every store note is free of other platforms" if not bad
          else f"✗ {bad} offending line(s)")
    return bad


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("versionCode", type=int, nargs="?")
    ap.add_argument("--since", default=None)
    ap.add_argument("--version", default=None)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true",
                    help="audit the notes already on disk and exit")
    a = ap.parse_args()

    if a.check:
        sys.exit(1 if check() else 0)
    if a.versionCode is None:
        ap.error("versionCode is required unless --check is given")

    subjects = commits_since(a.since)
    print(f"commits since {a.since or 'last tag'}: {len(subjects)}")
    notes = (handwritten(a.version) or llm_notes(subjects) or fallback_notes(subjects))

    for channel in CHANNELS:
        for lang in ("en", "de"):
            print(f"--- {channel} / {lang} ---")
            print(render(notes[lang], channel, lang))
    if a.write:
        write_all(a.versionCode, notes)
    else:
        print("(dry run — pass --write to update the store metadata)")


if __name__ == "__main__":
    main()
