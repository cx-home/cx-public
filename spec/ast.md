# CX AST Specification
# Version: 2.3
# Date: 2026-04-19

Both the CX parser and XML parser produce this AST. It is the canonical representation
shared by all emitters (CX, XML, JSON) and all language implementations.

---

## Conventions

- Optional fields are omitted when absent/null/empty — never serialized as null or [].
- `string` fields store literal values with no implicit escaping or normalization.
- Node types are identified by the `type` field (string discriminant).
- All field names use camelCase. No cx: prefixes in AST field names.

---

## Parse AST vs. Resolved AST

Two phases produce different ASTs from the same source. Parsers MUST document which
they return, and provide a resolver if they return Parse AST.

**Parse AST** — exact structural representation of what was parsed:
- `CXDirective` include nodes are preserved as-is (file not expanded)
- `Alias` nodes are preserved (not replaced with the anchored element)
- `anchor` and `merge` fields on elements are preserved (not resolved)
- Used for: round-trip serialization, source tools, formatters

**Resolved AST** — fully expanded, semantically complete:
- `[?cx include=file.cx]` nodes are replaced with the parsed content of that file
- `[*name]` alias nodes are replaced with a deep copy of the anchored element
- `merge` references are resolved (anchor attrs/items merged, local attrs override)
- Used for: XML emission, validation, code generation, data binding

When emitting XML, the emitter MUST work from the Resolved AST.

---

## Document

```json
{
  "type": "Document",
  "prolog": [],     // XMLDecl, PI, CXDirective, Comment — omitted if empty
  "doctype": {},    // DoctypeDecl — omitted if absent
  "elements": []    // top-level nodes — same set as element body nodes (see below)
}
```

`elements` may contain: Element, Scalar, Text, BlockContent, Alias, EntityRef, RawText,
Comment, PI, CXDirective, EntityDecl, ElementDecl, AttlistDecl, NotationDecl, ConditionalSect.
Text and EntityRef at the top level represent loose mixed content (no wrapping element).

A file using `---` separators produces multiple Document nodes (stream or array).
Each Document is independent — anchors, entities, and declarations do not cross boundaries.

Top-level Scalar and Text nodes are allowed (loose content at document level):
```json
{"type": "Document", "elements": [{"type": "Scalar", "dataType": "int", "value": 42}]}
```

---

## XMLDecl

```json
{
  "type": "XMLDecl",
  "version": "1.0",
  "encoding": "UTF-8",   // omitted if absent
  "standalone": "yes"    // omitted if absent; "yes" or "no"
}
```

CX: `[?xml version=1.0 encoding=UTF-8]`
XML: `<?xml version="1.0" encoding="UTF-8"?>`

Must be first item in `prolog` when present.

---

## CXDirective

```json
{
  "type": "CXDirective",
  "attrs": [{"name": "include", "value": "base.cx"}]
}
```

CX: `[?cx include=base.cx]`
XML: `<?cx include="base.cx"?>` (serializes as a standard XML PI)

Known attrs: `include` (file path), `schema` (schema path), `version` (CX version).
In Parse AST: preserved as CXDirective node.
In Resolved AST: `include` directives are expanded inline; others remain.

---

## PI (Processing Instruction)

```json
{
  "type": "PI",
  "target": "php",
  "data": "echo $foo;"   // omitted if empty
}
```

CX: `[?php echo $foo;]`
XML: `<?php echo $foo;?>`

`data` is a raw string — not parsed as name=value pairs.
`target` is never `xml` or `cx` (those produce XMLDecl and CXDirective).

---

## Comment

```json
{"type": "Comment", "value": "comment text"}
```

CX: `[-comment text]`
XML: `<!--comment text-->`

---

## DoctypeDecl

```json
{
  "type": "DoctypeDecl",
  "name": "html",
  "externalID": {"public": "-//W3C//DTD...", "system": "http://..."},
  "intSubset": []   // omitted if empty
}
```

### ExternalID

```json
{"system": "file.dtd"}
{"public": "-//Example//EN", "system": "file.dtd"}
```

SystemLiteral and PubidLiteral are always single-quoted in CX output.

---

## Element

```json
{
  "type": "Element",
  "name": "person",
  "anchor": "def",        // omitted if absent (Parse AST only)
  "merge": "def",         // omitted if absent (Parse AST only)
  "dataType": "string[]", // omitted if absent — from TypeAnnotation
  "attrs": [],            // Attribute[] — omitted if empty
  "items": []             // Node[] — omitted if empty
}
```

