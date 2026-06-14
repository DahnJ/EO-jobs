#!/usr/bin/env python3
"""Cheap, no-LLM link-rot sweep over the DB.

Checks every company's `website` and `careers_urls` with a HEAD (falling back to
a ranged GET) and reports anything that doesn't resolve to a healthy page. Use
the output to decide which companies are worth spending a verification pass on,
and to flag dead careers links.

Writes a report to /tmp/linkrot.txt and prints a summary. Read-only on the DB.

Usage: python check_links.py [--listed-only] [--timeout 8] [--workers 16]
"""
import argparse
import concurrent.futures as cf
import urllib.request
import urllib.error

import db

UA = "Mozilla/5.0 (compatible; EO-jobs-linkcheck/1.0)"


def check(url: str, timeout: float) -> tuple:
    """Return (ok: bool, detail: str) for a URL."""
    if not url or not url.startswith("http"):
        return False, "no-url"
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=method,
                                         headers={"User-Agent": UA,
                                                  "Range": "bytes=0-2047"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return True, f"{resp.status}"
        except urllib.error.HTTPError as e:
            # 403/405 to HEAD is common; retry as GET before judging.
            if method == "HEAD" and e.code in (403, 405, 501):
                continue
            return (e.code < 400), f"HTTP {e.code}"
        except Exception as e:  # noqa: BLE001 — timeout, DNS, SSL, etc.
            if method == "HEAD":
                continue
            return False, type(e).__name__
    return False, "unreachable"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--listed-only", action="store_true")
    ap.add_argument("--timeout", type=float, default=8)
    ap.add_argument("--workers", type=int, default=16)
    args = ap.parse_args()

    targets = []  # (slug, kind, url)
    for p in sorted(db.DB.glob("*.md")):
        r = db.parse(p.read_text())
        if args.listed_only and not r.get("listed"):
            continue
        if r.get("website"):
            targets.append((p.stem, "website", r["website"]))
        for u in (r.get("careers_urls") or []):
            targets.append((p.stem, "careers", u))

    bad = []
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(check, url, args.timeout): (slug, kind, url)
                for slug, kind, url in targets}
        for fut in cf.as_completed(futs):
            slug, kind, url = futs[fut]
            ok, detail = fut.result()
            if not ok:
                bad.append((slug, kind, detail, url))

    bad.sort()
    report = "\n".join(f"{slug}\t{kind}\t{detail}\t{url}"
                       for slug, kind, detail, url in bad)
    open("/tmp/linkrot.txt", "w").write(report + "\n")
    print(f"checked {len(targets)} urls across "
          f"{len({t[0] for t in targets})} companies; {len(bad)} dead/unreachable")
    print("full report: /tmp/linkrot.txt")
    for slug, kind, detail, url in bad[:40]:
        print(f"  {slug:30} {kind:8} {detail:14} {url}")


if __name__ == "__main__":
    main()
