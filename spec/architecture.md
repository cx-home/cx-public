# CX System Architecture Specification
# Version: 1.0
# Date: 2026-04-23

This document specifies the system architecture of CX: the role of V and libcx,
the C ABI (current mechanism), the binary wire protocol, and the language binding
contract. All language binding implementations must conform to this spec.

---

## 1 — Implementation Structure

### V as the reference

V is not a language binding. V IS the library. The `vcx/` directory contains the
single, authoritative implementation of the CX parser, emitters, type system, and
streaming engine. All other language bindings consume this implementation via libcx.

The relationship is:
```
vcx/cx/        ← V source: single implementation of everything
    │
    ├── V binding ──────────────────────── lang/v/cxlib/
    │   import vcx.cx directly             native Document/Element types
    │   no FFI, no binary protocol         compile-time access to V sum types
    │
    └── compiled to libcx ─────────────── all other 9 language bindings
        libcx.dylib / libcx.so             each wraps via FFI
        C ABI in include/cx.h
```

**Current V binding state:** `lang/v/cxlib/` currently uses the same JSON bridge
as other bindings (via libcx). Restructuring to `import vcx.cx` directly is
deferred pending V module boundary resolution. The API surface is identical to the
eventual native form; the wire path is temporary.

### libcx

libcx is the V source in `vcx/` compiled to a platform shared library:

- `vcx/target/libcx.dylib` on macOS
- `vcx/target/libcx.so` on Linux

It is built with `make build-vcx`. The public interface is `include/cx.h`.

libcx exposes **49 C ABI functions** (see §3 for complete list). It is stateless —
no global mutable state. Every call is independent and thread-safe.

### What lives in libcx vs. language bindings

**libcx provides (via C ABI):**
- Parsing all 6 input formats (CX, XML, JSON, YAML, TOML, Markdown)
- Emitting all 6 output formats plus AST JSON
- Binary wire encoding of AST (`cx_to_ast_bin`)
- Binary wire encoding of streaming events (`cx_to_events_bin`)
- CXPath expression evaluation (via `cx_to_ast_bin` + evaluator in libcx; see §Language binding contract)
- Streaming events as JSON (`cx_to_events`, retained for tooling only)

**Each language binding implements natively (never through C ABI):**
- The `Document` and `Element` types and all their fields
- All Document API methods: `at`, `get`, `get_all`, `children`, `find_first`,
  `find_all`, `root`, `attr`, `text`, `scalar`, `set_attr`, `remove_attr`,
  `append`, `prepend`, `insert`, `remove_at`, `remove_child`
- `transform(path, fn)` — path-copy structural update
- `transform_all(cxpath, fn)` — decomposed into `select_all` + iterative `transform`
- Binary AST decoder (reads `cx_to_ast_bin` output → native Document tree)
- Binary events decoder (reads `cx_to_events_bin` output → native StreamEvent list)
- `select(expr)` / `select_all(expr)` — these serialize the in-memory Document
  back to CX string, call `cx_to_ast_bin` (which evaluates the expression internally),
  and decode the result

**The invariant:** No Document API method (`find_all`, `at`, `attr`, `transform`,
etc.) goes through the C ABI. The C ABI is for parsing, format conversion, binary
encoding, and CXPath evaluation only.

---

## 2 — C ABI: Current Mechanism

The C ABI is the **current** distribution mechanism for libcx. It is **not** the
long-term target architecture. The target is a WASM module (see §5). Specs and
implementations that describe the C ABI must treat it as transitional.

### Calling convention

All C ABI functions follow this contract:

```c
char* cx_{input}_to_{output}(const char* input, char** err_out);
```

- `input` — NUL-terminated UTF-8 string. Must not be NULL.
- `err_out` — pointer to a `char*` that receives the error message on failure.
  MAY be NULL if error detail is not needed.
- **On success** — returns a heap-allocated NUL-terminated UTF-8 string (or binary
  buffer for `_bin` functions — see §4). Caller must `cx_free()` it.