`anchor` and `merge` are present in Parse AST. In Resolved AST they are removed
after resolution.

`dataType` carries the TypeAnnotation value (`:int`, `:string[]`, etc.) when present.
Emitters MUST always store the canonical long form (`int`, not `i`; `string[]`, not `s[]`).

### Attribute

```json
{"name": "href", "value": "https://example.com"}
{"name": "port", "value": 8080, "dataType": "int"}
{"name": "debug", "value": true, "dataType": "bool"}
```

BareValue attribute values are auto-typed using the same scalar priority as body
scalars (see Scalar › Auto-typing rule). The `dataType` field is present when the
value is non-string; string is the default and is omitted. QuotedText attribute
values are always string — use `'8080'` to force a numeric-looking value to string.
Array auto-type does not apply to attribute values.

XML emission: attribute values are always serialized as strings in XML output. Type
information is recovered on re-parse via the same auto-typing rule — round-trips are
lossless for values that auto-type consistently (numbers, bools, dates). To preserve
a string value that would otherwise auto-type, use QuotedText (`'8080'`).

### Examples

`[p class=note Hello]`
```json
{
  "type": "Element", "name": "p",
  "attrs": [{"name": "class", "value": "note"}],
  "items": [{"type": "Text", "value": "Hello"}]
}
```

`[server host=localhost port=8080 debug=false]`
```json
{
  "type": "Element", "name": "server",
  "attrs": [
    {"name": "host",  "value": "localhost"},
    {"name": "port",  "value": 8080,  "dataType": "int"},
    {"name": "debug", "value": false, "dataType": "bool"}
  ]
}
```

`[tags :string[] admin user guest]`
```json
{
  "type": "Element", "name": "tags", "dataType": "string[]",
  "items": [
    {"type": "Scalar", "dataType": "string", "value": "admin"},
    {"type": "Scalar", "dataType": "string", "value": "user"},
    {"type": "Scalar", "dataType": "string", "value": "guest"}
  ]
}
```

`[defaults &def timeout=30 retries=3]` (Parse AST)
```json
{
  "type": "Element", "name": "defaults", "anchor": "def",
  "attrs": [
    {"name": "timeout", "value": 30, "dataType": "int"},
    {"name": "retries", "value": 3,  "dataType": "int"}
  ]
}
```

`[production *def host=prod.example.com]` (Parse AST)
```json
{
  "type": "Element", "name": "production", "merge": "def",
  "attrs": [{"name": "host", "value": "prod.example.com"}]
}
```

---

## Alias

```json
{"type": "Alias", "name": "def"}
```

CX: `[*def]`
XML: `<cx:alias name="def"/>` (Parse AST) or expanded element (Resolved AST)

In Resolved AST, Alias nodes are replaced with a deep copy of the anchored element.

---

## Text

```json
{"type": "Text", "value": "Hello world"}
```

`value` is the literal character content after whitespace rules are applied:
- **CX unquoted**: S between tokens → single space; adjacency → no space
- **CX quoted** (`'...'`): whitespace preserved exactly
- **CX triple-quoted** (`'''...'''`): whitespace preserved; common indent stripped
- **CX block** (`[|...|]`): whitespace preserved; common indent stripped (see BlockContent)
- **XML**: whitespace preserved exactly

The CX emitter wraps Text in single quotes when the value contains leading/trailing
whitespace, consecutive spaces, or newlines — unless the value spans multiple lines,
in which case the emitter SHOULD use TripleQuoted form.

Text nodes contain only string content. Typed tokens produce Scalar nodes.

---

## Scalar

Typed value node. Produced by explicit TypeAnnotation or by auto-typing.

```json
{"type": "Scalar", "dataType": "int",      "value": 30}
{"type": "Scalar", "dataType": "float",    "value": 3.14}
{"type": "Scalar", "dataType": "bool",     "value": true}
{"type": "Scalar", "dataType": "null",     "value": null}
{"type": "Scalar", "dataType": "string",   "value": "hello"}
{"type": "Scalar", "dataType": "date",     "value": "2026-04-19"}
{"type": "Scalar", "dataType": "datetime", "value": "2026-04-19T14:30:00Z"}
{"type": "Scalar", "dataType": "bytes",    "value": "SGVsbG8="}
```

