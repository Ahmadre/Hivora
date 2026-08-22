#!/usr/bin/env python3
"""What version is each of the five stores actually serving?

    python tool/store_status.py                # report
    python tool/store_status.py --expect 10.2.0  # and fail if one is behind

A green release run is not five shipped stores, and the gap between those two
things is wide enough to walk through. iOS can fall back to a TestFlight upload
and still finish green; a snap can upload and then sit in store review; the
Microsoft Store commits a submission that certification later rejects; Play can
refuse a production upload while every other job succeeds. All of that ends in
check marks. The only honest answer comes from asking the stores.

Every source here is the PUBLIC catalog — what a user's device would be offered.
That is deliberate:

  * it needs no credentials, so it runs on a laptop as well as on CI, and
  * publisher-side APIs answer a different question. App Store Connect keeps
    every superseded macOS version at READY_FOR_SALE, six of them here, so it
    cannot tell you which one is live. The catalog can.

Where a fact cannot be proven, this prints "unknown" rather than a guess.
"""
from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.request

BUNDLE_ID = "com.ahmadre.hinata"
PLAY_PACKAGE = "com.ahmadre.hinata"
SNAP_NAME = "hinata"
# The Store listing id, the one in the store.microsoft.com URL.
MS_PRODUCT_ID = "9N5NVNPKBBLR"

TIMEOUT = 30
UA = "hinata-store-status/1.0 (+https://github.com/hinata-platform/hinata-app)"

# A hostile or merely broken endpoint should not be able to make this allocate
# without limit. The largest legitimate body here is the Play listing at ~1.1 MB.
MAX_BODY = 8 * 1024 * 1024

# Named once so a branch cannot disagree with its own heading — every probe has
# a success path and at least one failure path, and they must report the same
# platform under the same name or the table quietly grows a sixth row.
IOS, MACOS, PLAY, WINDOWS, SNAP = (
    "iOS", "macOS", "Android (Play)", "Windows", "Linux (Snap)")
SRC_ITUNES = "iTunes lookup"
SRC_SNAP = "snapcraft.io API"
SRC_MS = "MS display catalog"
SRC_PLAY = "Play listing (scraped)"


# Everything a remote endpoint can throw at us. urllib.error.URLError covers a
# refused connection or DNS failure, but a stalled *read* raises TimeoutError,
# which is not one of its subclasses — catching only URLError means one slow
# store takes the other four answers down with it. Both derive from OSError, so
# that is the honest net; ValueError catches malformed JSON.
REMOTE_TROUBLE = (OSError, ValueError)


def fetch(url: str, headers: dict | None = None) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        body = r.read(MAX_BODY + 1)
    if len(body) > MAX_BODY:
        raise ValueError(f"response from {url} exceeds {MAX_BODY} bytes")
    return body


def fetch_json(url: str, headers: dict | None = None):
    return json.loads(fetch(url, headers))


class Result:
    """One platform's answer, with the receipt for it."""

    def __init__(self, platform: str, version: str | None, source: str,
                 detail: str = "", note: str = ""):
        self.platform = platform
        self.version = version          # None means: could not be established
        self.source = source
        self.detail = detail
        self.note = note


def apple(kind: str, label: str, entity: str) -> Result:
    """iOS and macOS share one bundle id, so the catalog is asked for both and
    the answers are told apart by `kind` — `software` is the iOS app,
    `mac-software` the Mac one. A bundle with no iOS app returns the Mac record
    for either entity, which is exactly how you learn iOS has never shipped.
    """
    url = (f"https://itunes.apple.com/lookup?bundleId={BUNDLE_ID}"
           f"&entity={entity}")
    try:
        data = fetch_json(url)
    except REMOTE_TROUBLE as e:
        return Result(label, None, SRC_ITUNES, note=f"lookup failed: {e}")

    for r in data.get("results", []):
        if r.get("kind") == kind:
            return Result(label, r.get("version"), SRC_ITUNES,
                          detail=f"released {r.get('currentVersionReleaseDate', '?')}")
    return Result(label, "—", SRC_ITUNES,
                  note="not in the public catalog — nothing has ever shipped here")


def snap() -> Result:
    """The Snap Store publishes its channel map, so this reports what
    `snap install` would actually give you, per architecture. Both have to
    match: a channel carrying two versions means one architecture was left
    behind by a half-finished publish.
    """
    try:
        data = fetch_json(f"https://api.snapcraft.io/v2/snaps/info/{SNAP_NAME}",
                          {"Snap-Device-Series": "16"})
    except REMOTE_TROUBLE as e:
        return Result(SNAP, None, SRC_SNAP, note=f"lookup failed: {e}")

    stable = {}
    for c in data.get("channel-map", []):
        ch = c.get("channel", {})
        if ch.get("risk") == "stable":
            stable[ch.get("architecture")] = (c.get("version"), c.get("revision"))
    if not stable:
        return Result(SNAP, "—", SRC_SNAP,
                      note="no stable channel — nothing released to stable")

    versions = {v for v, _ in stable.values()}
    detail = ", ".join(f"{a} rev{rev}" for a, (_, rev) in sorted(stable.items()))
    if len(versions) == 1:
        return Result(SNAP, versions.pop(), SRC_SNAP, detail=detail)
    return Result(SNAP, "/".join(sorted(versions)), SRC_SNAP, detail=detail,
                  note="architectures disagree — one of them was not published")


