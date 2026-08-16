#!/usr/bin/env python3
"""Replace the Store-listing screenshots of the pending Microsoft Store
submission, in every listing language, through the Store submission API.

    python windows/store/update_listing.py [--commit] [--dry-run]
                                           [--languages en-us,de-de]

Credentials come from the environment (the same four values the msstore CLI
uses, see release/MANUAL_STEPS_WINDOWS.md):

    AZURE_AD_TENANT_ID  AZURE_AD_APPLICATION_CLIENT_ID
    AZURE_AD_APPLICATION_SECRET  MSSTORE_PRODUCT_ID (optional, defaults below)

Flow (Microsoft Store submission API v1, "manage app submissions"):
  1. client-credentials token for https://manage.devcenter.microsoft.com
  2. GET the app  -> the pending submission id
  3. GET the submission, swap `Screenshot` images for the ones in screenshots/
     (old ones go to PendingDelete, new ones to PendingUpload)
  4. PUT the submission back
  5. PUT a ZIP of the new images to the submission's SAS `fileUploadUrl`
  6. POST /commit (only with --commit) and poll until certification starts

Why the API and not the msstore CLI: `msstore publish` uploads *packages*. Store
listing content - screenshots, captions - is only reachable through this API.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
import zipfile

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "screenshots")
CAPTIONS = os.path.join(HERE, "captions.json")

API = "https://manage.devcenter.microsoft.com/v1.0/my"
RESOURCE = "https://manage.devcenter.microsoft.com"
# Public Store ID (the id in https://apps.microsoft.com/detail/9N5NVNPKBBLR).
PRODUCT_ID = os.environ.get("MSSTORE_PRODUCT_ID") or "9N5NVNPKBBLR"

# Desktop screenshots. The other image types on the listing (store logos) are
# left exactly as they are.
IMAGE_TYPE = "Screenshot"


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def token():
    tenant = os.environ.get("AZURE_AD_TENANT_ID")
    client = os.environ.get("AZURE_AD_APPLICATION_CLIENT_ID")
    secret = os.environ.get("AZURE_AD_APPLICATION_SECRET")
    if not (tenant and client and secret):
        die("AZURE_AD_TENANT_ID / _APPLICATION_CLIENT_ID / _APPLICATION_SECRET "
            "must be set")
    r = requests.post(
        f"https://login.microsoftonline.com/{tenant}/oauth2/token",
        data={"grant_type": "client_credentials", "client_id": client,
              "client_secret": secret, "resource": RESOURCE}, timeout=30)
    if r.status_code != 200:
        die(f"token request failed ({r.status_code}): {r.text[:400]}")
    return r.json()["access_token"]


class Store:
    def __init__(self, access):
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {access}",
                               "Content-type": "application/json"})

    def _call(self, method, path, **kw):
        r = self.s.request(method, f"{API}{path}", timeout=120, **kw)
        if r.status_code >= 400:
            die(f"{method} {path} -> {r.status_code}: {r.text[:1200]}")
        return r.json() if r.content else {}

    def app(self):
        return self._call("GET", f"/applications/{PRODUCT_ID}")

    def submission(self, sid):
        return self._call("GET", f"/applications/{PRODUCT_ID}/submissions/{sid}")

    def update(self, sid, body):
        """False when the Store refuses the edit because an ingestion run holds
        the submission (409 InvalidState). That clears once the run ends, so it
        is a "come back later", not a failure."""
        r = self.s.put(f"{API}/applications/{PRODUCT_ID}/submissions/{sid}",
                       data=json.dumps(body), timeout=120)
        if r.status_code == 409 and "InvalidState" in r.text:
            print(f"  busy: {r.json().get('message')}")
            return False
        if r.status_code >= 400:
            die(f"PUT submission -> {r.status_code}: {r.text[:1200]}")
        return True

    def commit(self, sid):
        return self._call(
            "POST", f"/applications/{PRODUCT_ID}/submissions/{sid}/commit")

    def status(self, sid):
        return self._call(
            "GET", f"/applications/{PRODUCT_ID}/submissions/{sid}/status")


def outcome(value):
    """Report what happened to the caller (a workflow step reads this)."""
    print(f"outcome: {value}")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(f"outcome={value}\n")
    return 0


def load_shots():
    with open(CAPTIONS, encoding="utf-8") as f:
        cfg = json.load(f)
    shots = cfg["screenshots"]
    for s in shots:
        path = os.path.join(SHOTS, s["file"])
        if not os.path.exists(path):
            die(f"missing screenshot {path}")
        for lang, cap in s["captions"].items():
            if len(cap) > 200:
                die(f"caption for {s['file']} [{lang}] is {len(cap)} chars (max 200)")
    return shots, cfg.get("notesForCertification", "")


def already_applied(listing, shots):
    """True when this listing already carries exactly these screenshots."""
    live = {i["fileName"] for i in listing["baseListing"].get("images", [])
            if i.get("imageType") == IMAGE_TYPE
            and i.get("fileStatus") != "PendingDelete"}
    return live == {s["file"] for s in shots}


def swap_images(listing, shots, lang):
    """Old desktop screenshots out, the new ones in — logos are left alone."""
    base = listing["baseListing"]
    kept, retired = [], 0
    for img in base.get("images", []):
        if img.get("imageType") != IMAGE_TYPE:
            kept.append(img)
            continue
        if img.get("fileStatus") != "PendingDelete":
            retired += 1
        img["fileStatus"] = "PendingDelete"
        kept.append(img)
    for s in shots:
        kept.append({
            "fileName": s["file"],
            "fileStatus": "PendingUpload",
            "imageType": IMAGE_TYPE,
            "description": s["captions"].get(lang, s["captions"]["en-us"]),
        })
    base["images"] = kept
    return retired


def zip_images(shots):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for s in shots:
            z.write(os.path.join(SHOTS, s["file"]), s["file"])
    return buf.getvalue()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true",
                    help="commit the submission (starts certification)")
    ap.add_argument("--dry-run", action="store_true",
                    help="show what would change; touch nothing")
    ap.add_argument("--languages", default="",
                    help="comma-separated listing languages (default: all)")
    ap.add_argument("--tolerate-busy", action="store_true",
                    help="exit 0 when the submission is locked by an ingestion "
                         "run (for the scheduled retry)")
    args = ap.parse_args(argv)

    shots, notes = load_shots()
    store = Store(token())

    app = store.app()
    pending = app.get("pendingApplicationSubmission")
    if pending:
        sid = pending["id"]
    elif app.get("lastPublishedApplicationSubmission"):
        # Nothing open: clone the published one, which is what Partner Center's
        # "new submission" button does.
        sid = store._call("POST", f"/applications/{PRODUCT_ID}/submissions")["id"]
        print(f"created submission {sid} from the published listing")
    else:
        die("the app has no pending submission and has never been published — "
            "create the submission in Partner Center first")
    sub = store.submission(sid)
    published = (app.get("lastPublishedApplicationSubmission") or {}).get("id")
    print(f"app {PRODUCT_ID} · submission {sid} · status {sub.get('status')} · "
          f"last published {published or 'never'}")
    for e in sub.get("statusDetails", {}).get("errors", []):
        print(f"  ! {e.get('code')}: {e.get('details')}")
    # Committing sends whatever package the submission already holds to
    # certification — say which one, so nobody ships an unexpected build.
    for p in sub.get("applicationPackages", []):
        print(f"  package {p.get('fileName')} {p.get('version')} "
              f"({p.get('fileStatus')})")

    wanted = [l.strip().lower() for l in args.languages.split(",") if l.strip()]
    listings = sub.get("listings", {})
    langs = [l for l in listings if not wanted or l.lower() in wanted]
    missing = [l for l in wanted if l not in {k.lower() for k in listings}]
    if missing:
        die(f"no store listing for {', '.join(missing)} — the listing has "
            f"{', '.join(sorted(listings)) or 'none'}")
    if not langs:
        die("submission has no store listings")

    if all(already_applied(listings[l], shots) for l in langs):
        print("listings already carry these screenshots — nothing to do")
        return outcome("already-applied")

    for lang in langs:
        retired = swap_images(listings[lang], shots, lang.lower())
        print(f"  {lang}: {retired} screenshot(s) removed, {len(shots)} added")

    if notes and notes not in (sub.get("notesForCertification") or ""):
        existing = (sub.get("notesForCertification") or "").strip()
        sub["notesForCertification"] = f"{existing}\n\n{notes}".strip()

    if args.dry_run:
        print("dry run — nothing sent")
        return outcome("dry-run")

    if not store.update(sid, sub):
        print("the submission is being ingested right now and cannot be edited; "
              "it becomes editable again when that run ends (certification "
              "passed or failed). Re-run this then.")
        return outcome("busy") if args.tolerate_busy else 1
    print("submission updated")

    blob = zip_images(shots)
    r = requests.put(sub["fileUploadUrl"].replace("+", "%2B"), data=blob,
                     headers={"x-ms-blob-type": "BlockBlob"}, timeout=600)
    if r.status_code not in (200, 201):
        die(f"image upload failed ({r.status_code}): {r.text[:400]}")
    print(f"uploaded {len(shots)} images ({len(blob) / 1e6:.1f} MB zip)")

    if not args.commit:
        print("not committed (--commit to submit for certification)")
        return outcome("uploaded")

    store.commit(sid)
    for _ in range(60):
        st = store.status(sid)
        state = st.get("status")
        print(f"  status: {state}")
        if state not in ("CommitStarted", "PendingCommit"):
            for e in st.get("statusDetails", {}).get("errors", []):
                print(f"  ! {e.get('code')}: {e.get('details')}")
            if state in ("CommitFailed", "PreProcessingFailed",
                         "CertificationFailed", "PublishFailed", "ReleaseFailed"):
                die(f"submission ended in {state}")
            print("committed — certification is running")
            return outcome("committed")
        time.sleep(15)
    print("still committing; check Partner Center")
    return outcome("committed")


if __name__ == "__main__":
    raise SystemExit(main())