- **On error** — returns NULL. If `err_out` is non-NULL, sets `*err_out` to a
  heap-allocated error message string. Caller must `cx_free(*err_out)`.
- **Thread safety** — all functions are stateless and safe to call concurrently
  from multiple threads without synchronisation.
- **Memory rule** — every non-NULL pointer returned by libcx (result or `*err_out`)
  must be released with `cx_free()`. Never pass these pointers to the system `free()`.

### Complete C ABI function list

**Format conversions (6 inputs × 7 outputs = 42 + cx_to_cx_compact):**

| Group        | Functions |
|--------------|-----------|
| CX input     | `cx_to_cx`, `cx_to_cx_compact`, `cx_to_xml`, `cx_to_ast`, `cx_to_json`, `cx_to_yaml`, `cx_to_toml`, `cx_to_md` |
| XML input    | `cx_xml_to_cx`, `cx_xml_to_xml`, `cx_xml_to_ast`, `cx_xml_to_json`, `cx_xml_to_yaml`, `cx_xml_to_toml`, `cx_xml_to_md` |
| JSON input   | `cx_json_to_cx`, `cx_json_to_xml`, `cx_json_to_ast`, `cx_json_to_json`, `cx_json_to_yaml`, `cx_json_to_toml`, `cx_json_to_md` |
| YAML input   | `cx_yaml_to_cx`, `cx_yaml_to_xml`, `cx_yaml_to_ast`, `cx_yaml_to_json`, `cx_yaml_to_yaml`, `cx_yaml_to_toml`, `cx_yaml_to_md` |
| TOML input   | `cx_toml_to_cx`, `cx_toml_to_xml`, `cx_toml_to_ast`, `cx_toml_to_json`, `cx_toml_to_yaml`, `cx_toml_to_toml`, `cx_toml_to_md` |
| MD input     | `cx_md_to_cx`, `cx_md_to_xml`, `cx_md_to_ast`, `cx_md_to_json`, `cx_md_to_yaml`, `cx_md_to_toml`, `cx_md_to_md` |
| AST input    | `cx_ast_to_cx` |

**Semantics of the output formats:**
- `*_to_cx` — canonical CX with whitespace normalization
- `*_to_cx_compact` — compact CX (CX input only), no optional whitespace
- `*_to_xml` — XML with CX extensions in `cx:` namespace where needed
- `*_to_ast` — full parse tree as JSON (see `spec/ast.md`); retained for tooling
- `*_to_json` — semantic JSON (resolved values, not AST)
- `*_to_yaml` — YAML
- `*_to_toml` — TOML
- `*_to_md` — Markdown

**Utility functions:**

| Signature | Semantics |
|-----------|-----------|
| `void cx_free(char* s)` | Release any string or buffer returned by libcx |
| `char* cx_version(void)` | Returns heap-allocated version string (e.g. `"1.0.0"`). Caller must `cx_free()`. |

**Streaming and binary protocol:**

| Signature | Semantics |
|-----------|-----------|
| `char* cx_to_events(const char* input, char** err_out)` | Parse CX, return streaming events as JSON array. Retained for external tooling. Language bindings use `cx_to_events_bin` instead. |
| `char* cx_to_ast_bin(const char* input, char** err_out)` | Parse CX, return binary-encoded AST. See §4 for format. |
| `char* cx_to_events_bin(const char* input, char** err_out)` | Parse CX, return binary-encoded events. See §4 for format. |

---

## 3 — Language Binding Contract

### What every conformant binding must implement

A language binding is conformant when it implements all of the following:

**Tier 1 — Core (required for any conformance claim):**
- [ ] `parse(cx_str) → Document` — parse CX source via `cx_to_ast_bin` + binary decoder
- [ ] `parse_xml`, `parse_json`, `parse_yaml`, `parse_toml`, `parse_md` — same
- [ ] Full Document type with `elements` field (list of top-level Element nodes)
- [ ] Full Element type with `name`, `attrs`, `items` fields
- [ ] All node types decoded from binary: Element, Text, Scalar, Comment, RawText,
  EntityRef, Alias, PI, XMLDecl, CXDirective, BlockContent