`value` uses native JSON types: number for int/float, boolean for bool, null for null,
string for date/datetime/bytes/string.

`dataType` always stores the canonical long form (`int`, `string[]`, etc.) regardless
of whether a short alias (`:i`, `:s[]`) was used in source.

### Auto-typing rule

**Scalar auto-type:** applies when an element's body is a single unquoted token with
no child elements. Priority for that token:

1. Matches `0x[0-9a-fA-F]+` → `int`
2. Matches integer pattern → `int`
3. Matches float/scientific pattern → `float`
4. `true` or `false` → `bool`
5. `null` → `null`
6. Matches ISO 8601 datetime → `datetime`
7. Matches ISO 8601 date → `date`
8. Otherwise → `Text`

**Array auto-type:** applies when an element's body has 2+ unquoted tokens with no
child elements and no TypeAnnotation. Each token is tested against the scalar priority
above. If all tokens resolve to the same non-string type the element body becomes an
array of that type. Mixed int+float tokens promote to `float[]`. Any other mix, or
any token that falls through to Text, leaves the body as Text — no array is produced.
String tokens never trigger array auto-type; string arrays always require `:[]` or `:s[]`.

**Attribute auto-type:** BareValue attribute values follow the scalar priority. Array
auto-type does not apply to attributes.

Explicit TypeAnnotation overrides all auto-typing in all contexts.
QuotedText is always `Text`, never `Scalar`.
`:bytes` is always explicit — never auto-typed.

### TypeAnnotation and short aliases

Short aliases in source (`:i`, `:f`, `:b`, `:s`, `:d`, `:dt`) are equivalent to their
long forms. The AST always stores canonical long-form `dataType` strings. The short
alias `:[]` produces an inferred-type array: non-string tokens → that type;
any string token → `string[]`.

```
[age 30]            → Scalar int 30          (scalar auto-type)
[scores 10 20 30]   → Array  int[] [10,20,30] (array auto-type)
[tags :[] a b c]    → Array  string[] (inferred via :[], tokens are strings)
[tags :s[] a b c]   → Array  string[] (explicit short alias)
[port :i 8080]      → Scalar int 8080        (explicit short alias)
[port '8080']       → Text   "8080"          (quoted → always Text)
[scores :s[] 1 2 3] → Array  string[]        (override auto-int with :s[])
```

### Scalar in XML

Auto-typed scalar: `[age 30]` → `<age>30</age>`
Explicit scalar:   `[age :int 30]` → `<age cx:type="int">30</age>`
Auto-typed array:  `[scores 10 20 30]` → `<scores cx:type="int[]"><item>10</item>...</scores>`
Explicit array:    `[tags :string[] a b]` → `<tags cx:type="string[]"><item>a</item>...</tags>`

---

## BlockContent

Parsed block literal. Content is parsed as normal CX body items but newlines are
preserved literally rather than normalized to spaces.

```json
{
  "type": "BlockContent",
  "items": []    // Node[] — same set as element body items
}
```

CX: `[| ... ]`
XML round-trip: `<cx:block>...</cx:block>`
Semantic XML: items inlined directly into the parent element's content (no wrapper)

`items` may contain: Text (with literal newlines), Element, Scalar, EntityRef,
RawText, BlockContent (nested), Comment, PI, CXDirective.

Whitespace processing applied to the raw block content:
1. One leading newline immediately after `[|` is stripped.
2. One trailing newline immediately before the closing `]` is stripped.
3. Common leading whitespace of all non-blank lines is stripped.

BlockContent is the preferred form for mixed content where newlines are significant —
poetry, preformatted prose, code with inline markup, template literals.

### Examples

```
[poem
  [|
    Roses are red,
    Violets are blue,
    CX is [em elegant],
    And YAML is through.
  ]
]
```
```json
{
  "type": "Element", "name": "poem",
  "items": [{
    "type": "BlockContent",
    "items": [
      {"type": "Text", "value": "Roses are red,\nViolets are blue,\nCX is "},
      {"type": "Element", "name": "em",
       "items": [{"type": "Text", "value": "elegant"}]},
      {"type": "Text", "value": ",\nAnd YAML is through.\n"}
    ]
  }]
}
```

XML (semantic): `<poem>Roses are red,\nViolets are blue,\nCX is <em>elegant</em>,\nAnd YAML is through.\n</poem>`

---

## EntityRef

```json
{"type": "EntityRef", "name": "amp"}
```

