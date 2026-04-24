#!/usr/bin/env python3
"""Python conformance runner — delegates to libcx via ctypes."""
import sys, os, json
sys.path.insert(0, os.path.dirname(__file__))

from cxlib.cx import (
    to_cx, to_xml, to_ast, to_json, to_md,
    xml_to_cx, xml_to_xml, xml_to_ast, xml_to_json, xml_to_md,
    md_to_cx, md_to_xml, md_to_ast, md_to_json, md_to_md,
)

MULTIDOC_SEP = '\n---\n'

# ── suite parser ─────────────────────────────────────────────────────────────

def parse_suite(path):
    tests, cur, section, buf = [], None, None, []

    def flush():
        if cur is not None and section is not None:
            lines = buf[:]
            while lines and not lines[0].strip():  lines.pop(0)
            while lines and not lines[-1].strip(): lines.pop()
            cur['sections'][section] = '\n'.join(lines)
        buf.clear()

    with open(path) as f:
        for raw in f:
            raw = raw.rstrip('\n')
            if raw.startswith('=== test:'):
                flush()
                if cur: tests.append(cur)
                cur = {'name': raw[9:].strip(), 'sections': {}}
                section = None
            elif raw.startswith('level:') and cur:
                cur['level'] = raw[6:].strip()
            elif raw.startswith('tags:') and cur:
                cur['tags'] = raw[5:].strip().split()
            elif raw.startswith('--- ') and cur:
                flush()
                section = raw[4:].strip()
            elif section and cur:
                buf.append(raw)

    flush()
    if cur: tests.append(cur)
    return tests

# ── test runner ───────────────────────────────────────────────────────────────

def run_test(t):
    failures = []
    s = t['sections']

    if   'in_cx'  in s: src, fmt = s['in_cx'],  'cx'
    elif 'in_xml' in s: src, fmt = s['in_xml'], 'xml'
    elif 'in_md'  in s: src, fmt = s['in_md'],  'md'
    else: return failures  # no input — skip

    if fmt == 'xml':
        emit_cx, emit_xml, emit_ast, emit_json, emit_md = xml_to_cx, xml_to_xml, xml_to_ast, xml_to_json, xml_to_md
    elif fmt == 'md':
        emit_cx, emit_xml, emit_ast, emit_json, emit_md = md_to_cx, md_to_xml, md_to_ast, md_to_json, md_to_md
    else:
        emit_cx, emit_xml, emit_ast, emit_json, emit_md = to_cx, to_xml, to_ast, to_json, to_md

    def call(fn, text):
        try:
            return fn(text), None
        except RuntimeError as e:
            return None, str(e)

    # ── out_ast ───────────────────────────────────────────────────────────────
    if 'out_ast' in s:
        out, err = call(emit_ast, src)
        if err:
            failures.append(f'out_ast parse error: {err}')
        else:
            expected = json.loads(s['out_ast'])
            got = json.loads(out)
            if expected != got:
                failures.append(
                    f'out_ast mismatch\n  expected: {json.dumps(expected, indent=2)}\n  got:      {json.dumps(got, indent=2)}'
                )

    # ── out_xml ───────────────────────────────────────────────────────────────
    if 'out_xml' in s:
        out, err = call(emit_xml, src)
        if err:
            failures.append(f'out_xml parse error: {err}')
        elif s['out_xml'].strip() != out.strip():
            failures.append(f'out_xml mismatch\n  expected:\n{s["out_xml"]}\n  got:\n{out}')

    # ── out_cx ────────────────────────────────────────────────────────────────
    if 'out_cx' in s:
        out, err = call(emit_cx, src)
        if err:
            failures.append(f'out_cx parse error: {err}')
        elif s['out_cx'].strip() != out.strip():
            failures.append(f'out_cx mismatch\n  expected:\n{s["out_cx"]}\n  got:\n{out}')

    # ── out_json ──────────────────────────────────────────────────────────────
    if 'out_json' in s:
        out, err = call(emit_json, src)
        if err:
            failures.append(f'out_json parse error: {err}')
        else:
            expected = json.loads(s['out_json'])
            got = json.loads(out)
            if expected != got:
                failures.append(
                    f'out_json mismatch\n  expected: {json.dumps(expected, indent=2)}\n  got:      {json.dumps(got, indent=2)}'
                )

    # ── out_md ────────────────────────────────────────────────────────────────
    if 'out_md' in s:
        out, err = call(emit_md, src)
        if err:
            failures.append(f'out_md parse error: {err}')
        elif s['out_md'].strip() != out.strip():
            failures.append(f'out_md mismatch\n  expected:\n{s["out_md"]}\n  got:\n{out}')

    return failures

# ── suite runner ──────────────────────────────────────────────────────────────

def run_suite(path):
    tests = parse_suite(path)
    passed = failed = 0
    for t in tests:
        try:
            failures = run_test(t)
        except Exception as e:
            failures = [f'runner exception: {e}']
        if failures:
            failed += 1
            print(f'FAIL  {t["name"]}')
            for f in failures:
                for line in f.splitlines():
                    print(f'      {line}')
        else:
            passed += 1
    print(f'{path}: {passed} passed, {failed} failed')
    return failed

# ── entry point ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    base = os.path.join(os.path.dirname(__file__), '..', '..', 'conformance')
    suites = sys.argv[1:] or [
        os.path.join(base, 'core.txt'),
        os.path.join(base, 'extended.txt'),
        os.path.join(base, 'xml.txt'),
        os.path.join(base, 'md.txt'),
    ]
    total_failed = sum(run_suite(s) for s in suites)
    sys.exit(1 if total_failed else 0)
