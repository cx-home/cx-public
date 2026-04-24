# CX Format Conversion Semantics
# Version: 1.0
# Date: 2026-04-23

This document specifies the semantics of all 30 conversion paths between the 6
supported formats: CX, XML, JSON, YAML, TOML, and Markdown. Self-to-self paths
are covered in §1 (normalization). All 30 cross-format paths are specified in §2
through §7.

---

## Conventions

**Lossless** — a round-trip through the target format and back to CX recovers the
original CX document with identical content and structure.

**Lossy** — some information in the source is not representable in the target format.
When this document says a conversion is lossy, it names the specific information lost.
A binding MUST NOT silently discard information that could be encoded; it drops only
what the target format cannot represent.

**Error** — the source document contains features that are not only non-representable
in the target but cause the conversion to fail. All format errors are communicated
via the calling convention's error mechanism (see `spec/architecture.md §2`).

---

## 1 — Self-to-self (normalization)

Self-to-self conversions normalize the source. They are not format conversions.

| Path | Effect |
|------|--------|
| `cx_to_cx` | Canonical CX: consistent indentation, normalized whitespace, attributes in document order |
| `cx_to_cx_compact` | CX with all optional whitespace removed (one-line form) |
| `xml_to_xml` | Round-tripped through the CX AST — normalizes whitespace and attribute ordering |
| `json_to_json` | Round-tripped through the CX semantic model — normalizes key ordering |
| `yaml_to_yaml` | Round-tripped — normalizes YAML style |
| `toml_to_toml` | Round-tripped — normalizes TOML table ordering |
| `md_to_md` | Round-tripped — normalizes Markdown whitespace |

---

## 2 — CX as input

CX is the most expressive format. Converting from CX to any other format is the
primary lossy direction. CX features that have no equivalent in the target format
are handled as described below.

### 2.1 — CX → XML

**Function:** `cx_to_xml`

CX → XML is **round-trip preserving**: all CX features are encoded in the output
using the `cx:` namespace. A round-trip `cx_to_xml` → `xml_to_cx` recovers the
original CX document.

**cx: namespace elements and attributes:**

| CX feature | XML encoding |
|------------|--------------|
| Element anchor (`&name`) | `cx:anchor="name"` attribute |
| Element merge (`<<name`) | `cx:merge="name"` attribute |
| Element type annotation (`:type`) | `cx:type="type"` attribute |
| AliasNode (`*name`) | `<cx:alias name="name"/>` element |
| BlockContent node | `<cx:block>...</cx:block>` element |
| CX namespace attrs (`ns:prefix`) | Converted to `xmlns:prefix="..."` |

The `cx:` namespace prefix is used whenever a CX feature has no XML equivalent.
It is absent from XML output that contains no CX-specific features.

**Arrays:**

An element with a type annotation ending in `[]` (e.g., `:string[]`) encodes its
scalar children as `<item>` elements:

```cx
[tags :string[] core internal]
```
```xml
<tags cx:type="string[]"><item>core</item><item>internal</item></tags>
```

**CDATA split rule:**

RawText nodes are emitted as XML CDATA sections. The sequence `]]>` cannot appear
inside a CDATA section. Occurrences of `]]>` in RawText are split:

```
]]>  →  ]]><![CDATA[>
```

The result is two adjacent CDATA sections whose concatenated content equals the
original.

**Mixed content:**

Elements whose body contains both text/scalars and child elements are emitted
inline (opening and closing tag on one line). Elements whose body contains only
child elements are emitted with indented children on separate lines.

**Text and scalar content:**

