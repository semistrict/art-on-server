#!/usr/bin/env python3
"""Summarize per-benchmark JMH logs into a comparison table.

Reads <results>/<Class>.<method>.<config>.log for configs jdk26 / nocoops / art, extracts the
[Average] score, and prints a table with art-jit / OpenJDK ratios (AverageTime: lower = faster).
"""
import glob
import math
import os
import re
import sys

CONFIGS = [("jdk26", "jdk26"), ("nocoops", "jdk26-nocoops"), ("art", "art-jit")]


def score(path):
    if not os.path.exists(path):
        return None
    t = open(path, errors="ignore").read()
    if re.search(r"invalid reference|SIGSEGV|Aborted|Fatal signal", t):
        return "CRASH"
    m = re.search(r"([0-9.]+) ±\([0-9.]+%\) [0-9.]+ ([num]?s/op) \[Average\]", t)
    return (float(m.group(1)), m.group(2)) if m else None


def to_ns(v):
    if not isinstance(v, tuple):
        return None
    s, u = v
    return s * {"ns/op": 1, "us/op": 1000, "ms/op": 1_000_000, "s/op": 1_000_000_000}[u]


def cell(v):
    return f"{v[0]:.3f}" if isinstance(v, tuple) else (v or "-")


def main(res):
    shorts = sorted(
        {".".join(os.path.basename(p).split(".")[:2]) for p in glob.glob(os.path.join(res, "*.jdk26.log"))}
    )
    print(f"{'benchmark':<32}{'unit':>6}{'jdk26':>11}{'nocoops':>11}{'art-jit':>11}{'art/jdk26':>11}{'art/ncp':>9}")
    print("-" * 92)
    rj, rn = [], []
    for sh in shorts:
        vals = {c: score(os.path.join(res, f"{sh}.{c}.log")) for c, _ in CONFIGS}
        unit = next((v[1] for v in vals.values() if isinstance(v, tuple)), "")
        a, j, n = to_ns(vals["art"]), to_ns(vals["jdk26"]), to_ns(vals["nocoops"])
        sj = f"{a / j:.2f}x" if a and j else "-"
        sn = f"{a / n:.2f}x" if a and n else "-"
        if a and j:
            rj.append(a / j)
        if a and n:
            rn.append(a / n)
        print(f"{sh:<32}{unit:>6}{cell(vals['jdk26']):>11}{cell(vals['nocoops']):>11}{cell(vals['art']):>11}{sj:>11}{sn:>9}")
    print("-" * 92)
    if rj:
        print(f"geomean art-jit / jdk26 (compressed oops):  {math.exp(sum(map(math.log, rj)) / len(rj)):.2f}x  (n={len(rj)})")
    if rn:
        print(f"geomean art-jit / jdk26 -UseCompressedOops: {math.exp(sum(map(math.log, rn)) / len(rn)):.2f}x  (n={len(rn)})")
    print("AverageTime: lower = faster. ratio = art-jit / baseline (>1 => ART slower).")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
