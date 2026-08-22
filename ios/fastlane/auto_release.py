#!/usr/bin/env python3
"""Press "Release this version" the moment App Store Connect lets us.

    python ios/fastlane/auto_release.py --platform IOS --expect-version 10.1.0

Hinata's App Store versions are created with `automatic_release: false` (see the
`release` lane in ios/fastlane/Fastfile), which is what you want while a release
is being reviewed: approval and going live stay two separate decisions. The cost
is that an approved version does nothing at all until somebody opens App Store
Connect and presses a button. Apple approves when Apple approves — often outside
office hours — so that button can sit unpressed for a night, and on iOS, where
nothing has ever shipped, a night is a night the app does not exist.

This script is that button, and nothing else. It reads the current state, and in
exactly one of them — PENDING_DEVELOPER_RELEASE, the state that means "approved,
waiting for you" — it POSTs the release request. Every other state is reported
and left alone.

Deliberately quiet: a watcher that runs every quarter of an hour must exit 0 when
there is nothing to do, or "Apple is still reviewing" turns into a failed run and
an email, four times an hour, for days. Only a broken credential or a rejected
POST is an error here.

Credentials are the same three values every lane uses:
APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID, _API_KEY_CONTENT (base64 .p8).
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.ahmadre.hinata"

# What each App Store version state means for a watcher. The API hands back a
# single string and the difference between "wait", "act" and "a human is needed"
# is not obvious from the name — PENDING_APPLE_RELEASE and
# PENDING_DEVELOPER_RELEASE differ by one word and by who owns the next move.
ACTIONABLE = "PENDING_DEVELOPER_RELEASE"  # approved; the button is ours to press

LIVE = {
    "READY_FOR_DISTRIBUTION",  # on the store
}
IN_FLIGHT = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_APPLE_RELEASE",       # approved, Apple releases it on its own date
    "PROCESSING_FOR_DISTRIBUTION",  # we already pressed; it is on its way out
    "WAITING_FOR_EXPORT_COMPLIANCE",
}
NEEDS_A_HUMAN = {
    "REJECTED",
    "METADATA_REJECTED",
    "DEVELOPER_REJECTED",
    "INVALID_BINARY",
    "PREPARE_FOR_SUBMISSION",  # a draft nobody ever submitted
    "READY_FOR_REVIEW",        # items attached, Submit never pressed
}


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def token() -> str:
    kid = os.environ.get("APP_STORE_CONNECT_API_KEY_ID")
    iss = os.environ.get("APP_STORE_CONNECT_ISSUER_ID")
    key = os.environ.get("APP_STORE_CONNECT_API_KEY_CONTENT")
    if not (kid and iss and key):
        die("APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID / _API_KEY_CONTENT must be set")
    # The secret is stored base64-encoded on CI and as a plain .p8 locally.
    if "BEGIN PRIVATE KEY" not in key:
        key = base64.b64decode(key).decode()
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                      headers={"kid": kid, "typ": "JWT"})


class ASC:
    def __init__(self) -> None:
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token()}"

    def get(self, path: str, **params):
        r = self.s.get(f"{API}/{path}", params=params, timeout=60)
        if r.status_code >= 400:
            die(f"GET {path} -> {r.status_code}: {r.text[:600]}")
        return r.json()

    def post(self, path: str, body: dict):
        r = self.s.post(f"{API}/{path}", json=body, timeout=60)
        return r


def emit(**kv) -> None:
    """Publish the outcome as GitHub Actions step outputs.

    The workflow decides what to do next from these — pressing the button and
    shipping the follow-up release are two separate runs, so the state has to
    leave this process in a form a YAML `if:` can read.
    """
    for k, v in kv.items():
        print(f"{k}={v}")
    out = os.environ.get("GITHUB_OUTPUT")
    if not out:
        return
    with open(out, "a", encoding="utf-8") as f:
        for k, v in kv.items():
            f.write(f"{k}={v}\n")


def summary(markdown: str) -> None:
    """Append to the run summary, so a glance at the run says what happened."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as f:
        f.write(markdown.rstrip() + "\n")


def newest_version(asc: ASC, app_id: str, platform: str) -> dict | None:
    """The version record the store is currently working on for this platform.

    Sorted newest-first by version string rather than by creation date: a
    version record is created once and then lives through many submissions, so
    createdDate says when the number was first reserved, not how current it is.
    """
    data = asc.get(f"apps/{app_id}/appStoreVersions",
                   **{"filter[platform]": platform, "limit": 50})["data"]
    if not data:
        return None

    def key(v):
        raw = v["attributes"].get("versionString", "0")
        return tuple(int(p) if p.isdigit() else 0 for p in raw.split("."))

    return sorted(data, key=key, reverse=True)[0]