TextNodes are XML-escaped (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`).
ScalarNodes are emitted as their string representation (typed values round-trip
via `cx:type`).

**Comments, PIs, XMLDecl:**

CommentNodes → `<!-- ... -->`. PINodes → `<?target data?>`. XMLDeclNode →
`<?xml version="1.0" ...?>`. These are all preserved.

**EntityRef:**

EntityRefNodes are emitted as XML entity references: `&name;`.

**What is NOT lossless:**

When the output is used by a non-CX consumer and the `cx:` attributes are
stripped, the following are lost: anchors, merges, aliases, type annotations,
BlockContent structure. The XML elements and their content remain correct.

**Canonical example:**

```cx
[config &srv
  [server host=localhost port=8080 :int]
  [tags :string[] web api]
]
```

```xml
<config cx:anchor="srv">
  <server cx:type="int" host="localhost" port="8080"/>
  <tags cx:type="string[]"><item>web</item><item>api</item></tags>
</config>
```

---

### 2.2 — CX → JSON (semantic)

**Function:** `cx_to_json`

Produces **semantic JSON**: a data-oriented representation that resolves typed
values to native JSON types. This is distinct from AST JSON (`cx_to_ast`), which
encodes the full parse tree.

**Conversion rules:**

| CX element form | JSON output |
|-----------------|-------------|
| Element with attrs only | JSON object with attr names as keys |
| Element with text only (no attrs, no child elements) | JSON string |
| Element with a single scalar (no attrs, no children) | JSON native value |
| Element with multiple scalars only (array form) | JSON array |
| Element with attrs + body text | JSON object with attr keys + `"_"` for body |
| Element with child elements | JSON object with child element names as keys |
| Multiple same-named children | JSON array under that key |
| Empty element (no attrs, no body) | JSON null |

**Typed scalar to JSON:**

| CX scalar type | JSON output |
|----------------|-------------|
| int            | JSON number (no decimal point) |
| float          | JSON number (with decimal point or `e` notation) |
| bool           | JSON boolean |
| null           | JSON null |
| string         | JSON string |
| date           | JSON string (ISO 8601) |
| datetime       | JSON string (ISO 8601) |

**Mixed content** (element has both text and child elements):

The text is captured under the key `"_"`. Child elements are emitted as their
named keys. If multiple text segments exist, they are concatenated.

**Multiple documents:**

A multi-document stream produces a JSON array, one object per document.

**What is lost** (semantic JSON is always lossy from CX):

- Comments (dropped)
- Processing instructions (dropped)
- Entity refs (resolved to their character equivalents for standard XML entities:
  `&amp;` → `&`, `&lt;` → `<`, `&gt;` → `>`, `&apos;` → `'`, `&quot;` → `"`;
  unrecognised entity refs emitted as `&name;`)
- Type annotations on elements (dropped; value type is inferred in the output)
- Anchors, merges, aliases (dropped)
- BlockContent structure (content inlined)
- Attribute type information (int and float both become JSON numbers; a consumer
  cannot distinguish `int` from `float` without the source)
- Element structure for pure-text elements (collapsed to string)

**AST JSON vs semantic JSON:**

`cx_to_ast` produces the **full parse tree** as JSON, including all node types,
type metadata, anchors, and aliases. It is used for tooling (debuggers, tree-sitter,
external processors). Language bindings use `cx_to_ast_bin` instead.

`cx_to_json` produces **data-oriented JSON** that erases CX structure. Use it
for data binding (`loads`/`dumps`-style) when the caller wants native types.

**Canonical example:**

```cx
[server host=localhost port=8080 debug=false]
[tags :string[] web api]
```

```json
{
  "server": {
    "host": "localhost",
    "port": 8080,
    "debug": false
  },
  "tags": ["web", "api"]
}
```

---

### 2.3 — CX → YAML

**Function:** `cx_to_yaml`

CX → YAML maps the document to a YAML mapping. The conversion is **lossy**.

**Conversion rules:**

| CX construct | YAML output |
|--------------|-------------|
| Element with attrs only | YAML mapping |
| Element with scalar body only | YAML scalar |
| Element with text body only | YAML string |
| Child elements | Nested YAML mappings |
| Multiple same-named children | YAML sequence |
| Array element (`:type[]`) | YAML sequence |

**What is lost:**

- Comments (dropped)
- Processing instructions (dropped)
- Entity refs (resolved)
- Anchors and merges (YAML has its own anchor/alias mechanism; CX anchors are dropped,
  not converted to YAML anchors)
- Type annotations (YAML auto-infers from value)
- BlockContent (content inlined)
- Element names for children (they become YAML mapping keys; if multiple elements
  share the same name they become a sequence, but the element name itself is
  preserved as the key)

---

### 2.4 — CX → TOML

**Function:** `cx_to_toml`

CX → TOML maps elements to TOML tables and attributes to TOML key-value pairs.
The conversion is **lossy**.

**Conversion rules:**

| CX construct | TOML output |
|--------------|-------------|
| Top-level element | TOML `[table]` |
| Element attrs | TOML key = value pairs |
| Nested element | Nested TOML `[parent.child]` table |
| Multiple same-named children | TOML `[[array of tables]]` |
| Scalar values | TOML integer, float, boolean, string, datetime as appropriate |

**What is lost:**

- Comments (TOML has comments but CX comments are not mapped)
- Processing instructions (dropped)
- Entity refs (resolved)
- Anchors, merges, aliases (dropped)
- Text body content without attrs (no equivalent in TOML key-value model)
- Mixed content (text + elements) (text dropped when children present)
- BlockContent (dropped)
- Type annotations (TOML infers from value)