- [ ] Document API — navigation: `root()`, `get()`, `get_all()`, `at()`,
  `find_first()`, `find_all()`, `children()`
- [ ] Document API — extraction: `attr()`, `text()`, `scalar()`
- [ ] Document API — build mode mutation: `set_attr()`, `remove_attr()`, `append()`,
  `prepend()`, `insert()`, `remove_at()`, `remove_child()`
- [ ] Document API — transform mode: `transform()`, `transform_all()`
- [ ] Emit: `to_cx()`, `to_xml()`, `to_json()`, `to_yaml()`, `to_toml()`, `to_md()`
- [ ] Parse error raised as the binding's error type; never silently swallowed
- [ ] Missing-value contract: navigation and extraction return `none`/`nil`/`null`
  (not error) when the target is absent
- [ ] 122/122 conformance tests passing

**Tier 2 — CXPath (required for CXPath feature claim):**
- [ ] `select(expr) → Element or none`
- [ ] `select_all(expr) → Element[]`
- [ ] Round-trip implementation: serialize Document to CX → `cx_to_ast_bin` with
  expression → decode result (see §3.1 for specification)
- [ ] Invalid expression panics/throws (programming error, not soft return)
- [ ] No-match returns `none` / `[]` (not error)

**Tier 3 — Streaming (required for streaming feature claim):**
- [ ] `stream(cx_str) → language-idiomatic sequence of StreamEvent`
- [ ] Implemented via `cx_to_events_bin` + binary decoder
- [ ] All 11 event types decoded with correct field types
- [ ] Event sequence contract: StartDoc first, EndDoc last, nested Start/End balanced

### Binding may omit and still claim Core conformance

A binding that implements Tier 1 only may claim Core conformance. It may not claim
CXPath or Streaming conformance. Feature claims are all-or-nothing within each tier.

### 3.1 — select / select_all implementation for non-V bindings

`select` and `select_all` in non-V bindings are implemented as follows:

1. Serialize the in-memory Document to a CX string using the binding's `to_cx()`.
2. Prepend the CXPath expression to the CX string in a standard envelope, then
   call `cx_to_ast_bin` with the compound input. (Alternatively: call a dedicated
   CXPath evaluation path when available.)
3. Decode the binary result to get the matching element paths.
4. Return matching elements located within the existing in-memory Document tree.

This round-trip is the specified implementation path, not an optimization. V does
not use this path — it evaluates CXPath directly against the in-memory Document.

### 3.2 — transform_all decomposition

`transform_all(cxpath_expr, fn)` is always implemented as:

1. Call `select_all(cxpath_expr)` to get the list of matching elements (with their
   paths within the document).
2. Sort matched paths deepest-first (to avoid path invalidation on nested matches).
3. For each path, call `transform(path, fn)` on the current document.
4. Return the final document after all transforms.

No callback function crosses the C ABI. The `fn` argument is always called within
the binding's own language.

### 3.3 — Naming conventions per language

| Language   | Methods / functions | Types | Constants |
|------------|---------------------|-------|-----------|
| V          | `snake_case`        | `PascalCase` | `snake_case` |
| Python     | `snake_case`        | `PascalCase` | `UPPER_CASE` |
| Go         | `camelCase`         | `PascalCase` | `PascalCase` |
| Rust       | `snake_case`        | `PascalCase` | `SCREAMING_SNAKE` |
| TypeScript | `camelCase`         | `PascalCase` | `camelCase` |
| C#         | `PascalCase`        | `PascalCase` | `PascalCase` |
| Swift      | `camelCase`         | `PascalCase` | `camelCase` |
| Java       | `camelCase`         | `PascalCase` | `UPPER_CASE` |
| Kotlin     | `camelCase`         | `PascalCase` | `UPPER_CASE` |
| Ruby       | `snake_case`        | `PascalCase` | `SCREAMING_SNAKE` |

Method names translate as: `find_first` → Go/TS/Swift/Java/Kotlin: `findFirst`,
C#: `FindFirst`, Ruby: `find_first`.