def windows() -> Result:
    """The Store's display catalog names the package, and the package name
    carries the version: `4hm4dr3.hinata_10.0.3.0_x64__<hash>`. Reading it out
    of the name beats decoding the packed integer next to it, which is four
    16-bit fields in one number.
    """
    url = (f"https://displaycatalog.mp.microsoft.com/v7.0/products/{MS_PRODUCT_ID}"
           f"?languages=en-us&market=US")
    try:
        data = fetch_json(url)
    except REMOTE_TROUBLE as e:
        return Result(WINDOWS, None, SRC_MS, note=f"lookup failed: {e}")

    found: dict[str, tuple[int, ...]] = {}
    for sku in data.get("Product", {}).get("DisplaySkuAvailabilities", []):
        for pkg in sku.get("Sku", {}).get("Properties", {}).get("Packages", []):
            m = re.search(r"_(\d+\.\d+\.\d+)\.\d+_(\w+)__",
                          pkg.get("PackageFullName", ""))
            if not m:
                continue
            arch, parts = m.group(2), tuple(int(p) for p in m.group(1).split("."))
            # Highest wins, not last-seen. The catalog can list more than one
            # package for an architecture, and JSON order is not a version order
            # — taking whichever came last makes the answer depend on how
            # Microsoft happened to serialise the response that morning.
            if parts > found.get(arch, ()):
                found[arch] = parts
    if not found:
        return Result(WINDOWS, None, SRC_MS,
                      note="no package in the catalog — is the listing live?")
    versions = {".".join(str(p) for p in v) for v in found.values()}
    return Result(WINDOWS, "/".join(sorted(versions)), SRC_MS,
                  detail=", ".join(sorted(found)))


def play() -> Result:
    """Play has no public API, so this reads the version out of the store page.

    Scraping is the weakest source here and it is labelled as such: Google
    reshapes that page without notice, and the page cannot tell a completed
    rollout from one that is still at 20%. It is enough to catch "Android was
    left behind entirely", which is the failure this tool exists to catch.
    """
    try:
        html = fetch(f"https://play.google.com/store/apps/details?id={PLAY_PACKAGE}",
                     {"Accept-Language": "en-US"}).decode("utf-8", "replace")
    except REMOTE_TROUBLE as e:
        return Result(PLAY, None, SRC_PLAY, note=f"fetch failed: {e}")

    # The About-this-app block: [[["10.1.0"]],[[[36]],...  — the version string
    # immediately followed by the minimum-SDK structure.
    m = re.search(r'\[\[\["(\d+\.\d+\.\d+)"\]\],\[\[\[\d+\]\]', html)
    if not m:
        return Result(PLAY, None, SRC_PLAY,
                      note="version not found on the page — the layout changed")
    return Result(PLAY, m.group(1), SRC_PLAY,
                  note="best effort; the page cannot show a staged rollout")


def render(results: list[Result]) -> None:
    """One row per store, with the note underneath where there is one."""
    width = max(len(r.platform) for r in results)
    print(f"{'platform'.ljust(width)}  version    source")
    print(f"{'-' * width}  ---------  ------")
    for r in results:
        shown = r.version if r.version is not None else "unknown"
        line = f"{r.platform.ljust(width)}  {shown:9}  {r.source}"
        if r.detail:
            line += f" ({r.detail})"
        print(line)
        if r.note:
            print(f"{' ' * width}  ↳ {r.note}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--expect", default="", metavar="X.Y.Z",
                    help="exit non-zero unless every store serves this version")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args(argv)

    results = [
        apple("software", IOS, "software"),
        apple("mac-software", MACOS, "macSoftware"),
        play(),
        windows(),
        snap(),
    ]

    if args.json:
        print(json.dumps([{"platform": r.platform, "version": r.version,
                           "source": r.source, "detail": r.detail, "note": r.note}
                          for r in results], indent=2))
    else:
        render(results)

    if not args.expect:
        return 0

    behind = [r for r in results if r.version != args.expect]
    if not behind:
        print(f"\nAll five stores serve {args.expect}.")
        return 0
    print(f"\nNot on {args.expect}: "
          + ", ".join(f"{r.platform} ({r.version or 'unknown'})" for r in behind))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