**Constraint:** TOML cannot represent arbitrary nesting of elements with both
attributes and child text. Elements that mix attrs and text body produce TOML
tables where the body text is dropped.

---

### 2.5 — CX → Markdown

**Function:** `cx_to_md`

CX → Markdown maps CX element names to Markdown constructs based on a semantic
mapping of common element names. The conversion is **lossy**.

**Element name to Markdown mapping:**

| CX element name | Markdown output |
|-----------------|----------------|
| `h1` | `# text` |
| `h2` | `## text` |
| `h3` | `### text` |
| `h4` | `#### text` |
| `h5` | `##### text` |
| `h6` | `###### text` |
| `p` | paragraph (plain text + blank line) |
| `ul` | unordered list |
| `ol` | ordered list |
| `li` | list item (`- text`) |
| `pre`, `code` | fenced code block (` ``` `) |
| `em`, `i` | `*text*` |
| `strong`, `b` | `**text**` |
| `a` | `[text](href)` (uses `href` attr) |
| `img` | `![alt](src)` (uses `alt` and `src` attrs) |
| `blockquote` | `> text` |
| `hr` | `---` |
| other elements | omitted or rendered as plain text |

**What is lost:**

- Attributes (except `href` for `a`, `src`/`alt` for `img`)
- Comments
- Processing instructions
- Entity refs (resolved)
- Anchors, merges, aliases
- Type annotations
- Elements with no Markdown equivalent (rendered as their text content or dropped)
- Structural nesting beyond what Markdown supports

---

## 3 — XML as input

### 3.1 — XML → CX

**Function:** `cx_xml_to_cx`

XML → CX is the inverse of CX → XML. Round-tripping `cx_to_xml` → `xml_to_cx`
recovers the original CX document. Direct XML → CX (from non-CX-originated XML)
maps XML constructs to CX as follows:

**Conversion rules:**

| XML construct | CX output |
|---------------|-----------|
| XML element | CX Element |
| XML attribute | CX Attr |
| Namespace declaration `xmlns:prefix="uri"` | CX Attr `ns:prefix=uri` |
| Default namespace declaration `xmlns="uri"` | CX Attr `ns:default=uri` |
| Text content | TextNode |
| CDATA section | RawTextNode |
| Comment `<!-- ... -->` | CommentNode |
| Processing instruction `<?target data?>` | PINode |
| XML declaration `<?xml ...?>` | XMLDeclNode |
| DOCTYPE declaration | DoctypeDecl |
| Entity references `&name;` | EntityRefNode |
| `cx:anchor` attribute | Sets Element `anchor` field; attribute removed |
| `cx:merge` attribute | Sets Element `merge` field; attribute removed |
| `cx:type` attribute | Sets Element `data_type` field; attribute removed |
| `<cx:alias name="..."/>` element | AliasNode |
| `<cx:block>...</cx:block>` | BlockContentNode |

**CDATA → RawText:** CDATA sections become RawTextNode values. Adjacent CDATA
sections that were split by the CDATA split rule (see §2.1) are merged back into
a single RawTextNode.

**Namespace attributes:** XML namespace declarations are preserved as CX attrs
with the `ns:` prefix convention. This allows round-tripping namespace-aware XML
through CX without loss.

---

### 3.2 — XML → JSON

**Function:** `cx_xml_to_json`

XML → CX → semantic JSON. The same rules as CX → JSON (§2.2) apply, after the
XML is first parsed to a CX Document. What is lost is the union of losses in
XML → CX (none, since that is lossless) and CX → JSON (lossy; see §2.2).

In practice: namespace declarations, PIs, comments, and CDATA are all dropped.
Element attrs become JSON keys. Namespace URIs from `xmlns:` declarations are
dropped.

---

### 3.3 — XML → YAML

**Function:** `cx_xml_to_yaml`

XML → CX → YAML. Same rules as §2.3 after XML→CX parse.

---

### 3.4 — XML → TOML

**Function:** `cx_xml_to_toml`

XML → CX → TOML. Same rules as §2.4 after XML→CX parse.

---

### 3.5 — XML → Markdown

**Function:** `cx_xml_to_md`

XML → CX → Markdown. Same rules as §2.5 after XML→CX parse.

---

## 4 — JSON as input

### 4.1 — JSON → CX

**Function:** `cx_json_to_cx`

JSON → CX maps JSON values to CX elements and scalars. This is the **inverse** of
the semantic JSON emitter (§2.2).

**Conversion rules:**

| JSON value | CX output |
|------------|-----------|
| Top-level JSON object | Document with one Element per top-level key |
| Nested JSON object | Element whose name is the enclosing key; each key becomes a child element or attr depending on depth |
| JSON string value under a key | Element containing a TextNode or Attr value |
| JSON number (integer) | ScalarNode with `int` type |
| JSON number (floating-point) | ScalarNode with `float` type |
| JSON boolean | ScalarNode with `bool` type |
| JSON null | Empty Element (no attrs, no body) |
| JSON array (homogeneous scalars) | Element with `:type[]` annotation and scalar children |
| JSON array (mixed or nested objects) | Repeated child Elements with the enclosing key's name |

**Root element name:**

When the top-level JSON is an object, each key becomes a top-level Element in the
CX Document. There is no unnamed wrapper element. For a JSON object with a single
key, the document has a single root element with that name.

Example: `{"server": {"host": "localhost", "port": 8080}}` →
```cx
[server
  [host localhost]
  [port 8080]
]
```

The `host` and `port` values become child elements (since they were nested JSON
object values). If the JSON representation uses the `cx_to_json` convention of
placing scalar attrs as object keys at the same level, those round-trip correctly:

`{"server": {"host": "localhost", "port": 8080}}` →
```cx
[server
  [host localhost]
  [port 8080]
]
```

Note: JSON → CX does not reconstruct attribute-bearing elements from semantic JSON.
A JSON object `{"port": 8080}` under key `server` becomes a nested `[server [port 8080]]`
tree, not `[server port=8080]`. Full attribute reconstruction from semantic JSON would
require schema knowledge not available at conversion time.

**Arrays:**

A JSON array of scalars → element with `:type[]` annotation:
```json
{"tags": ["web", "api"]}
```
```cx
[tags :string[]
  web
  api
]
```

A JSON array of objects → repeated same-named child elements:
```json
{"services": [{"name": "auth"}, {"name": "api"}]}
```
```cx
[services
  [service
    [name auth]
  ]
  [service
    [name api]
  ]
]
```

The parent key name (`services`) becomes the wrapper element; each array element
becomes a child element named by removing a trailing `s` if present, otherwise
using the parent name. (Implementation note: the exact singularisation rule is:
the child element name is the key with trailing `s` removed; if the result is
empty or would be the same as the original, the original key is used.)

**What is lossless:** JSON scalars, strings, booleans, null, and numbers
round-trip correctly. JSON arrays round-trip.

**What is added:** Element structure that was not in the source JSON (CX always
requires named elements).

---

### 4.2 — JSON → XML

**Function:** `cx_json_to_xml`

JSON → CX → XML. Applies §4.1 then §2.1 (XML round-trip emitter).

---

### 4.3 — JSON → YAML

**Function:** `cx_json_to_yaml`

JSON → CX → YAML. Applies §4.1 then §2.3.

---

### 4.4 — JSON → TOML

**Function:** `cx_json_to_toml`

JSON → CX → TOML. Applies §4.1 then §2.4.

---

### 4.5 — JSON → Markdown

**Function:** `cx_json_to_md`

JSON → CX → Markdown. Applies §4.1 then §2.5. Generally not meaningful unless
the JSON models a document structure with semantic element names.

---

## 5 — YAML as input

### 5.1 — YAML → CX

**Function:** `cx_yaml_to_cx`

YAML → CX maps YAML structures to CX elements, attrs, and scalars.

**Conversion rules:**

| YAML construct | CX output |
|----------------|-----------|
| YAML mapping | Element with child elements per key (or attrs for scalar values at top level) |
| YAML scalar string | TextNode or ScalarNode depending on auto-typing |
| YAML integer | ScalarNode with `int` type |
| YAML float | ScalarNode with `float` type |
| YAML boolean (`true`/`false`) | ScalarNode with `bool` type |
| YAML null (`~`, `null`) | ScalarNode with `null` type |
| YAML sequence | Repeated same-named child elements |
| YAML anchor (`&name`) | Not encoded in CX (YAML anchors are resolved before CX output) |
| YAML alias (`*name`) | Resolved before CX output (inline expansion) |
| YAML comments | Dropped |
| YAML multi-document (`---`) | CX multi-document stream |

**Note:** YAML anchors and aliases are resolved (expanded) during parsing. The
resulting CX does not contain CX anchors, merges, or aliases. A YAML → CX → YAML
round-trip recovers the data but not the YAML anchor/alias structure.

---

### 5.2 — YAML → XML, JSON, TOML, Markdown

**Functions:** `cx_yaml_to_xml`, `cx_yaml_to_json`, `cx_yaml_to_toml`, `cx_yaml_to_md`

All apply §5.1 (YAML → CX) then the appropriate CX → target conversion.

---

## 6 — TOML as input

### 6.1 — TOML → CX

**Function:** `cx_toml_to_cx`

TOML → CX maps TOML tables to CX elements and TOML key-value pairs to CX attrs
and child elements.

**Conversion rules:**

| TOML construct | CX output |
|----------------|-----------|
| Top-level key = scalar | Child element of document root |
| `[table]` | CX Element |
| `[[array of tables]]` | Repeated same-named CX Elements |
| TOML integer | ScalarNode with `int` type |
| TOML float | ScalarNode with `float` type |
| TOML boolean | ScalarNode with `bool` type |
| TOML string | TextNode or ScalarNode |
| TOML datetime | ScalarNode with `datetime` type |
| TOML date | ScalarNode with `date` type |
| TOML inline array | Element with `:type[]` annotation when homogeneous |
| TOML inline table | Nested Element |
| TOML comments | Dropped |

---

### 6.2 — TOML → XML, JSON, YAML, Markdown

**Functions:** `cx_toml_to_xml`, `cx_toml_to_json`, `cx_toml_to_yaml`, `cx_toml_to_md`

All apply §6.1 (TOML → CX) then the appropriate CX → target conversion.

---

## 7 — Markdown as input

### 7.1 — Markdown → CX

**Function:** `cx_md_to_cx`

Markdown → CX maps Markdown block and inline constructs to CX elements.

**Conversion rules:**

| Markdown construct | CX output |
|-------------------|-----------|
| `# Heading` | `[h1 Heading]` |
| `## Heading` | `[h2 Heading]` |
| `### Heading` to `######` | `[h3]` … `[h6]` |
| Paragraph | `[p text]` |
| `- item` or `* item` | `[ul [li item]]` |
| `1. item` | `[ol [li item]]` |
| `> quote` | `[blockquote text]` |
| ` ```lang\ncode\n``` ` | `[pre [code text]]` (with optional `lang` attr) |
| `` `inline code` `` | `[code text]` |
| `**bold**` or `__bold__` | `[strong text]` |
| `*italic*` or `_italic_` | `[em text]` |
| `[text](url)` | `[a href=url text]` |
| `![alt](src)` | `[img src=src alt=alt]` |
| `---` or `***` | `[hr]` |
| HTML inline tags | Passed through as-is (not parsed) |
| YAML frontmatter (`---...\n---`) | `[-meta ...]` element with YAML keys as attrs |

**Multi-document:** Markdown documents separated by `---` on its own line produce
a CX multi-document stream.

**What is lost:**

- Markdown table structure (not yet supported; tables become text)
- Inline HTML (passed through as text, not parsed into CX elements)
- Markdown-specific formatting details (exact blank line counts, list nesting
  beyond two levels)

---

### 7.2 — Markdown → XML, JSON, YAML, TOML

**Functions:** `cx_md_to_xml`, `cx_md_to_json`, `cx_md_to_yaml`, `cx_md_to_toml`

All apply §7.1 (Markdown → CX) then the appropriate CX → target conversion.

---

## 8 — Lossiness summary

| From \ To | CX         | XML          | JSON         | YAML         | TOML         | MD           |
|-----------|------------|--------------|--------------|--------------|--------------|--------------|
| **CX**    | lossless   | lossless†    | lossy        | lossy        | lossy        | lossy        |
| **XML**   | lossless   | lossless     | lossy        | lossy        | lossy        | lossy        |
| **JSON**  | adds struct| adds struct  | lossless‡    | lossless‡    | lossless‡    | lossy        |
| **YAML**  | lossy*     | lossy*       | lossless‡    | lossless‡    | lossless‡    | lossy        |
| **TOML**  | lossless** | lossless**   | lossless‡    | lossless‡    | lossless‡    | lossy        |
| **MD**    | lossy      | lossy        | lossy        | lossy        | lossy        | lossless     |

† cx→xml is lossless when consumers preserve the `cx:` namespace attributes.
  Consumers that strip `cx:` attributes lose CX-specific metadata.

‡ lossless within the expressive range of that format.

\* YAML anchors and aliases are resolved (expanded) on parse; not reconstructed
  in CX output. Data content is preserved.

** TOML has no mixed content or comments, so the CX output contains only what
   TOML can express; no loss within TOML's range.