def release(asc: ASC, version_id: str) -> None:
    """POST the release request — the API form of the button.

    Creating an appStoreVersionReleaseRequest is the whole operation; there is
    no field to flip on the version itself. Apple answers 201 with an (otherwise
    useless) request object, and moves the version to
    PROCESSING_FOR_DISTRIBUTION. 409 is the answer when the version is not in a
    releasable state, which is the race this script can actually lose: Apple
    releases it from their side between our GET and our POST.
    """
    r = asc.post("appStoreVersionReleaseRequests", {
        "data": {
            "type": "appStoreVersionReleaseRequests",
            "relationships": {
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id},
                },
            },
        },
    })
    if r.status_code in (200, 201):
        return
    die(f"POST appStoreVersionReleaseRequests -> {r.status_code}: {r.text[:600]}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", default=BUNDLE_ID)
    ap.add_argument("--platform", default="IOS", choices=["IOS", "MAC_OS"])
    ap.add_argument("--expect-version", default="", metavar="X.Y.Z[,X.Y.Z...]",
                    help="the only version strings this run may release. More "
                         "than one is normal: a release train presses the button "
                         "for the version waiting today and again for its "
                         "successor a fortnight later")
    ap.add_argument("--allow-any-version", action="store_true",
                    help="release whatever is approved. Required to run without "
                         "--expect-version, so that forgetting the guard cannot "
                         "quietly turn into publishing anything at all")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would happen and change nothing")
    args = ap.parse_args(argv)

    allowed = [v.strip() for v in args.expect_version.split(",") if v.strip()]
    if not allowed and not args.allow_any_version:
        die("refusing to run without --expect-version. This script publishes to "
            "the public App Store; name the versions it may release, or pass "
            "--allow-any-version to say you meant it.")

    asc = ASC()
    apps = asc.get("apps", **{"filter[bundleId]": args.bundle_id})["data"]
    if not apps:
        die(f"no app with bundle id {args.bundle_id}")
    app_id = apps[0]["id"]

    version = newest_version(asc, app_id, args.platform)
    if not version:
        print(f"no {args.platform} version exists yet")
        emit(state="NONE", released="false", live="false", version="")
        return 0

    attrs = version["attributes"]
    state = attrs.get("appVersionState") or attrs.get("appStoreState") or "UNKNOWN"
    number = attrs.get("versionString", "")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    print(f"{args.platform} {number}: {state}  ({stamp})")

    if state in LIVE:
        emit(state=state, released="false", live="true", version=number)
        return 0

    if state != ACTIONABLE:
        # Nothing to press. Say which kind of waiting this is, because "Apple has
        # it" and "Apple bounced it back and is waiting on us" look identical
        # from a green check mark.
        if state in NEEDS_A_HUMAN:
            summary(f"### ⚠️ {args.platform} {number} — `{state}`\n\n"
                    f"App Store Connect is waiting on us, not on Apple. "
                    f"Nothing will happen here until somebody resolves it.\n")
        emit(state=state, released="false", live="false", version=number,
             blocked="true" if state in NEEDS_A_HUMAN else "false")
        return 0

    # Approved and held. The one case with something to do.
    if allowed and number not in allowed:
        # A guard, not a nicety: this process publishes to the public App Store
        # and cannot be undone from here. If the approved version is not one the
        # watcher was set up for, the safe move is to stop and let a person look.
        summary(f"### ⏸️ {args.platform} {number} is approved, but this watcher "
                f"only releases {', '.join(f'`{v}`' for v in allowed)}\n\n"
                f"Not releasing. Add it to `RELEASABLE_VERSIONS` in "
                f"`.github/workflows/appstore-auto-release.yml` if that is "
                f"what you want.\n")
        emit(state=state, released="false", live="false", version=number,
             blocked="true")
        return 0

    if args.dry_run:
        print(f"dry run: would release {args.platform} {number} ({version['id']})")
        emit(state=state, released="false", live="false", version=number)
        return 0

    release(asc, version["id"])
    print(f"released {args.platform} {number}")
    summary(f"### 🚀 Released {args.platform} **{number}** to the App Store\n\n"
            f"`{state}` → release requested at {stamp}. Apple now processes it "
            f"for distribution; it appears on the store within a few hours.\n")
    emit(state=state, released="true", live="false", version=number)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
