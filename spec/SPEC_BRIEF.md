# CX Specification Brief
# Date: 2026-04-23

## Purpose

Produce a complete, unambiguous specification for the CX system. The test:
if all code and implementation history were destroyed and only the specs
remained, a competent engineer could recreate CX — parser, AST, format
conversions, Document API, CXPath, streaming, architecture, and language
bindings — with no divergence from the original design.

Ambiguity is a first-class defect. Wherever a reasonable implementor could
make two different correct-seeming choices and produce different behavior,
the spec has failed.

---

## Existing specs (inputs — treat as authoritative where present)

| File                    | Status   | Notes |
|-------------------------|----------|-------|
| `spec/grammar.ebnf`     | complete | CX grammar v3.3 — do not contradict |
| `spec/ast.md`           | complete | AST node types v2.3 — do not contradict |
| `spec/api.md`           | complete | Document API v2.0 — authoritative |
| `spec/cxpath.md`        | complete | CXPath v1.0 — authoritative |
| `conformance/README.md` | partial  | test format is complete; conformance contract is not |
| `CONTEXT.md`            | informal | useful background; not a spec |
| `spec/analysis.md`      | reference only | format comparison, not normative |

---

## Required spec documents

Write or complete each of the following. Where a document already exists,
extend it rather than replacing it.

---

### 1. `spec/grammar.ebnf` — CX Grammar
**Status: complete. Do not modify unless a contradiction is found.**

---

### 2. `spec/ast.md` — AST Specification
**Status: complete. Do not modify unless a contradiction is found.**

The AST spec must be sufficient to answer:
- What is the complete set of node types?
- For each node type: what fields are required, optional, and forbidden?
- What are the exact rules for when a field is omitted vs null vs empty?
- What is the difference between Parse AST and Resolved AST, and which
  operations require which?
- What is the JSON serialization format, including key names, value types,
  and omission rules?
- What are the auto-typing rules in full, including priority order and all
  patterns matched?

---

### 3. `spec/api.md` — Document API
**Status: complete. Do not modify unless a contradiction is found.**

The API spec must be sufficient to answer:
- What is the immutability model? What does "structural sharing" mean
  concretely and what are the copy semantics at each level?
- What is the exact contract of every method on Document and Element?
- What is the difference between build mode and transform mode mutation?
  When is each correct?
- What does `transform` return when the path does not exist?
- What does `transform_all` do when no elements match?
- What is the missing-value contract for every method?
- Which methods are available on Document vs Element?
- What are the parallel-safety guarantees?

---

### 4. `spec/cxpath.md` — CXPath Expression Language
**Status: complete. Do not modify unless a contradiction is found.**

The CXPath spec must be sufficient to answer:
- What is the complete expression grammar (EBNF or equivalent)?
- What is the exact evaluation semantics for each axis (`/`, `//`)?
- What predicates are supported and what is their evaluation order?
- What comparison operators exist and what are their type rules?
- What happens when a numeric operator is applied to a non-numeric value?
- What are `contains()` and `starts-with()` applied to — the attribute value
  as a string regardless of native type?
- What does `[n]` count — siblings with the same name or all siblings?
- What does `[last()]` mean when there is only one match?
- What is the context when `select`/`select_all` is called on Document vs
  Element? Is the element itself included or only descendants?
- What is the exact error contract for invalid expressions?
- What is the exact return value for no-match?
- What is the relationship between CXPath expressions and the structural API?
  When are they equivalent?

---

### 5. `spec/architecture.md` — System Architecture  *(needs writing)*

Must unambiguously answer:

**Implementation structure**
- What is V's role? Why is it the reference and not a binding?
- What is libcx? What does it compile to and what does it expose?
- What is the C ABI? What is its status (transitional) and what replaces it
  (WASM) and when?
- What is the exact boundary between what lives in libcx and what is
  implemented natively in each language binding? Give a definitive list.

**Binary wire protocol**
- What is `cx_to_ast_bin`? Give the complete binary format: byte layout,
  field order, string encoding, all node type IDs and their payloads.
- What is `cx_to_events_bin`? Give the complete binary format.
- What is the calling convention? Who allocates, who frees, what does
  NULL return mean, what does a non-NULL err_out mean?
- What is the complete list of C ABI functions, their signatures, and their
  semantics?

**Language binding contract**
- What must every conformant language binding implement? Give a definitive
  checklist.
- What may a binding omit and still be considered conformant at a given tier?
- What naming conventions apply per language (camelCase, snake_case,
  PascalCase)?
- How do CX scalar types map to native types in each language?
  (int→int64/long/i64, bool→bool, null→None/nil/null, date→string/Date, etc.)
- What are the error/exception conventions per language? When does a method
  return an error type vs panic vs raise vs return none?

**WASM transition**
- What changes when the C ABI is replaced by a WASM module?
- What stays the same (the native Document API layer)?
- What does each binding need to do differently?

---

### 6. `spec/conversions.md` — Format Conversion Semantics  *(needs writing)*

Must unambiguously answer for **each of the 30 conversion paths**
(6 inputs × 5 outputs, excluding self-to-self):

cx, xml, json, yaml, toml, md → cx, xml, json, yaml, toml, md

For each path:
- What is lossless, what is lossy, and what is the precise definition of
  each loss?
- What CX features have no equivalent in the target format and how are they
  handled (dropped, encoded, error)?
- What target format features have no CX equivalent and how are they
  handled?
- Give a canonical example: input, expected output, and explanation of any
  non-obvious transformation.

Key conversions that must be specified with particular precision:

**CX → XML**
- Round-trip vs semantic XML: what is the exact difference?
- How are CX-specific features encoded: anchors, merges, aliases,
  type annotations, block content, CX directives?
- When does the `cx:` namespace appear and when is it omitted?
- What is the CDATA split rule for `]]>` in RawText?

**CX → JSON**
- What is "semantic JSON" vs "AST JSON"? When is each produced?
- How are typed scalars represented? int vs float vs bool vs null?
- How is mixed content (text + child elements) represented?
- How are arrays represented?
- What is lost (comments, PIs, entity refs, type info)?

**XML → CX**
- How are XML namespace declarations handled?
- How are XML attributes without CX equivalents preserved?
- How is CDATA handled?
- How are processing instructions handled?

**JSON → CX**
- How are JSON arrays mapped to CX elements?
- How are JSON null values mapped?
- What is the root element name when JSON has no element concept?

---

### 7. `spec/streaming.md` — Streaming API  *(needs writing)*

Must unambiguously answer:

**Event types**
- What are all 11 StreamEvent types? For each: exact fields, field types,
  which fields are optional, what values they can take.
- What is the complete event sequence for a document? Give the ordering
  guarantees: does StartDoc always precede all element events? Does
  EndElement always follow all its child events?
- Are comments, PIs, and entity refs included in the event stream? If so,
  what event type do they produce?

**API contract**
- What does `stream(cx_str)` return? An iterator, a channel, a list?
  Specify per language idiom.
- Is streaming lazy (events produced on demand) or eager (all events
  produced upfront)?
- What happens on a parse error mid-stream?
- Can a stream be consumed more than once?

**Binary wire protocol for events**
- Give the complete binary format for `cx_to_events_bin`: byte layout,
  field order, all event type IDs and their payloads, string encoding.

---

### 8. `conformance/README.md` — Conformance Contract  *(extend existing)*

The existing file specifies the test format. It must be extended to answer:

**Format conformance (existing tests)**
- Which of the 122 tests must a Core implementation pass?
- Which tests are required for Extended feature claims?
- What does it mean to "claim" a feature? Is it all-or-nothing?

**Document API conformance (not yet covered)**
- What is the fixture set for API tests and what does each fixture test?
- What is the minimum set of API tests a conformant binding must pass?
- How are `transform` and `transform_all` tested?

**CXPath conformance (not yet covered)**
- What is the CXPath test format?
- What expressions must a conformant CXPath implementation evaluate
  correctly?
- How are predicate type errors tested?

**Streaming conformance (not yet covered)**
- What event sequences must a conformant streaming implementation produce
  for the standard fixtures?

---

## Design decisions that must be captured in the specs

These decisions were made explicitly and are not yet fully reflected in the
specs. Each spec must encode them in a way that leaves no room for a
different interpretation.

**Immutability**
Documents are immutable values. There is no mutable document type. All
"mutations" on existing documents go through `transform` or `transform_all`,
which return new documents. In-place mutation methods (`set_attr`,
`append`, etc.) exist only on Element and are correct only when the caller
owns the element (construction mode). Calling in-place methods on an element
extracted from a document does not modify the document.

**No parent pointers**
Element has no `parent` field and never will in the persistent model.
`parent::` and sibling axes are available inside CXPath expressions because
the evaluator threads traversal context internally. They are not available
as standalone API calls. Any spec section discussing navigation must make
this explicit.

**C ABI is transitional**
The C ABI is the current distribution mechanism for libcx. It is not the
target architecture. The target is WASM. Specs that describe the C ABI must
say "current mechanism" and reference WASM as the successor. Specs must not
describe the C ABI as permanent or foundational.

**CXPath expression errors panic**
An invalid CXPath expression is a programming error. Implementations must
panic or throw an unrecoverable exception. Soft error returns are incorrect.
This is different from "no match", which is not an error.

**select/select_all round-trip for non-V bindings**
In non-V language bindings, `select` and `select_all` serialise the
in-memory Document back to CX string, pass it to the libcx CXPath evaluator,
and decode binary results. This round-trip is the specified implementation
path, not an optimisation to be skipped. V does not round-trip — it
evaluates directly on the in-memory Document.

**`transform_all` uses select_all internally**
`transform_all(cxpath, fn)` is implemented as: `select_all(cxpath)` to get
paths, then iterative `transform(path, fn)` calls from deepest path first.
No callback crosses the C ABI. This decomposition must be specified.

**Language binding Document API is always native**
No Document API method (`find_all`, `at`, `attr`, `transform`, etc.) goes
through the C ABI. These are always implemented in the binding's own
language against the in-memory Document. The C ABI is for parsing, format
conversion, and CXPath evaluation only.

---

## Quality criteria

A spec section passes if a competent engineer who has never seen the CX
codebase could read it and implement the described behavior, and their
implementation would pass the conformance suite.

A spec section fails if:
- It describes what a method does without specifying what it returns for
  every possible input (including missing, empty, and error cases)
- It uses the word "appropriate", "reasonable", "typical", or "usually"
  without a normative default
- It specifies behavior for the happy path but leaves error paths implicit
- Two reasonable engineers reading it could make different implementation
  choices that produce different observable behavior
- It references a concept defined elsewhere without citing where

Every method signature in `spec/api.md` and `spec/cxpath.md` must be
accompanied by:
1. What it returns on success
2. What it returns when the target is absent (not an error)
3. What constitutes a programming error (panic/throw) vs a soft return

Every binary format in `spec/architecture.md` and `spec/streaming.md` must
include a hex-annotated example that can be used as a test vector.
