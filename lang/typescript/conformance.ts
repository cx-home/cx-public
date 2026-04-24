/**
 * CX TypeScript conformance runner.
 * Run: cd typescript/cxlib && npm run conform
 */
import * as cx from './cxlib/src/index';
import * as fs from 'fs';
import * as path from 'path';

// ── suite parser ──────────────────────────────────────────────────────────────

interface TestCase {
  name: string;
  sections: Record<string, string>;
}

function parseSuite(filePath: string): TestCase[] {
  const lines = fs.readFileSync(filePath, 'utf8').split('\n');
  const tests: TestCase[] = [];
  let cur: TestCase | null = null;
  let section: string | null = null;
  let buf: string[] = [];

  function flush(): void {
    if (cur && section !== null) {
      let lines = [...buf];
      while (lines.length > 0 && lines[0].trim() === '') lines.shift();
      while (lines.length > 0 && lines[lines.length - 1].trim() === '') lines.pop();
      cur.sections[section] = lines.join('\n');
    }
    buf = [];
  }

  for (const raw of lines) {
    const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
    if (line.startsWith('=== test:')) {
      flush();
      if (cur) tests.push(cur);
      cur = { name: line.slice(9).trim(), sections: {} };
      section = null;
    } else if (line.startsWith('--- ') && cur) {
      flush();
      section = line.slice(4).trim();
    } else if (section !== null && cur) {
      buf.push(line);
    }
  }
  flush();
  if (cur) tests.push(cur);
  return tests;
}

// ── dispatch ──────────────────────────────────────────────────────────────────

type ConvFn = (s: string) => string;

function dispatch(inFmt: string, outFmt: string): ConvFn | undefined {
  const table: Record<string, ConvFn> = {
    'cx:cx':     cx.toCx,     'cx:xml':    cx.toXml,    'cx:ast':    cx.toAst,
    'cx:json':   cx.toJson,   'cx:yaml':   cx.toYaml,   'cx:toml':   cx.toToml,  'cx:md':     cx.toMd,
    'xml:cx':    cx.xmlToCx,  'xml:xml':   cx.xmlToXml, 'xml:ast':   cx.xmlToAst,
    'xml:json':  cx.xmlToJson,'xml:yaml':  cx.xmlToYaml,'xml:toml':  cx.xmlToToml,'xml:md':   cx.xmlToMd,
    'json:cx':   cx.jsonToCx, 'json:xml':  cx.jsonToXml,'json:ast':  cx.jsonToAst,
    'json:json': cx.jsonToJson,'json:yaml': cx.jsonToYaml,'json:toml': cx.jsonToToml,'json:md': cx.jsonToMd,
    'yaml:cx':   cx.yamlToCx, 'yaml:xml':  cx.yamlToXml,'yaml:ast':  cx.yamlToAst,
    'yaml:json': cx.yamlToJson,'yaml:yaml': cx.yamlToYaml,'yaml:toml': cx.yamlToToml,'yaml:md': cx.yamlToMd,
    'toml:cx':   cx.tomlToCx, 'toml:xml':  cx.tomlToXml,'toml:ast':  cx.tomlToAst,
    'toml:json': cx.tomlToJson,'toml:yaml': cx.tomlToYaml,'toml:toml': cx.tomlToToml,'toml:md': cx.tomlToMd,
    'md:cx':     cx.mdToCx,   'md:xml':    cx.mdToXml,  'md:ast':    cx.mdToAst,
    'md:json':   cx.mdToJson, 'md:yaml':   cx.mdToYaml, 'md:toml':   cx.mdToToml, 'md:md':    cx.mdToMd,
  };
  return table[`${inFmt}:${outFmt}`];
}

// ── test runner ───────────────────────────────────────────────────────────────

