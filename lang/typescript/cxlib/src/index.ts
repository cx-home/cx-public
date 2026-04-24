/**
 * CX TypeScript binding — koffi wrapper around libcx.
 */
import koffi from 'koffi';
import path from 'path';
import fs from 'fs';
import { decodeAST, decodeEvents } from './binary';
import type { StreamEvent } from './binary';

// ── library discovery ─────────────────────────────────────────────────────────
const libName = process.platform === 'darwin' ? 'libcx.dylib' : 'libcx.so';

function findLibcx(): string {
  // 1. Explicit path override
  if (process.env.LIBCX_PATH) return process.env.LIBCX_PATH;

  const candidates: string[] = [];

  // 2. Directory override
  if (process.env.LIBCX_LIB_DIR)
    candidates.push(path.join(process.env.LIBCX_LIB_DIR, libName));

  // 3. System paths
  for (const dir of ['/usr/local/lib', '/opt/homebrew/lib', '/usr/lib',
                     '/usr/lib/x86_64-linux-gnu', '/usr/lib/aarch64-linux-gnu'])
    candidates.push(path.join(dir, libName));

  // 4. Repo-relative fallback (development)
  const repoRoot = path.resolve(__dirname, '..', '..', '..', '..');
  candidates.push(path.join(repoRoot, 'vcx', 'target', libName));
  candidates.push(path.join(repoRoot, 'dist', 'lib', libName));

  const found = candidates.find(p => fs.existsSync(p));
  if (found) return found;
  throw new Error(`libcx not found. Install with 'sudo make install' or set LIBCX_PATH.\nLooked in: ${candidates.join(', ')}`);
}

const libPath = findLibcx();

const lib = koffi.load(libPath);

// ── native function declarations ──────────────────────────────────────────────
// koffi copies returned char* strings to JS; no manual cx_free needed.
// For err_out we use _Out_ str* so koffi writes the error string into an array.

const _cx_version = lib.func('char* cx_version()');
const _cx_free = lib.func('void cx_free(void* ptr)');

// Binary functions — return a raw pointer to [u32 size][payload] buffer.
const _cx_to_ast_bin    = lib.func('void* cx_to_ast_bin(str input, _Out_ str* err_out)');
const _cx_to_events_bin = lib.func('void* cx_to_events_bin(str input, _Out_ str* err_out)');

// CX input
const _cx_to_cx          = lib.func('char* cx_to_cx         (str input, _Out_ str* err_out)');
const _cx_to_cx_compact  = lib.func('char* cx_to_cx_compact (str input, _Out_ str* err_out)');
const _cx_ast_to_cx      = lib.func('char* cx_ast_to_cx     (str input, _Out_ str* err_out)');
const _cx_to_xml  = lib.func('char* cx_to_xml (str input, _Out_ str* err_out)');
const _cx_to_ast  = lib.func('char* cx_to_ast (str input, _Out_ str* err_out)');
const _cx_to_json = lib.func('char* cx_to_json(str input, _Out_ str* err_out)');
const _cx_to_yaml = lib.func('char* cx_to_yaml(str input, _Out_ str* err_out)');
const _cx_to_toml = lib.func('char* cx_to_toml(str input, _Out_ str* err_out)');
const _cx_to_md   = lib.func('char* cx_to_md  (str input, _Out_ str* err_out)');

// XML input
const _cx_xml_to_cx   = lib.func('char* cx_xml_to_cx  (str input, _Out_ str* err_out)');
const _cx_xml_to_xml  = lib.func('char* cx_xml_to_xml (str input, _Out_ str* err_out)');
const _cx_xml_to_ast  = lib.func('char* cx_xml_to_ast (str input, _Out_ str* err_out)');
const _cx_xml_to_json = lib.func('char* cx_xml_to_json(str input, _Out_ str* err_out)');
const _cx_xml_to_yaml = lib.func('char* cx_xml_to_yaml(str input, _Out_ str* err_out)');
const _cx_xml_to_toml = lib.func('char* cx_xml_to_toml(str input, _Out_ str* err_out)');
const _cx_xml_to_md   = lib.func('char* cx_xml_to_md  (str input, _Out_ str* err_out)');

