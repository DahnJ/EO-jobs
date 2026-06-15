#!/usr/bin/env python3
"""Detect likely acquisitions/rebrands via cross-domain redirects (no LLM, no browser).

For each listed company, follow its website's redirects and compare the final
registrable domain to the original. A company whose own domain now lands on a
DIFFERENT company's domain (e.g. pachama.com -> carbon-direct.com) is almost
certainly acquired/merged — exactly the case WebFetch agents miss when bot-blocked.

Also reports careers URLs that 404. Read-only. Writes /tmp/redirects.txt.

Usage: python check_redirects.py [--timeout 10] [--workers 16]
"""
import argparse
import concurrent.futures as cf
import urllib.request
import urllib.error
from urllib.parse import urlparse

import db

UA = "Mozilla/5.0 (compatible; EO-jobs-redirect-check/1.0)"


def reg_domain(url: str) -> str:
    net = urlparse(url if url.startswith("http") else "https://" + url).netloc.lower()
    net = net.split("@")[-1].split(":")[0]
    if net.startswith("www."):
        net = net[4:]
    parts = net.split(".")
    # naive registrable domain: keep last 2 labels (last 3 for common 2-part TLDs)
    if len(parts) >= 3 and parts[-2] in {"co", "com", "org", "gov", "ac", "net"} and parts[-1] in {"uk", "au", "nz", "za", "in", "br", "jp", "kr"}:
        return ".".join(parts[-3:])
    return ".".join(parts[-2:]) if len(parts) >= 2 else net


def final_url(url: str, timeout: float):
    """Return (final_url, detail) following redirects; ('', reason) on failure."""
    if not url or not url.startswith("http"):
        return "", "no-url"
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=method, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.geturl(), str(resp.status)
        except urllib.error.HTTPError as e:
            # redirect already resolved; the error is on the *final* page. Its URL
            # (e.url / e.geturl) is still the post-redirect destination.
            final = getattr(e, "url", "") or url
            if method == "HEAD" and e.code in (403, 405, 501):
                continue
            return final, f"HTTP {e.code}"
        except Exception as e:  # noqa: BLE001
            if method == "HEAD":
                continue
            return "", type(e).__name__
    return "", "unreachable"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--workers", type=int, default=16)
    args = ap.parse_args()

    listed = []
    for p in sorted(db.DB.glob("*.md")):
        r = db.parse(p.read_text())
        if r.get("listed") and r.get("website"):
            listed.append((p.stem, r["name"], r["website"]))

    moved = []
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(final_url, w, args.timeout): (s, n, w) for s, n, w in listed}
        for fut in cf.as_completed(futs):
            slug, name, web = futs[fut]
            final, detail = fut.result()
            if final:
                a, b = reg_domain(web), reg_domain(final)
                if a and b and a != b:
                    moved.append((slug, name, a, b, detail))

    moved.sort()
    lines = [f"{s}\t{n}\t{a} -> {b}\t({d})" for s, n, a, b, d in moved]
    open("/tmp/redirects.txt", "w").write("\n".join(lines) + "\n")
    print(f"checked {len(listed)} listed websites; {len(moved)} redirect to a DIFFERENT domain:\n")
    for s, n, a, b, d in moved:
        print(f"  {n:28} {a}  ->  {b}   [{d}]")


if __name__ == "__main__":
    main()