### 3.4 — Scalar type mappings

CX scalar types map to native types as follows. Bindings MUST use these exact types —
no narrowing or widening.

| CX type  | V       | Go       | Rust    | Python  | TypeScript | C#      | Swift    | Java    | Kotlin  | Ruby    |
|----------|---------|----------|---------|---------|------------|---------|----------|---------|---------|---------|
| int      | `i64`   | `int64`  | `i64`   | `int`   | `number`   | `long`  | `Int64`  | `long`  | `Long`  | `Integer` |
| float    | `f64`   | `float64`| `f64`   | `float` | `number`   | `double`| `Double` | `double`| `Double`| `Float` |
| bool     | `bool`  | `bool`   | `bool`  | `bool`  | `boolean`  | `bool`  | `Bool`   | `boolean`| `Boolean`| `true/false` |
| null     | `NullVal`| `nil`   | `None`  | `None`  | `null`     | `null`  | `nil`    | `null`  | `null`  | `nil`   |
| string   | `string`| `string` | `String`| `str`   | `string`   | `string`| `String` | `String`| `String`| `String`|
| date     | `string`| `string` | `String`| `str`   | `string`   | `string`| `String` | `String`| `String`| `String`|
| datetime | `string`| `string` | `String`| `str`   | `string`   | `string`| `String` | `String`| `String`| `String`|
| bytes    | `string`| `[]byte` | `Vec<u8>`| `bytes`| `Uint8Array`| `byte[]`| `Data`  | `byte[]`| `ByteArray`| `String`|

date and datetime are represented as ISO 8601 strings. No language binding is
required to parse them into a native date type — doing so is permitted but must
not affect round-trip fidelity.

`attr()` and `scalar()` return a value of the appropriate native type from the
table above, or `none`/`nil`/`null` when absent. The return type in typed languages
is a union / sum type or `Any` capable of holding all scalar types plus the
none/absent sentinel.

### 3.5 — Error and exception conventions per language

**Parse errors** — the CX string is malformed. Implementations MUST raise an error:

| Language   | Mechanism |
|------------|-----------|
| V          | `!Document` — propagate with `!` or `or { ... }` |
| Go         | `(Document, error)` — caller checks `err != nil` |
| Rust       | `Result<Document, CxError>` |
| Python     | `raise CxError(msg)` |
| TypeScript | `throw new CxError(msg)` |
| C#         | `throw new CxException(msg)` |
| Swift      | `throws CxError` |
| Java       | `throw new CxException(msg)` (unchecked) |
| Kotlin     | `throw CxException(msg)` |
| Ruby       | `raise CxError, msg` |

**Navigation / extraction missing** — not an error. Return `none`/`nil`/`null`/`[]`
as documented in `spec/api.md §4`. Never throw.

**CXPath invalid expression** — programming error. Implementations MUST panic or
throw an unrecoverable exception. This is not a soft return. CXPath expressions
are always program literals, never user-supplied data.

**CXPath no match** — not an error. `select` returns `none`, `select_all` returns `[]`.

---

## 4 — Binary Wire Protocol

The binary wire protocol is used by all non-V language bindings to transfer parsed
AST and streaming events from libcx to the binding's memory. It replaces the JSON
intermediate for parse and stream, providing ~2.5× faster encoding (C side) and
~3.5× faster decoding (binding side) vs JSON.

Both binary functions return a buffer with a **size prefix** header:

```
[u32 LE: payload_size] [payload_size bytes: payload]
```

Read the first 4 bytes as a little-endian `uint32` to get `payload_size`. Then
read exactly `payload_size` bytes. Call `cx_free()` on the entire buffer.
The buffer is **binary data**, not a null-terminated string.

### String and OptString encoding

All strings in the binary payload use this encoding:

```
String:    [u32 LE: byte_len] [byte_len bytes: UTF-8]   (no null terminator)
OptString: [u8: present (0=absent, 1=present)] [String if present]
```

### 4.1 — cx_to_ast_bin payload format

