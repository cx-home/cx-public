#!/usr/bin/env python3
"""
CX performance benchmark — Python binding.

Measures parse, stream, round-trip, conversion, and data-binding operations
across three document sizes. Run from the repo root:
    python python/bench.py
"""
import sys, os, time, json

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from cxlib import cx as _cx  # noqa: E402
import cxlib                  # noqa: E402

# ── fixture loader ─────────────────────────────────────────────────────────────

_BENCH = os.path.join(os.path.dirname(__file__), '..', '..', 'fixtures', 'bench')

def _load(name):
    with open(os.path.join(_BENCH, name)) as f:
        return f.read()

SMALL  = _load('bench_small.cx')
MEDIUM = _load('bench_medium.cx')
LARGE  = _load('bench_large.cx')

# ── timer ──────────────────────────────────────────────────────────────────────

def bench(name, fn, n=200, warmup=20):
    for _ in range(warmup):
        fn()
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        times.append((time.perf_counter() - t0) * 1000)
    times.sort()
    mn  = times[0]
    med = times[n // 2]
    mx  = times[-1]
    print(f'  {name:<32s}  min={mn:7.3f}ms  med={med:7.3f}ms  max={mx:7.3f}ms')

# ── benchmark groups ───────────────────────────────────────────────────────────

def run_group(label, cx_str):
    print(f'\n── {label} ({len(cx_str):,} bytes) ──')

    # Document API
    bench('parse (CX → Document)',       lambda: cxlib.parse(cx_str))
    bench('to_cx (CX → CX round-trip)',  lambda: _cx.to_cx(cx_str))

    # Streaming
    bench('stream (CX → all events)',    lambda: list(cxlib.stream(cx_str)))

    # Format conversion
    bench('to_json (CX → JSON)',         lambda: _cx.to_json(cx_str))
    bench('to_xml  (CX → XML)',          lambda: _cx.to_xml(cx_str))
    bench('to_yaml (CX → YAML)',         lambda: _cx.to_yaml(cx_str))
    bench('to_toml (CX → TOML)',         lambda: _cx.to_toml(cx_str))

    # Data binding
    bench('loads   (CX → native dict)',  lambda: cxlib.loads(cx_str))
    json_str = _cx.to_json(cx_str)
    bench('dumps   (dict → CX)',         lambda: cxlib.dumps(json.loads(json_str)))

    # CXPath + transform
    doc = cxlib.parse(cx_str)
    bench('select_all //service',       lambda: doc.select_all('//service'))
    bench('transform  services/service', lambda: doc.transform('services/service', lambda el: el))

    # Reverse conversion
    xml_str = _cx.to_xml(cx_str)
    bench('xml→cx  (XML → CX)',          lambda: _cx.xml_to_cx(xml_str))


if __name__ == '__main__':
    print(f'CX Python benchmark  (version: {cxlib.version()})')

    run_group('small  (20 services)',   SMALL)
    run_group('medium (200 services)',  MEDIUM)
    run_group('large  (2000 services)', LARGE)

    print()