function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((v, i) => deepEqual(v, (b as unknown[])[i]));
  }
  const aObj = a as Record<string, unknown>;
  const bObj = b as Record<string, unknown>;
  const aKeys = Object.keys(aObj).sort();
  const bKeys = Object.keys(bObj).sort();
  if (aKeys.join('\0') !== bKeys.join('\0')) return false;
  return aKeys.every(k => deepEqual(aObj[k], bObj[k]));
}

function jsonEq(a: string, b: string): boolean {
  try {
    return deepEqual(JSON.parse(a), JSON.parse(b));
  } catch { return false; }
}

function runTest(t: TestCase): string[] {
  const failures: string[] = [];
  const s = t.sections;

  let src = '', inFmt = '';
  for (const [key, fmt] of [
    ['in_cx','cx'], ['in_xml','xml'], ['in_json','json'],
    ['in_yaml','yaml'], ['in_toml','toml'], ['in_md','md'],
  ] as [string, string][]) {
    if (key in s) { src = s[key]; inFmt = fmt; break; }
  }
  if (!inFmt) return failures;

  function call(outFmt: string): [string | null, string | null] {
    const fn = dispatch(inFmt, outFmt);
    if (!fn) return [null, `no dispatch for ${inFmt}->${outFmt}`];
    try { return [fn(src), null]; }
    catch (e) { return [null, (e as Error).message]; }
  }

  if ('out_ast' in s) {
    const [out, err] = call('ast');
    if (err) { failures.push(`out_ast parse error: ${err}`); }
    else if (!jsonEq(s['out_ast'], out!)) {
      failures.push(`out_ast mismatch\n  expected: ${s['out_ast']}\n  got:      ${out}`);
    }
  }

  if ('out_xml' in s) {
    const [out, err] = call('xml');
    if (err) { failures.push(`out_xml parse error: ${err}`); }
    else if (s['out_xml'].trim() !== out!.trim()) {
      failures.push(`out_xml mismatch\n  expected:\n${s['out_xml']}\n  got:\n${out}`);
    }
  }

  if ('out_cx' in s) {
    const [out, err] = call('cx');
    if (err) { failures.push(`out_cx parse error: ${err}`); }
    else if (s['out_cx'].trim() !== out!.trim()) {
      failures.push(`out_cx mismatch\n  expected:\n${s['out_cx']}\n  got:\n${out}`);
    }
  }

  if ('out_json' in s) {
    const [out, err] = call('json');
    if (err) { failures.push(`out_json parse error: ${err}`); }
    else if (!jsonEq(s['out_json'], out!)) {
      failures.push(`out_json mismatch\n  expected: ${s['out_json']}\n  got:      ${out}`);
    }
  }

  if ('out_md' in s) {
    const [out, err] = call('md');
    if (err) { failures.push(`out_md parse error: ${err}`); }
    else if (s['out_md'].trim() !== out!.trim()) {
      failures.push(`out_md mismatch\n  expected:\n${s['out_md']}\n  got:\n${out}`);
    }
  }

  return failures;
}

// ── suite runner ──────────────────────────────────────────────────────────────

function runSuite(filePath: string): number {
  const tests = parseSuite(filePath);
  let passed = 0, failed = 0;
  for (const t of tests) {
    const failures = runTest(t);
    if (failures.length === 0) {
      passed++;
    } else {
      failed++;
      console.log(`FAIL  ${t.name}`);
      for (const f of failures) {
        for (const line of f.split('\n')) {
          console.log(`      ${line}`);
        }
      }
    }
  }
  console.log(`${filePath}: ${passed} passed, ${failed} failed`);
  return failed;
}

// ── entry point ───────────────────────────────────────────────────────────────

const base = path.resolve(__dirname, '..', '..', 'conformance');
const args = process.argv.slice(2);
const suites = args.length > 0 ? args : [
  path.join(base, 'core.txt'),
  path.join(base, 'extended.txt'),
  path.join(base, 'xml.txt'),
  path.join(base, 'md.txt'),
];

let totalFailed = 0;
for (const s of suites) {
  totalFailed += runSuite(s);
}
process.exit(totalFailed > 0 ? 1 : 0);
