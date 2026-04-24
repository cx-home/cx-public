# CX Streaming API Specification
# Version: 1.0
# Date: 2026-04-23

The CX Streaming API provides a SAX/StAX-style event sequence for processing CX
documents without building a full in-memory tree. It is suited for large documents,
pipelines, and transformations that need only a forward pass.

---

## 1 — Event Types

There are 11 `StreamEvent` types. Every parsed node produces one or more events.

### 1.1 — Event type reference

#### StartDoc
Signals the beginning of the document.

Fields: none

Ordering: always the **first** event emitted for any document.

---

#### EndDoc
Signals the end of the document.

Fields: none

Ordering: always the **last** event emitted for any document.

---

#### StartElement
Signals the opening of an element.

| Field       | Type            | Required | Value |
|-------------|-----------------|----------|-------|
| `name`      | string          | yes      | Element name |
| `anchor`    | string or none  | no       | YAML-style anchor (`&name`), absent when not present |
| `data_type` | string or none  | no       | Explicit type annotation (`:type`), absent when not present |
| `merge`     | string or none  | no       | Merge directive (`<<anchor`), absent when not present |
| `attrs`     | Attr[]          | yes      | Zero or more key-value attributes; empty list when none |

An `Attr` has:

| Field       | Type            | Required | Value |
|-------------|-----------------|----------|-------|
| `name`      | string          | yes      | Attribute key |
| `value`     | typed scalar    | yes      | Native-typed value: int, float, bool, null, or string |
| `data_type` | string or none  | no       | Explicit type annotation on the attribute, absent when inferred |

All attributes are emitted in document order.

---

#### EndElement
Signals the closing of an element.

| Field  | Type   | Required | Value |
|--------|--------|----------|-------|
| `name` | string | yes      | Element name — same value as the matching StartElement |

Ordering: immediately after all events for the element's body (children, text,
etc.) have been emitted.

---

#### Text
A raw text node.

| Field   | Type   | Required | Value |
|---------|--------|----------|-------|
| `value` | string | yes      | Raw text content (untyped string) |

A Text event is produced for quoted body content (`'hello world'`) and bare
body text (`hello world`) that does not auto-type to a scalar.

---

#### Scalar
A typed scalar value.

| Field       | Type           | Required | Value |
|-------------|----------------|----------|-------|
| `data_type` | string or none | no       | One of: `int`, `float`, `bool`, `null`, `string`, `date`, `datetime`, `bytes`. Absent only when type is inferred as string and no explicit annotation is present. |
| `value`     | string         | yes      | The scalar value as a raw string (e.g. `"42"`, `"true"`, `"3.14"`) |

Scalars are unquoted body values that auto-type to a non-string type, or any
body value with an explicit type annotation.

`value` is always the raw string representation. Decoders use `data_type` to
reconstruct the native typed value.

---

#### Comment
An inline comment.

| Field   | Type   | Required | Value |
|---------|--------|----------|-------|
| `value` | string | yes      | Comment text, without the `[-` / `-]` delimiters |

---

#### PI
A processing instruction.

| Field    | Type           | Required | Value |
|----------|----------------|----------|-------|
| `target` | string         | yes      | PI target name |
| `data`   | string or none | no       | PI data content; absent when not present |

---

#### EntityRef
An XML entity reference.

| Field   | Type   | Required | Value |
|---------|--------|----------|-------|
| `value` | string | yes      | Entity name without `&` and `;` (e.g. `amp`, `lt`, `nbsp`) |

---

#### RawText
A raw text block (preserves newlines and indentation).

| Field   | Type   | Required | Value |
|---------|--------|----------|-------|
| `value` | string | yes      | Full content of the raw text block, with original whitespace |

---

#### Alias
A YAML-style alias reference.

| Field   | Type   | Required | Value |
|---------|--------|----------|-------|
| `value` | string | yes      | Anchor name being referenced (without `*` prefix) |

---

### 1.2 — StreamEvent structure

In all language bindings, a single `StreamEvent` value carries all possible fields.
Fields that do not apply to a given event type carry their zero/absent value:
- Absent optional strings: `none` / `nil` / `null`
- Absent attrs: `[]` (empty list)
- Absent string fields: `""` (empty string)

The `typ` / `type` field identifies the event type.

```
StreamEvent {
  typ:       EventType   -- one of the 11 types
  name:      string      -- StartElement, EndElement
  anchor:    ?string     -- StartElement (absent if none)
  data_type: ?string     -- StartElement type annotation, or Scalar data type
  merge:     ?string     -- StartElement merge directive (absent if none)
  attrs:     Attr[]      -- StartElement attributes (empty if none)
  value:     string      -- Text, Comment, RawText, EntityRef name, Alias name, Scalar raw value
  target:    string      -- PI target
  data:      ?string     -- PI data (absent if none)
}
```