// JSON input
const _cx_json_to_cx   = lib.func('char* cx_json_to_cx  (str input, _Out_ str* err_out)');
const _cx_json_to_xml  = lib.func('char* cx_json_to_xml (str input, _Out_ str* err_out)');
const _cx_json_to_ast  = lib.func('char* cx_json_to_ast (str input, _Out_ str* err_out)');
const _cx_json_to_json = lib.func('char* cx_json_to_json(str input, _Out_ str* err_out)');
const _cx_json_to_yaml = lib.func('char* cx_json_to_yaml(str input, _Out_ str* err_out)');
const _cx_json_to_toml = lib.func('char* cx_json_to_toml(str input, _Out_ str* err_out)');
const _cx_json_to_md   = lib.func('char* cx_json_to_md  (str input, _Out_ str* err_out)');

// YAML input
const _cx_yaml_to_cx   = lib.func('char* cx_yaml_to_cx  (str input, _Out_ str* err_out)');
const _cx_yaml_to_xml  = lib.func('char* cx_yaml_to_xml (str input, _Out_ str* err_out)');
const _cx_yaml_to_ast  = lib.func('char* cx_yaml_to_ast (str input, _Out_ str* err_out)');
const _cx_yaml_to_json = lib.func('char* cx_yaml_to_json(str input, _Out_ str* err_out)');
const _cx_yaml_to_yaml = lib.func('char* cx_yaml_to_yaml(str input, _Out_ str* err_out)');
const _cx_yaml_to_toml = lib.func('char* cx_yaml_to_toml(str input, _Out_ str* err_out)');
const _cx_yaml_to_md   = lib.func('char* cx_yaml_to_md  (str input, _Out_ str* err_out)');

// TOML input
const _cx_toml_to_cx   = lib.func('char* cx_toml_to_cx  (str input, _Out_ str* err_out)');
const _cx_toml_to_xml  = lib.func('char* cx_toml_to_xml (str input, _Out_ str* err_out)');
const _cx_toml_to_ast  = lib.func('char* cx_toml_to_ast (str input, _Out_ str* err_out)');
const _cx_toml_to_json = lib.func('char* cx_toml_to_json(str input, _Out_ str* err_out)');
const _cx_toml_to_yaml = lib.func('char* cx_toml_to_yaml(str input, _Out_ str* err_out)');
const _cx_toml_to_toml = lib.func('char* cx_toml_to_toml(str input, _Out_ str* err_out)');
const _cx_toml_to_md   = lib.func('char* cx_toml_to_md  (str input, _Out_ str* err_out)');

// MD input
const _cx_md_to_cx   = lib.func('char* cx_md_to_cx  (str input, _Out_ str* err_out)');
const _cx_md_to_xml  = lib.func('char* cx_md_to_xml (str input, _Out_ str* err_out)');
const _cx_md_to_ast  = lib.func('char* cx_md_to_ast (str input, _Out_ str* err_out)');
const _cx_md_to_json = lib.func('char* cx_md_to_json(str input, _Out_ str* err_out)');
const _cx_md_to_yaml = lib.func('char* cx_md_to_yaml(str input, _Out_ str* err_out)');
const _cx_md_to_toml = lib.func('char* cx_md_to_toml(str input, _Out_ str* err_out)');
const _cx_md_to_md   = lib.func('char* cx_md_to_md  (str input, _Out_ str* err_out)');

// ── helper ────────────────────────────────────────────────────────────────────

function callFn(fn: koffi.KoffiFunction, input: string): string {
  const errArr: (string | null)[] = [null];
  const out: string | null = fn(input, errArr);
  if (out === null) {
    throw new Error(errArr[0] ?? 'unknown error');
  }
  return out;
}

function callBinFn(fn: koffi.KoffiFunction, input: string): Buffer {
  const errArr: (string | null)[] = [null];
  const ptr: any = fn(input, errArr);
  if (ptr === null || ptr === undefined) {
    throw new Error(errArr[0] ?? 'unknown error');
  }
  // Read the 4-byte little-endian size prefix, coerce to number for safety.
  const payloadSize: number = Number(koffi.decode(ptr, 'uint32_t') as number);
  // Map the raw C buffer into an ArrayBuffer (zero-copy view), copy payload
  // bytes into a Node Buffer, then free the C-owned memory.
  const ab: ArrayBuffer = koffi.view(ptr, 4 + payloadSize);
  const payload = Buffer.from(Buffer.from(ab).subarray(4));
  _cx_free(ptr);
  return payload;
}

// ── public API ────────────────────────────────────────────────────────────────

export function version(): string { return _cx_version() as string; }

// Binary bridge — used by parse() in ast.ts and stream() below.
export function toAstBin(input: string): Buffer {
  return callBinFn(_cx_to_ast_bin, input);
}