```
[u8: version = 0x01]
[u16 LE: prolog_count]
[prolog_count nodes...]
[u16 LE: element_count]
[element_count nodes...]
```

Each node is recursively encoded:

```
[u8: node_type_id]
[payload by type]
```

Node type IDs and payloads:

| ID   | Node type      | Payload |
|------|----------------|---------|
| 0x01 | Element        | `String:name  OptString:anchor  OptString:data_type  OptString:merge  u16:attr_count  attrs[]  u16:child_count  nodes[]` |
| 0x02 | Text           | `String:value` |
| 0x03 | Scalar         | `String:data_type  String:value` |
| 0x04 | Comment        | `String:value` |
| 0x05 | RawText        | `String:value` |
| 0x06 | EntityRef      | `String:name` |
| 0x07 | Alias          | `String:name` |
| 0x08 | PI             | `String:target  OptString:data` |
| 0x09 | XMLDecl        | `String:version  OptString:encoding  OptString:standalone` |
| 0x0A | CXDirective    | `String:content` |
| 0x0B | DoctypeDecl    | `String:content` |
| 0x0C | BlockContent   | `u16:child_count  nodes[]` |
| 0xFF | (skip/padding) | (no payload — skip this node) |

Each `Attr` in an element's attrs array:

```
Attr: String:name  String:value  OptString:data_type
```

`data_type` in Attr is the explicit type annotation, if present. When absent,
decoders infer the type from the value string using CX auto-typing rules
(see `spec/ast.md §Auto-typing`).

**Test vector — input:** `[hello world]`

```
Parsed as: Document { elements: [ Element { name:"hello", items:[ Text{"world"} ] } ] }
```

```
Buffer (36 bytes):
Offset  Hex bytes                         Annotation
00      20 00 00 00                       payload_size = 32 (u32 LE)
04      01                                version = 1
05      00 00                             prolog_count = 0 (u16 LE)
07      01 00                             element_count = 1 (u16 LE)
09      01                                node_type = 0x01 (Element)
0A      05 00 00 00  68 65 6C 6C 6F       String "hello" (len=5)
13      00                                anchor = absent
14      00                                data_type = absent
15      00                                merge = absent
16      00 00                             attr_count = 0 (u16 LE)
18      01 00                             child_count = 1 (u16 LE)
1A      02                                node_type = 0x02 (Text)
1B      05 00 00 00  77 6F 72 6C 64       String "world" (len=5)
```

Total buffer: `20 00 00 00 01 00 00 01 00 01 05 00 00 00 68 65 6C 6C 6F 00 00 00 00 00 01 00 02 05 00 00 00 77 6F 72 6C 64`

### 4.2 — cx_to_events_bin payload format

```
[u32 LE: event_count]
[event_count events...]
```

Each event:

```
[u8: event_type_id]
[payload by type]
```

Event type IDs and payloads:

| ID   | Event type   | Payload |
|------|--------------|---------|
| 0x01 | StartDoc     | (none) |
| 0x02 | EndDoc       | (none) |
| 0x03 | StartElement | `String:name  OptString:anchor  OptString:data_type  OptString:merge  u16:attr_count  attrs[]` |
| 0x04 | EndElement   | `String:name` |
| 0x05 | Text         | `String:value` |
| 0x06 | Scalar       | `OptString:data_type  String:value` |
| 0x07 | Comment      | `String:value` |
| 0x08 | PI           | `String:target  OptString:data` |
| 0x09 | EntityRef    | `String:name` |
| 0x0A | RawText      | `String:value` |
| 0x0B | Alias        | `String:name` |

Each `Attr` in a StartElement event:

```
Attr: String:name  String:value  OptString:data_type
```

**Test vector — input:** `[hello world]`

```
Events: StartDoc, StartElement{name:"hello"}, Text{value:"world"}, EndElement{name:"hello"}, EndDoc
event_count = 5
```