---

## 2 — Event Ordering Guarantees

The event sequence for any well-formed CX document satisfies these invariants:

1. **StartDoc is first.** No other event precedes StartDoc.
2. **EndDoc is last.** No other event follows EndDoc.
3. **Document prolog events** (XMLDecl, CXDirective, DoctypeDecl) appear after
   StartDoc and before the first StartElement for a top-level element.
4. **StartElement / EndElement are balanced.** For every StartElement with name `n`
   at nesting depth `d`, there is exactly one corresponding EndElement with name `n`
   at the same depth, and all events for the element's body appear between them.
5. **Children before siblings.** All events for an element's body appear before the
   EndElement of that element. Depth-first, document order.
6. **BlockContent is transparent.** BlockContent nodes are not emitted as events.
   Their children are emitted inline, in order, as if the BlockContent node did not exist.

**Example event sequence for:**
```cx
[doc
  [h1 Title]
  [p First line.]
]
```

```
StartDoc
StartElement { name:"doc" }
  StartElement { name:"h1" }
    Text { value:"Title" }
  EndElement { name:"h1" }
  StartElement { name:"p" }
    Text { value:"First line." }
  EndElement { name:"p" }
EndElement { name:"doc" }
EndDoc
```

---

## 3 — API Contract

### 3.1 — stream(cx_str)

Parses the CX source string and returns all events.

```
stream(cx_str) → EventSequence
```

- **Input:** a CX-format string.
- **Return:** a language-idiomatic sequence of StreamEvent. See §3.2 for per-language types.
- **Eagerness:** the current implementation is **eager** — all events are produced
  upfront and returned as a list or iterator over that list. Lazy streaming (events
  produced on demand from a live parse) is not part of v1; implementations that
  wrap an eager list with a lazy interface are conformant.
- **Error:** if the CX source is malformed, raises/throws a parse error using the
  same error convention as `parse()` (see `spec/architecture.md §3.5`). No partial
  event sequence is returned on error.
- **Reuse:** the returned sequence MAY be consumed more than once. An implementation
  that returns a list (not a one-shot iterator) is conformant and preferred.

### 3.2 — Per-language idioms

| Language   | Return type               | Iteration idiom |
|------------|---------------------------|-----------------|
| V          | `![]StreamEvent`          | `for e in events { ... }` |
| Python     | `list[StreamEvent]`       | `for e in stream(src): ...` |
| Go         | `([]StreamEvent, error)`  | `for _, e := range events { ... }` |
| Rust       | `Result<Vec<StreamEvent>, CxError>` | `for e in events { ... }` |
| TypeScript | `StreamEvent[]`           | `for (const e of events) { ... }` |
| C#         | `IEnumerable<StreamEvent>`| `foreach (var e in events) { ... }` |
| Swift      | `[StreamEvent]`           | `for e in events { ... }` |
| Java       | `List<StreamEvent>`       | `for (StreamEvent e : events) { ... }` |
| Kotlin     | `List<StreamEvent>`       | `for (e in events) { ... }` |
| Ruby       | `Array<StreamEvent>`      | `events.each { |e| ... }` |

For languages with native streaming types (Go channels, Rust async iterators,
Swift AsyncSequence), providing an additional streaming variant is permitted but
the synchronous list return MUST be the primary conformance target.

### 3.3 — Parse errors mid-stream

Because the current implementation is eager (full parse before first event), all
parse errors are detected before any event is returned. There is no partial event
sequence. The error contract is: either return the complete event list, or raise
an error. Never return a partial list.

---

## 4 — Implementation

Streaming in non-V language bindings is implemented via the C ABI binary protocol:

1. Call `cx_to_events_bin(cx_str, err_out)`.
2. If result is NULL, raise a parse error using `*err_out`.
3. Read `payload_size` from the first 4 bytes (u32 LE).
4. Read `event_count` from bytes 4–7 of the payload (u32 LE).
5. Decode each event from the binary payload using the format in `spec/architecture.md §4.2`.
6. Call `cx_free(buffer)`.
7. Return the decoded event list.

V does not use this path. V's `stream()` walks the parsed Document directly
(see `lang/v/cxlib/stream.v`).

The binary format is fully specified in `spec/architecture.md §4.2` including a
test vector. Streaming conformance is validated against the fixtures in
`fixtures/stream/`.

---

## 5 — v1 Scope

**In scope:**
- 11 event types as specified
- Eager event list (full parse, then deliver all events)
- `stream(cx_str)` — CX source input only
- Binary wire protocol (`cx_to_events_bin`) for all non-V bindings
- Per-language idiomatic sequence type

**Deferred:**
- Lazy / pull-parser streaming (events produced on demand)
- Streaming from non-CX input formats (XML, JSON, etc.)
- Random access within the event stream
- Back-pressure or cancellation