export function toEventsBin(input: string): Buffer {
  return callBinFn(_cx_to_events_bin, input);
}

/** Stream CX input as an array of StreamEvents using the binary protocol. */
export function stream(cxStr: string): StreamEvent[] {
  return decodeEvents(toEventsBin(cxStr));
}

export type { StreamEvent };

// CX input
export function toCx        (input: string): string { return callFn(_cx_to_cx,         input); }
export function toCxCompact (input: string): string { return callFn(_cx_to_cx_compact, input); }
export function astToCx     (input: string): string { return callFn(_cx_ast_to_cx,     input); }
export function toXml (input: string): string { return callFn(_cx_to_xml,  input); }
export function toAst (input: string): string { return callFn(_cx_to_ast,  input); }
export function toJson(input: string): string { return callFn(_cx_to_json, input); }
export function toYaml(input: string): string { return callFn(_cx_to_yaml, input); }
export function toToml(input: string): string { return callFn(_cx_to_toml, input); }
export function toMd  (input: string): string { return callFn(_cx_to_md,   input); }

// XML input
export function xmlToCx  (input: string): string { return callFn(_cx_xml_to_cx,   input); }
export function xmlToXml (input: string): string { return callFn(_cx_xml_to_xml,  input); }
export function xmlToAst (input: string): string { return callFn(_cx_xml_to_ast,  input); }
export function xmlToJson(input: string): string { return callFn(_cx_xml_to_json, input); }
export function xmlToYaml(input: string): string { return callFn(_cx_xml_to_yaml, input); }
export function xmlToToml(input: string): string { return callFn(_cx_xml_to_toml, input); }
export function xmlToMd  (input: string): string { return callFn(_cx_xml_to_md,   input); }

// JSON input
export function jsonToCx  (input: string): string { return callFn(_cx_json_to_cx,   input); }
export function jsonToXml (input: string): string { return callFn(_cx_json_to_xml,  input); }
export function jsonToAst (input: string): string { return callFn(_cx_json_to_ast,  input); }
export function jsonToJson(input: string): string { return callFn(_cx_json_to_json, input); }
export function jsonToYaml(input: string): string { return callFn(_cx_json_to_yaml, input); }
export function jsonToToml(input: string): string { return callFn(_cx_json_to_toml, input); }
export function jsonToMd  (input: string): string { return callFn(_cx_json_to_md,   input); }

// YAML input
export function yamlToCx  (input: string): string { return callFn(_cx_yaml_to_cx,   input); }
export function yamlToXml (input: string): string { return callFn(_cx_yaml_to_xml,  input); }
export function yamlToAst (input: string): string { return callFn(_cx_yaml_to_ast,  input); }
export function yamlToJson(input: string): string { return callFn(_cx_yaml_to_json, input); }
export function yamlToYaml(input: string): string { return callFn(_cx_yaml_to_yaml, input); }
export function yamlToToml(input: string): string { return callFn(_cx_yaml_to_toml, input); }
export function yamlToMd  (input: string): string { return callFn(_cx_yaml_to_md,   input); }

// TOML input
export function tomlToCx  (input: string): string { return callFn(_cx_toml_to_cx,   input); }
export function tomlToXml (input: string): string { return callFn(_cx_toml_to_xml,  input); }
export function tomlToAst (input: string): string { return callFn(_cx_toml_to_ast,  input); }
export function tomlToJson(input: string): string { return callFn(_cx_toml_to_json, input); }
export function tomlToYaml(input: string): string { return callFn(_cx_toml_to_yaml, input); }
export function tomlToToml(input: string): string { return callFn(_cx_toml_to_toml, input); }
export function tomlToMd  (input: string): string { return callFn(_cx_toml_to_md,   input); }

// MD input
export function mdToCx  (input: string): string { return callFn(_cx_md_to_cx,   input); }
export function mdToXml (input: string): string { return callFn(_cx_md_to_xml,  input); }
export function mdToAst (input: string): string { return callFn(_cx_md_to_ast,  input); }
export function mdToJson(input: string): string { return callFn(_cx_md_to_json, input); }
export function mdToYaml(input: string): string { return callFn(_cx_md_to_yaml, input); }
export function mdToToml(input: string): string { return callFn(_cx_md_to_toml, input); }
export function mdToMd  (input: string): string { return callFn(_cx_md_to_md,   input); }

export * from './ast';
export { decodeAST, decodeEvents } from './binary';
