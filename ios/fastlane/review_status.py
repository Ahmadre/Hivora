#!/usr/bin/env python3
"""Report what App Store Connect actually thinks is going on with our reviews.

    python ios/fastlane/review_status.py [--bundle-id com.ahmadre.hinata]

Prints, per platform, every recent version with its state, and every review
submission with its state, submission date and items. That distinguishes the
three things that all look like "Apple is not reviewing us" from the outside:

  * the version is still a draft — never submitted (state PREPARE_FOR_SUBMISSION
    with no review submission),
  * the submission exists but was never *sent* (state READY_FOR_REVIEW: items are
    attached, the Submit button was not pressed),
  * the submission really is queued at Apple (WAITING_FOR_REVIEW / IN_REVIEW),
    in which case the submitted date says how long it has been sitting there.

Credentials are the same three values the fastlane lanes use:
APP_STORE_CONNECT_API_KEY_ID, _ISSUER_ID, _API_KEY_CONTENT (base64 .p8).
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.ahmadre.hinata"


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def token():
    kid = os.environ.get("APP_STORE_CONNECT_API_KEY_ID")
    iss = os.environ.get("APP_STORE_CONNECT_ISSUER_ID")
    key = os.environ.get("APP_STORE_CONNECT_API_KEY_CONTENT")
    if not (kid and iss and key):
        die("APP_STORE_CONNECT_API_KEY_ID / _ISSUER_ID / _API_KEY_CONTENT must be set")
    if "BEGIN PRIVATE KEY" not in key:
        key = base64.b64decode(key).decode()
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                      headers={"kid": kid, "typ": "JWT"})


class ASC:
    def __init__(self):
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token()}"

    def get(self, path, **params):
        r = self.s.get(f"{API}/{path}", params=params, timeout=60)
        if r.status_code >= 400:
            die(f"GET {path} -> {r.status_code}: {r.text[:600]}")
        return r.json()


def ago(stamp):
    if not stamp:
        return ""
    when = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    days = (dt.datetime.now(dt.timezone.utc) - when).total_seconds() / 86400
    return f"{when:%Y-%m-%d %H:%M} UTC ({days:.1f} days ago)"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-id", default=BUNDLE_ID)
    args = ap.parse_args(argv)

    asc = ASC()
    apps = asc.get("apps", **{"filter[bundleId]": args.bundle_id})["data"]
    if not apps:
        die(f"no app with bundle id {args.bundle_id}")
    app = apps[0]
    app_id = app["id"]
    print(f"{app['attributes']['name']} ({args.bundle_id}) · app {app_id}\n")

    print("VERSIONS")
    versions = asc.get(f"apps/{app_id}/appStoreVersions", limit=10)["data"]
    for v in versions:
        a = v["attributes"]
        state = a.get("appVersionState") or a.get("appStoreState")
        print(f"  {a['platform']:16} {a['versionString']:10} {state:28} "
              f"created {ago(a.get('createdDate'))}")

    print("\nREVIEW SUBMISSIONS")
    subs = asc.get("reviewSubmissions", **{"filter[app]": app_id,
                                           "limit": 10, "include": "items"})
    items = {i["id"]: i for i in subs.get("included", [])}
    if not subs["data"]:
        print("  none — nothing has been sent to App Review")
    for s in subs["data"]:
        a = s["attributes"]
        print(f"  {a['platform']:16} {a['state']:24} "
              f"submitted {ago(a.get('submittedDate')) or 'never'}")
        for ref in s["relationships"]["items"]["data"]:
            it = items.get(ref["id"], {}).get("attributes", {})
            kinds = [k for k in ("appStoreVersion", "appCustomProductPage",
                                 "appEvent") if k in it]
            print(f"      item {ref['id']} {it.get('state', '')} "
                  f"{' '.join(kinds)}")
        if a.get("canceled"):
            print("      ! canceled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