CX/XML: `&amp;`

Predefined entities (`amp`, `lt`, `gt`, `quot`, `apos`) are **never resolved**.
They remain as EntityRef nodes for round-trip fidelity: `&amp;` → `EntityRef("amp")` → `&amp;`.

CharRefs (`&#NNN;`, `&#xHHH;`) are resolved to their Unicode character and stored
as a single-character Text node.

---

## RawText (CDATA)

```json
{"type": "RawText", "value": "if (x < y) { return [1,2,3]; }"}
```

CX: `[# if (x < y) { return [1,2,3]; } #]`
XML: `<![CDATA[if (x < y) { return [1,2,3]; }]]>`

Raw text uses `#]` as its two-character terminator, allowing bare `]` inside.
Inner CX elements are NOT parsed — use BlockContent when inner elements are needed.

**CDATA split rule:** When emitting XML, if `value` contains the sequence `]]>`,
the emitter MUST split it using adjacent CDATA sections:
```
]]>  →  ]]><![CDATA[>
```
Example: `value = "a]]>b"` → `<![CDATA[a]]><![CDATA[>b]]>`.
XML parsers reassemble adjacent CDATA sections into the original content.
The `]]>` sequence is valid in CX raw text (only `#]` is forbidden in CX source).

---

## EntityDecl

```json
{
  "type": "EntityDecl",
  "kind": "GE",
  "name": "ext",
  "def": {"externalID": {"system": "external.txt"}}
}
```

`kind`: `"GE"` (general) or `"PE"` (parameter).
`def`: string for internal entities; ExternalEntityDef object for external.

### ExternalEntityDef

```json
{
  "externalID": {"system": "file.ent"},
  "ndata": "gif"    // omitted if absent
}
```

---

## ElementDecl

```json
{"type": "ElementDecl", "name": "p", "contentspec": "(#PCDATA|b|em)*"}
```

`contentspec` stored as raw string.

---

## AttlistDecl

```json
{
  "type": "AttlistDecl",
  "name": "img",
  "defs": [
    {"name": "src",  "type": "CDATA", "default": "#REQUIRED"},
    {"name": "alt",  "type": "CDATA", "default": "#IMPLIED"}
  ]
}
```

---

## NotationDecl

```json
{
  "type": "NotationDecl",
  "name": "gif",
  "publicID": "image/gif",
  "systemID": "viewer.exe"
}
```

At least one of `publicID` or `systemID` present.

---

## ConditionalSect

```json
{
  "type": "ConditionalSect",
  "kind": "include",
  "subset": []
}
```

CX: `[![INCLUDE[ ... ]]]`
XML: `<![INCLUDE[ ... ]]>`

IGNORE sections preserve their `subset` for round-trip fidelity.

---

## cx: Namespace

Namespace URI: `https://cxformat.org/ns`
Reserved prefix: `cx` — documents may not use `ns:cx` as a namespace alias.

CX AST fields map to XML `cx:` attributes. Two XML output modes exist (see below):

| AST field           | Round-trip XML            | Semantic XML              |
|---------------------|---------------------------|---------------------------|
| `element.anchor`    | `cx:anchor="name"`        | omitted (resolved)        |
| `element.merge`     | `cx:merge="name"`         | omitted (resolved)        |
| `element.dataType`  | `cx:type="string[]"`      | `cx:type="string[]"`      |
| `alias.name`        | `<cx:alias name="name"/>` | expanded element (clone)  |
| `CXDirective`       | `<?cx ...?>`              | omitted / inlined         |
| `BlockContent`      | `<cx:block>...</cx:block>`| items inlined into parent |

---

## XML Output Modes

**Round-trip XML** (from Parse AST) — preserves all CX structure as `cx:`
attributes and PIs. Used for tooling, formatters, and conformance tests.
Alias nodes emit as `<cx:alias name="…"/>`. `cx:anchor`, `cx:merge`, `cx:type`
are preserved on elements. CXDirective emits as `<?cx …?>`. BlockContent emits
as `<cx:block>`.

**Semantic XML** (from Resolved AST) — expands all aliases, inlines includes,
resolves merges. Suitable for XML consumers that do not understand `cx:`.
Only `cx:type` is preserved (to carry type information for re-parsing).
BlockContent items are inlined into the parent element without a wrapper.
Requires the resolver pass (future; not covered by conformance tests v1.0).

Conformance tests specify Round-trip XML in their `out_xml` sections.