```
Buffer (45 bytes):
Offset  Hex bytes                         Annotation
00      29 00 00 00                       payload_size = 41 (u32 LE)
04      05 00 00 00                       event_count = 5 (u32 LE)
08      01                                event_type = 0x01 (StartDoc)
09      03                                event_type = 0x03 (StartElement)
0A      05 00 00 00  68 65 6C 6C 6F       String "hello" (len=5)
13      00                                anchor = absent
14      00                                data_type = absent
15      00                                merge = absent
16      00 00                             attr_count = 0 (u16 LE)
18      05                                event_type = 0x05 (Text)
19      05 00 00 00  77 6F 72 6C 64       String "world" (len=5)
22      04                                event_type = 0x04 (EndElement)
23      05 00 00 00  68 65 6C 6C 6F       String "hello" (len=5)
2C      02                                event_type = 0x02 (EndDoc)
```

Total buffer: `29 00 00 00 05 00 00 00 01 03 05 00 00 00 68 65 6C 6C 6F 00 00 00 00 00 05 05 00 00 00 77 6F 72 6C 64 04 05 00 00 00 68 65 6C 6C 6F 02`

---

## 5 — WASM Transition

The C ABI is the **current** distribution mechanism for libcx. The architectural
target is a WASM module. This section specifies what changes and what stays the same.

### What the C ABI provides today

- libcx compiled to `.dylib` / `.so`
- `include/cx.h` with 49 exported functions
- Per-language FFI binding (ctypes, CGo, extern "C", koffi, P/Invoke, etc.)
- Platform-specific: macOS arm64, Linux x86_64

### What changes with WASM

- libcx compiled to `libcx.wasm` (single portable binary)
- No per-platform `.dylib` / `.so`; no per-language FFI setup
- Language bindings load the WASM module via their platform's WASM runtime
  (wasmtime, wasmer, browser runtime, etc.)
- The function signatures remain identical: same names, same `(const char*, char**) → char*`
  calling convention mapped to WASM linear memory
- Memory management: `cx_free()` still required; caller writes the input string into
  WASM linear memory, reads the output from WASM linear memory, calls `cx_free` in
  the WASM module

### What stays the same

- Every function name and semantic (§2)
- The binary wire protocol (§4) — same byte formats
- The language binding Document API (§3) — same native implementation, unaffected
- The language binding contract (§3) — same checklist, same naming, same type mappings
- The error contract — same conventions per language

### What each binding needs to change

1. Replace the FFI loader (ctypes/CGo/koffi/etc.) with a WASM runtime loader
2. Replace direct memory pointers with WASM memory buffer read/write
3. Keep the binary decoders unchanged — they read the same byte formats
4. The Document API implementation is unchanged

### Timeline

The C ABI is the current mechanism and will remain so until a reference WASM build
is available and tested across all 9 bindings. Bindings MUST support the C ABI
for the current release. The WASM transition is a separate migration; no binding
should assume C ABI permanence.

---

## 6 — Language Tiers

Tiers describe performance and implementation depth, not quality ranking. All tiers
must pass 122/122 conformance tests.

### V — Native

V IS the library. No FFI, no wire protocol. `import vcx.cx` gives direct access
to V sum types at compiled speed. This is the reference; all other languages are
measured against it.

### First-class (Go, Rust, TypeScript, C#, Swift, Java, Kotlin, Ruby)

Full API parity. All format conversions, Document API, CXPath, and streaming.
Binary wire protocol for parse and stream. Compiled languages (Go, Rust, C#,
Swift, TypeScript) reach 1.5–2× V on large documents. JVM languages (Java,
Kotlin) reach ~2.5× V. Ruby ~3.5× V.

### Python — Close (≤4× V)

Uses binary wire protocol. Remaining gap is Python interpreter overhead for
tree-walk and object allocation — irreducible without a C extension. Correct and
complete; acceptable for data-binding use cases.

### Well-supported (future additions)

New bindings start with `cx_to_ast` (JSON bridge) as a working baseline.
Graduate to binary protocol based on demand. Format conversions are identical
regardless of tier. A well-supported binding may claim Core conformance once
122/122 tests pass.
