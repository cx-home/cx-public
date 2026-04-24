#!/usr/bin/env python3
"""Minimal timing shim: outputs parse=X.XXX stream=X.XXX (median ms, medium fixture)."""
import sys, os, time
sys.path.insert(0, os.path.dirname(__file__))
import cxlib

with open(os.path.join(os.path.dirname(__file__), '..', '..', 'fixtures', 'bench', 'bench_medium.cx')) as f:
    medium = f.read()

def time_median(fn, n=100, warmup=20):
    for _ in range(warmup): fn()
    ts = []
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        ts.append((time.perf_counter() - t0) * 1000)
    ts.sort()
    return ts[n // 2]

parse_med  = time_median(lambda: cxlib.parse(medium))
stream_med = time_median(lambda: list(cxlib.stream(medium)))
print(f'parse={parse_med:.3f} stream={stream_med:.3f}')