---

## Node type summary

| Type            | Core/Ext | CX syntax               | XML syntax (round-trip)        |
|-----------------|----------|-------------------------|--------------------------------|
| Document        | Core     | (document)              | (document)                     |
| XMLDecl         | Core     | [?xml ...]              | <?xml ...?>                    |
| CXDirective     | Core     | [?cx include=f.cx]      | <?cx include="f.cx"?>          |
| PI              | Core     | [?target data]          | <?target data?>                |
| Comment         | Core     | [-text]                 | <!--text-->                    |
| DoctypeDecl     | Core     | [!DOCTYPE ...]          | <!DOCTYPE ...>                 |
| Element         | Core     | [name ...]              | <name>...</name>               |
| Alias           | Extended | [*name]                 | <cx:alias name="name"/>        |
| Text            | Core     | word or 'phrase'        | text node                      |
| Text            | Extended | '''multiline'''         | text node                      |
| Scalar          | Extended | 30  true  2026-04-19    | text node (+ cx:type opt.)     |
| BlockContent    | Extended | [| ... ]                | <cx:block>...</cx:block>       |
| EntityRef       | Core     | &name;                  | &name;                         |
| RawText         | Core     | [# content #]           | <![CDATA[content]]>            |
| EntityDecl      | Core     | [!ENTITY ...]           | <!ENTITY ...>                  |
| ElementDecl     | Extended | [!ELEMENT ...]          | <!ELEMENT ...>                 |
| AttlistDecl     | Extended | [!ATTLIST ...]          | <!ATTLIST ...>                 |
| NotationDecl    | Extended | [!NOTATION ...]         | <!NOTATION ...>                |
| ConditionalSect | Extended | [![INCLUDE[...]]]       | <![INCLUDE[...]]>              |

EntityDecl is Core because EntityRef is Core — entity declarations define the
names that appear as EntityRef nodes. ElementDecl, AttlistDecl, NotationDecl,
and ConditionalSect are Extended (DTD schema declarations, not needed to parse
element content).

---

## JSON serialization

`ast_to_json` produces a JSON representation for inspection, testing, and interop.

- All optional/empty fields omitted.
- Scalar `value` uses native JSON types.
- `dataType` always uses long-form canonical names (`int`, `string[]`, not `i`, `s[]`).
- Key order is not significant; implementations may sort keys for stability.

**Mixed content:** `[p Hello [b world] and [em you]]`
```json
{
  "type": "Document",
  "elements": [{
    "type": "Element", "name": "p",
    "items": [
      {"type": "Text", "value": "Hello"},
      {"type": "Element", "name": "b",
       "items": [{"type": "Text", "value": "world"}]},
      {"type": "Text", "value": "and"},
      {"type": "Element", "name": "em",
       "items": [{"type": "Text", "value": "you"}]}
    ]
  }]
}
```

**Typed data with auto-typed attributes:**
`[server host=localhost port=8080 debug=false]`
```json
{
  "type": "Document",
  "elements": [{
    "type": "Element", "name": "server",
    "attrs": [
      {"name": "host",  "value": "localhost"},
      {"name": "port",  "value": 8080,  "dataType": "int"},
      {"name": "debug", "value": false, "dataType": "bool"}
    ]
  }]
}
```

**Auto-typed array:** `[scores 10 20 30]`
```json
{
  "type": "Document",
  "elements": [{
    "type": "Element", "name": "scores", "dataType": "int[]",
    "items": [
      {"type": "Scalar", "dataType": "int", "value": 10},
      {"type": "Scalar", "dataType": "int", "value": 20},
      {"type": "Scalar", "dataType": "int", "value": 30}
    ]
  }]
}
```

**Mixed typed data:** `[person [age 30] [active true] [tags :[] admin user]]`
```json
{
  "type": "Document",
  "elements": [{
    "type": "Element", "name": "person",
    "items": [
      {"type": "Element", "name": "age",
       "items": [{"type": "Scalar", "dataType": "int", "value": 30}]},
      {"type": "Element", "name": "active",
       "items": [{"type": "Scalar", "dataType": "bool", "value": true}]},
      {"type": "Element", "name": "tags", "dataType": "string[]",
       "items": [
         {"type": "Scalar", "dataType": "string", "value": "admin"},
         {"type": "Scalar", "dataType": "string", "value": "user"}
       ]}
    ]
  }]
}
```
