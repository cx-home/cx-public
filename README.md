# CX

Because some things just need to be done. CX is a bracket-based document and configuration format that unifies markup and
structured data in one coherent syntax. It reads like XML, types like YAML, and
converts losslessly to and from JSON, YAML, TOML, XML, and Markdown. Multiple AI's were used but unharmed in this project including (in alpha order): ChatGPT, Claude, Grok.

```cx
[article lang=en
  [-author note: written 2026-04-19]
  [head
    [title Getting Started with CX]
    [tags :string[] tutorial beginner]
  ]
  [body
    [h1 What is CX?]
    [p CX is [em compact] and [strong human-friendly].]
    [pre [# [server [host localhost] [port :int 8080]] #]]
  ]
]
```

---

## Contents

- [Install](#install)
- [CLI](#cli)
- [Syntax](#syntax)
  - [Elements](#elements)
  - [Attributes](#attributes)
  - [Text and quoting](#text-and-quoting)
  - [Triple-quoted strings](#triple-quoted-strings)
  - [Comments](#comments)
  - [Scalars and auto-typing](#scalars-and-auto-typing)
  - [Explicit type annotations](#explicit-type-annotations)
  - [Short type aliases](#short-type-aliases)
  - [Typed arrays](#typed-arrays)
  - [Auto-array](#auto-array)
  - [Inferred-type array `:[]`](#inferred-type-array-)
  - [Mixed content](#mixed-content)
  - [Raw text blocks](#raw-text-blocks)
  - [Block content](#block-content)
  - [Entity and character references](#entity-and-character-references)
  - [Anchors, merges, and aliases](#anchors-merges-and-aliases)
  - [Processing instructions](#processing-instructions)
  - [Multi-document streams](#multi-document-streams)
- [Corner cases](#corner-cases)
- [Format conversion](#format-conversion)
- [Language bindings](#language-bindings)
- [Building from source](#building-from-source)

---

## Install

**Prerequisites:** [V](https://vlang.io) 0.5.1+. No other dependencies.

```sh
git clone https://github.com/ardec/cx
cd cx
make build
```

This builds the `cx` CLI binary at `vcx/target/cx` and the shared library
`vcx/target/libcx.dylib` / `vcx/target/libcx.so`.

Add the binary to your PATH:

```sh
export PATH="$PATH:$(pwd)/vcx/target"
```

---

## CLI

```
cx [--from cx|xml|json|yaml|toml|md] [--cx|--xml|--ast|--json|--yaml|--toml|--md] [file]
```

Input format is auto-detected from the file extension (`.cx`, `.xml`, `.json`,
`.yaml`, `.yml`, `.toml`) or overridden with `--from`. Default output is `--cx`.

```sh
cx file.cx                    # CX → CX  (canonical round-trip)
cx --json file.cx             # CX → semantic JSON
cx --yaml file.cx             # CX → YAML
cx --toml file.cx             # CX → TOML
cx --xml  file.cx             # CX → XML
cx --ast  file.cx             # CX → full AST as JSON (for tooling)

cx --from xml  file.xml       # XML  → CX
cx --from json file.json      # JSON → CX
cx --from yaml file.yaml      # YAML → CX
cx --from toml file.toml      # TOML → CX
cx --from md   file.md        # MD   → CX

cx --md file.cx               # CX   → Markdown

cat file.cx | cx --json       # read from stdin
```

---

## Syntax

Every construct in CX is a bracket pair `[...]`. There are no closing tags to
repeat, no mandatory quoting, and no indentation rules.

### Elements

```cx
[br]                          # empty element
[p Hello]                     # element with text
[p Hello World]               # multi-word text (whitespace normalized)
[div
  [p First]
  [p Second]
]                             # nested elements
```

XML equivalent:
```xml
<br/>
<p>Hello</p>
<p>Hello World</p>
<div>
  <p>First</p>
  <p>Second</p>
</div>
```

A document can have **multiple root elements** — no wrapper element required:

```cx
[title Hello]
[body
  [p World]
]
```

### Attributes

Attributes use `name=value` with no surrounding quotes needed for most values.
`[`, `]`, `=`, `'`, `"`, and whitespace terminate an unquoted value.

```cx
[input type=text name=q placeholder='Search...']
[a href=https://example.com/path?id=1 Visit us]
[img src=/images/logo.png alt='Company logo' width=120 height=40]
```

XML equivalent:
```xml
<input type="text" name="q" placeholder="Search..."/>
<a href="https://example.com/path?id=1">Visit us</a>
<img src="/images/logo.png" alt="Company logo" width="120" height="40"/>
```

> **Note:** URL characters including `/`, `?`, `#`, `@`, `:`, `+`, and `&` are
> all valid in unquoted attribute values. `href=https://example.com/a?b=1&c=2`
> works without quotes.

> **Note:** Bare attribute values are **auto-typed** the same way as bare element
> body tokens: `port=8080` stores int `8080`, `debug=false` stores bool `false`.
> Quoted attribute values (`port='8080'`) are always strings — use quotes to prevent
> auto-typing when a numeric-looking string is intended.

### Text and quoting

Unquoted text is whitespace-normalized: consecutive spaces and newlines collapse
to a single space. Use single quotes to preserve whitespace exactly:

```cx
[p   extra   spaces   ]       # stored as "extra spaces" (normalized)
[pre '  indented  ']          # stored as "  indented  " (preserved)
[p 'first line\nsecond line'] # \n escape inside quotes
```

Quotes are required when a value would otherwise be auto-typed (see below):

```cx
[status 'true']               # string "true",  not bool true
[version '3.0']               # string "3.0",   not float 3.0
[zip :string 90210]           # explicit :string type annotation also works
```

### Triple-quoted strings

`'''...'''` is the multiline string literal. Whitespace stripping (in order):
1. One leading newline after `'''` is stripped.
2. One trailing newline before `'''` is stripped.
3. Common leading indent of all non-blank lines is stripped.

```cx
[readme '''
  CX is a bracket-based format.
  It converts to XML, JSON, YAML, and TOML.
''']
```

Stored as `Text("CX is a bracket-based format.\nIt converts to XML, JSON, YAML, and TOML.")`.

Triple-quoted strings always produce a `Text` node — no auto-typing, no child element parsing.
Single and double quotes are allowed unescaped inside; `\'` prevents early termination.
Triple-quoted strings are **not** valid in attribute position — use single-quoted strings there.

The CX emitter round-trips multiline text as single-quoted strings with literal `\n`:
```cx
[readme 'CX is a bracket-based format.\nIt converts to XML, JSON, YAML, and TOML.']
```

### Comments

Comments use the `[-` opener:

```cx
[-this is a comment]

[config
  [-database settings]
  [host localhost]
  [port :int 5432]
]
```

XML equivalent: `<!--this is a comment-->` / `<!--database settings-->`

Comments are preserved in the AST and round-trip through all formats. JSON
(which has no comment syntax) discards them during conversion.

### Scalars and auto-typing

When an element body is a **single unquoted token** with **no child elements**,
the value is auto-typed:

| Pattern | Type | Example |
|---|---|---|
| Digits only | `int` | `[age 30]` |
| `0x` prefix | `int` (hex) | `[flags 0xFF]` → 255 |
| Digits with `.` or `e` | `float` | `[price 3.14]`, `[scale 1e-3]` |
| `true` or `false` | `bool` | `[debug true]` |
| `null` | `null` | `[value null]` |
| `YYYY-MM-DD` | `date` | `[born 2026-04-19]` |
| ISO 8601 datetime | `datetime` | `[created 2026-04-19T14:30:00Z]` |
| Anything else | `Text` | `[name Alice]`, `[msg hello world]` |

```cx
[server
  [host localhost]              # Text "localhost"
  [port 8080]                   # int 8080
  [ratio 0.75]                  # float 0.75
  [debug false]                 # bool false
  [secret null]                 # null
  [launched 2026-04-19]        # date
  [updated 2026-04-19T09:00:00Z] # datetime
]
```

Auto-typing fires **only** on a single bare token. Multiple tokens or any child
element suppress it:

```cx
[p Version 3.0]               # Text "Version 3.0" — two tokens, no typing
[p 3.0]                       # float 3.0 — single token
[root 42 [x]]                 # Text "42 " — has a child element, no typing
```

### Explicit type annotations

Use `:type` after the element name to override auto-typing or force a specific
type. This is the `ElementMeta` position — before any attributes or body:

```cx
[port :int 8080]              # explicitly int (same as auto here)
[zip :string 90210]           # force string — without :string this would be int
[ratio :float 1]              # force float — without :float this would be int
[payload :bytes SGVsbG8=]     # base64-encoded bytes
[count :int -1]               # negative int
```

In XML output, explicit annotations appear as `cx:type`:

```xml
<port cx:type="int">8080</port>
<zip cx:type="string">90210</zip>
```

### Short type aliases

Each long type name has a one- or two-character alias accepted everywhere
`:type` is valid. Emitters always produce long forms; parsers accept both:

| Short | Long | Example |
|---|---|---|
| `:i` | `:int` | `[count :i 42]` |
| `:f` | `:float` | `[ratio :f 3.14]` |
| `:b` | `:bool` | `[active :b true]` |
| `:s` | `:string` | `[label :s 90210]` |
| `:d` | `:date` | `[launch :d 2026-04-19]` |
| `:dt` | `:datetime` | `[stamp :dt 2026-04-19T09:00:00Z]` |

`null` and `bytes` have no short alias — use their long forms only.

Short aliases also work on arrays: `:i[]`, `:f[]`, `:b[]`, `:s[]`, `:d[]`, `:dt[]`.

### Typed arrays

`:type[]` turns the element body into a sequence of items of that type:

```cx
[tags :string[] admin user guest]
[scores :int[] 10 20 30]
[primes :int[] 2 3 5 7 11]
[origins :string[] https://example.com https://app.example.com]
```

In JSON / YAML / TOML output:

```json
{"tags": ["admin", "user", "guest"], "scores": [10, 20, 30]}
```

In XML output, each item becomes an `<item>` element:

```xml
<tags cx:type="string[]"><item>admin</item><item>user</item><item>guest</item></tags>
```

### Auto-array

When an element body has **2 or more** whitespace-separated unquoted tokens and
**no child elements**, and all tokens resolve to the **same non-string type**, the
body becomes a typed array automatically — no annotation needed:

```cx
[scores 10 20 30]             # → int[]   (all integers)
[temps  -2.5 0.0 3.7 21.1]   # → float[] (all floats)
[flags  true false true]      # → bool[]
[dates  2024-01-15 2025-03-01 2026-04-19]  # → date[]
```

Mixed int and float tokens promote to `float[]`:
```cx
[data 1 2.5 3]                # → float[] (1 and 3 promoted from int)
```

Any token that falls through to `Text`, or any quoted string token, suppresses
auto-array — the body stays as `Text`:
```cx
[p Version 3.0]               # Text "Version 3.0" — "Version" is not a number
[p 10 'twenty' 30]            # Text — quoted string suppresses auto-array
```

The CX emitter adds the explicit annotation on round-trip:
```cx
[scores :int[] 10 20 30]      # canonical output from [scores 10 20 30]
```

String arrays always require an explicit annotation (`:[]`, `:s[]`, or `:string[]`).

### Inferred-type array `:[]`

`:[]` without a type name infers the array element type from the tokens:

- Non-string auto-typed tokens → that type (with int+float promotion to `float[]`)
- Any quoted string or any token falling through to `Text` → `string[]`

```cx
[data  :[] 1 2.5 3]           # → float[]  (all numeric, int promoted)
[tags  :[] admin user guest]  # → string[] (bare words fall through to text)
[mixed :[] 10 hello 30]       # → string[] (hello falls through to text)
```

`:[]` is the minimal annotation to force a string array from bare tokens:
```cx
[tags :[] admin user guest]   # string[] — each bare word becomes a string item
```

### Block content

`[|...|]` is a parsed block literal that preserves newlines. Content is parsed as
normal CX — elements, entity refs, and all body items work inside:

```cx
[p [|
  Visit our [a href=https://example.com site] or
  read the [a href=https://docs.example.com docs].
|]]
```

Whitespace stripping (same rules as triple-quoted strings):
1. One leading newline after `[|` is stripped.
2. One trailing newline before `|]` is stripped.
3. Common leading indent of all non-blank lines is stripped.

In round-trip XML: `<cx:block>...</cx:block>`.
In semantic XML and JSON/YAML/TOML: items inlined into the parent.

### Mixed content

Text and child elements can be freely interleaved — like HTML prose:

```cx
[p
  For help, visit our [a href=https://example.com/faq FAQ page]
  or [a href=mailto:support@example.com contact us].
]

[p The result is [code x + y] where [em x] and [em y] are integers.]
```

XML equivalent:
```xml
<p>
  For help, visit our <a href="https://example.com/faq">FAQ page</a>
  or <a href="mailto:support@example.com">contact us</a>.
</p>
```

In the AST, each text run and element is a separate node. Auto-typing is
**suppressed** in mixed-content bodies — all bare tokens are `Text`, never
`Scalar`, regardless of their value:

```cx
[p The answer is 42 and it is true]
#                  ^^ Text, not int
#                           ^^^^ Text, not bool
```

### Raw text blocks

`[# ... #]` contains raw text where brackets are not parsed — equivalent to
XML CDATA sections:

```cx
[script [# if (x < y) { return [1, 2]; } #]]
[css    [# .nav > a[href^="https"] { color: blue; } #]]
[pre    [# [server [host localhost]] #]]
```

XML equivalent:
```xml
<script><![CDATA[ if (x < y) { return [1, 2]; } ]]></script>
```

The terminator is `#]`. A bare `]` is allowed inside raw text. To embed a
literal `#]` you must split it across two adjacent raw blocks.

### Entity and character references

Standard XML entity references require a semicolon:

```cx
[p Copyright &copy; 2026 &mdash; all rights reserved.]
[p Use &amp; for ampersands and &lt; for less-than signs.]
[p Predefined: &amp; &lt; &gt; &apos; &quot;]
```

The five predefined XML entities (`amp`, `lt`, `gt`, `apos`, `quot`) are
resolved to their characters in the semantic JSON output. Others (like `&copy;`,
`&mdash;`) are preserved as `EntityRef` nodes and passed through.

Character references are always resolved to Unicode:

```cx
[p &#169; 2026]               # © 2026
[p &#x1F600;]                 # 😀
[p &#8212; em dash]           # — em dash
```

> **Anchor vs EntityRef disambiguation:** `&name` without a semicolon is an
> _anchor definition_ (Extended). `&name;` with a semicolon is an _entity
> reference_ (Core). The parser uses semicolon lookahead to disambiguate.

### Anchors, merges, and aliases

Anchors name an element for later reuse. Merges inherit another element's
attributes. Useful for DRY configuration:

```cx
[-define shared defaults with &anchor]
[defaults &base timeout=30 retries=3 log_level=info ssl=false]

[-each environment merges base and overrides only what changes]
[dev     *base host=localhost         port=8080 debug=true]
[staging *base host=staging.acme.com  port=443  ssl=true]
[prod    *base host=acme.com          port=443  ssl=true  retries=5]
```

An **alias element** `[*name]` is a full stand-in for the anchored element:

```cx
[defaults &def timeout=30 retries=3]
[service1 *def host=svc1.internal]
[*def]                        # alias — expands to the full defaults element
```

Canonical meta order is: anchor `&` → merge `*` → type `:` → attributes.
Parsers accept any order; emitters produce canonical order.

In XML output:
```xml
<defaults cx:anchor="base" timeout="30" retries="3" log_level="info" ssl="false"/>
<dev cx:merge="base" host="localhost" port="8080" debug="true"/>
```

### Processing instructions

```cx
[?xml version=1.0 encoding=UTF-8]    # XML declaration (must be first)
[?cx include=base.cx]                 # CX directive
[?php echo $greeting; ]              # arbitrary PI
```

XML equivalent: `<?xml version="1.0" encoding="UTF-8"?>` / `<?php echo $greeting; ?>`

`[?xml ...]` and `[?cx ...]` are structured (parsed as key=value pairs).
All other `[?target data]` PIs store their data as a raw string.

### Multi-document streams

Separate documents with `---` on its own line:

```cx
[config
  [env production]
  [port :int 443]
]
---
[secrets
  [db_password :string 's3cr3t']
  [api_key :string abc123]
]
```

The CLI and all language bindings return a `Multi` result for multi-doc files.
YAML is the other common format that supports multi-document streams.

---

## Corner cases

### Auto-typing is single-token only

```cx
[n 42]                        # int 42
[n 42.0]                      # float 42.0
[n 42 items]                  # Text "42 items" — two tokens
[n -1]                        # int -1  (minus sign attached to digit)
[n - 1]                       # Text "- 1" — space separates minus from digit
```

### Quoting to prevent auto-typing

```cx
[active true]                 # bool true
[active 'true']               # Text "true" — quoted suppresses auto-typing
[version 3.0]                 # float 3.0
[version '3.0']               # Text "3.0"
[port 8080]                   # int 8080
[port :string 8080]           # Text "8080" — explicit :string annotation
```

### Attribute auto-typing

Bare attribute values are auto-typed the same way as bare body tokens:

```cx
[server host=localhost port=8080 debug=false]
# host → string "localhost"  (no pattern match)
# port → int 8080
# debug → bool false
```

Quote an attribute value to force it to be a string:
```cx
[server port='8080']          # string "8080", not int 8080
```

Array auto-typing does **not** apply to attributes — only scalar auto-typing does.
Use child elements for array-typed values.

### Whitespace normalization

Unquoted body text collapses whitespace. Quoted text preserves it:

```cx
[p hello    world]            # stored as "hello world" (one space)
[p 'hello    world']          # stored as "hello    world" (preserved)
[p
  first line
  second line
]                             # stored as "first line second line"
```

### Whitespace in mixed content needs quoting

When text adjacent to child elements has significant leading or trailing spaces,
quote it:

```cx
[p [b bold] text after]       # "text after" — no leading space captured
[p [b bold] ' text after']    # " text after" — leading space preserved
[p 'before ' [b bold] after]  # "before " then bold then "after"
```

The CX emitter automatically adds quotes when a text run would lose whitespace
on round-trip.

### Mixed content suppresses scalar auto-typing

Any child element in the body suppresses auto-typing for all bare tokens:

```cx
[root 42 [x]]                 # "42 " is Text, not int — child element present
[root 42]                     # int 42 — no child elements
[root :int 42 [x]]            # explicit annotation still forces int scalar
```

### Hex integer normalization

Hex literals are stored as their decimal integer value:

```cx
[mask 0xFF]                   # stored as int 255
[offset 0x1A3F]               # stored as int 6719
```

Round-tripping through CX emits decimal: `[mask 255]`.

### `&` disambiguation: anchor vs entity ref

Inside element meta position (no semicolon) → anchor definition:
```cx
[node &myanchor attr=val]     # defines anchor named "myanchor"
```

Inside body or attribute (with semicolon) → entity reference:
```cx
[p Tom &amp; Jerry]           # EntityRef "amp"
[p &copy; 2026]               # EntityRef "copy"
```

### Raw text terminator

`#]` terminates a raw text block. A single `]` is safe inside:

```cx
[p [# arrays use ] notation #]]   # OK — bare ] is fine
[p [# end: #]]                    # OK — terminates at #]
```

To include a literal `#]` sequence, split into two adjacent raw blocks:
```cx
[p [# first part: #][# ] rest #]]  # produces: first part: #] rest
```

### Multi-document `---` separator

`---` must not appear as content inside an element — it is only meaningful at
the top level between documents. Inside a body it is text:

```cx
[p ---]                       # Text "---" inside an element, not a separator
---
[next-doc]                    # this IS a separator — top-level between docs
```

### Entity refs need whitespace separation in body text

An `&name;` sequence is only parsed as an entity reference when separated from
surrounding text by whitespace. Without whitespace it is treated as plain text:

```cx
[p Tom &amp; Jerry]          # EntityRef "amp" — spaces around &amp;
[p a&amp;b]                  # Text "a&amp;b"  — no spaces, treated as bare text
```

This means URLs containing `&` work unquoted in both attribute and body
positions — no quoting needed:

```cx
[a href=https://example.com/search?q=hello&lang=en Click]   # attribute — fine
[p Visit https://example.com/search?q=hello&lang=en today.] # body — also fine
```

The `&lang=en` segment is never mistaken for an entity ref because there is no
whitespace before `&`.

---

## Format conversion

CX converts losslessly between CX, XML, JSON, YAML, TOML, and Markdown.

### All six formats from one source

```sh
cx --cx   examples/config.cx   # canonical CX
cx --xml  examples/config.cx   # XML with cx: namespace for type metadata
cx --json examples/config.cx   # semantic JSON (collapsed data values)
cx --yaml examples/config.cx   # YAML
cx --toml examples/config.cx   # TOML
cx --md   examples/doc.cx      # Markdown
```

### Reading any format as CX

```sh
cx --from xml  examples/books.xml
cx --from json examples/config.json
cx --from yaml examples/config.yaml
cx --from toml examples/config.toml
cx --from md   examples/doc.md
```

### Markdown format

CX supports Markdown as a 6th first-class format. CX bracket syntax maps to
standard Markdown shorthand, which in turn normalizes to canonical element names
in the AST:

| MD shorthand | CX bracket syntax | HTML long name | Markdown output |
|---|---|---|---|
| `# text` | `[# text]` or `[h1 text]` | `h1` | `# text` |
| `## text` | `[## text]` or `[h2 text]` | `h2` | `## text` |
| `**text**` | `[** text]` or `[strong text]` or `[b text]` | `strong` | `**text**` |
| `*text*` | `[* text]` or `[em text]` or `[i text]` | `em` | `*text*` |
| `~~text~~` | `[~~ text]` or `[del text]` or `[s text]` | `del` | `~~text~~` |
| `~text~` | `[~ text]` | `sub` | `~text~` |
| `^text^` | `[^ text]` | `sup` | `^text^` |
| `<u>text</u>` | `[__ text]` | `u` | `<u>text</u>` |
| `` `text` `` | `` [` text] `` or `[code text]` or `[c text]` | `code` | `` `text` `` |
| `` ```lang\n...\n``` `` | `` [``` lang:bash \| ... \|] `` | `code` (block) | fenced code block |
| `> text` | `[> text]` or `[blockquote text]` | `blockquote` | `> text` |
| `---` | `[---]` | `hr` | `---` |
| `[text](url)` | `[a href:"url" text]` | `a` | `[text](url)` |
| `![alt](src)` | `[img src:"s" alt:"a"]` | `img` | `![a](s)` |

**Auto-wrap**: bare `TextNode` at block level auto-wraps to `<p>` on MD output.

**YAML frontmatter**: `[doc title:"..." author:"..."]` emits YAML frontmatter.

**Tables**: `[table | pipe rows |]` stores raw GFM pipe table text; emitters pass
it through for MD, and parse rows into `tr/th/td` for XML/JSON.

**Unknown elements**: elements not in the vocabulary above render as
`<!-- [element_name attr:val body] -->` in MD output, and are round-tripped back
on MD input.

Example document in CX MD dialect:

```cx
[doc title:"Guide"
  [# CX Language Guide]
  [p CX is a [** structured] language with [* clean] syntax.]
  [## Lists]
  [ul
    [li Item one]
    [li Item two]
  ]
  [a href:"https://example.com" Learn more]
]
```

Produces Markdown:

```markdown
---
title: Guide
---

# CX Language Guide

CX is a **structured** language with *clean* syntax.

## Lists

- Item one
- Item two

[Learn more](https://example.com)
```

### JSON output — semantic vs AST

`--json` emits **semantic JSON**: collapsed data values as plain JSON, useful
for data pipelines.

`--ast` emits the **full AST** as JSON: every node type, attribute, and scalar
preserved, useful for tooling and debugging.

```sh
cx --json examples/config.cx   # {"server": {"host": "localhost", "port": 8080, ...}}
cx --ast  examples/config.cx   # {"type":"Document","elements":[{"type":"Element",...}]}
```

### Semantic JSON rules

| CX construct | JSON output |
|---|---|
| `[port :int 8080]` | `"port": 8080` (native int) |
| `[debug false]` | `"debug": false` (native bool) |
| `[name Alice]` | `"name": "Alice"` (string) |
| `[value null]` | `"value": null` |
| `[tags :string[] a b c]` | `"tags": ["a", "b", "c"]` |
| `[book ...]` repeated | `"book": [{...}, {...}]` (auto-array) |
| `[p text [em bold] more]` | `"p": {"_": "text  more", "em": "bold"}` |
| `[-comment]` | _(discarded)_ |

Repeated elements with the same name automatically collect into a JSON array:

```cx
[library
  [book [title Dune] [year :int 1965]]
  [book [title Neuromancer] [year :int 1984]]
]
```
```json
{"library": {"book": [{"title": "Dune", "year": 1965}, {"title": "Neuromancer", "year": 1984}]}}
```

### XML round-trip

CX uses the `cx:` namespace to preserve CX-specific metadata in XML output:

```xml
<!-- cx:type preserves scalar type annotations -->
<port cx:type="int">8080</port>
<tags cx:type="string[]"><item>admin</item><item>user</item></tags>

<!-- cx:anchor and cx:merge preserve anchor/merge relationships -->
<defaults cx:anchor="base" timeout="30" retries="3"/>
<dev cx:merge="base" host="localhost" port="8080"/>
```

---

## Language bindings

All language bindings wrap the same V implementation (`vcx/`) via the C ABI
(`libcx.dylib` / `libcx.so`). Every binding exposes:

- **Conversion API** — 6 input formats × 7 output formats (CX, XML, JSON, YAML, TOML, MD, AST), plus `to_cx_compact` and `ast_to_cx`
- **Document API** — `parse`, `at`, `find_all`, `select` / `select_all` (CXPath), `transform` / `transform_all` (immutable update), streaming, `loads` / `dumps`

All 10 languages have full feature parity. See each language's `README.md` for the complete API reference.

### Python

**Requires:** `libcx` built (`make build`). No pip packages needed.

```python
import sys; sys.path.insert(0, 'lang/python')
import cxlib

# Conversion API
result = cxlib.to_json('[server [host localhost] [port :int 8080]]')
# {"server": {"host": "localhost", "port": 8080}}

# Document API — parse, navigate, query, transform
doc = cxlib.parse('[config [server host=localhost port=8080] [db host=db.local]]')

print(doc.at('config/server').attr('host'))   # localhost

# CXPath select
for svc in doc.select_all('//server[@port>=8080]'):
    print(svc.attr('host'))   # localhost

# Immutable transform — returns a new document, original unchanged
updated = doc.transform('config/server',
    lambda el: (el.set_attr('host', 'prod.example.com') or el))
print(updated.at('config/server').attr('host'))  # prod.example.com
print(doc.at('config/server').attr('host'))       # localhost
```

Errors raise `RuntimeError`. See `lang/python/cxlib/README.md` for the full API reference.

Run the full example:
```sh
python lang/python/examples/transform.py
```

Run conformance:
```sh
python lang/python/conformance.py
```

### V

V is the native implementation language — the `vcx/` core is written in V and
compiled to `libcx`. The V binding therefore exposes the full Document API in
addition to the conversion API shared by all other bindings.

**Requires:** V 0.5+, `libcx` built (`make build`).

```v
import cxlib

fn main() {
    // Conversion API (shared by all bindings)
    result := cxlib.to_json('[server [host localhost] [port :int 8080]]') or { panic(err) }
    println(result)
    // {"server": {"host": "localhost", "port": 8080}}

    // Document API — parse, navigate, transform
    doc := cxlib.parse('[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]') or { panic(err) }

    host := (doc.at('config/server') or { panic('') }).attr('host') or { panic('') }
    println(host.str())  // localhost

    // Immutable update — returns a new document, original unchanged
    updated := doc.transform('config/server', fn (el cxlib.Element) cxlib.Element {
        mut e := el
        e.set_attr('host', cxlib.ScalarVal('prod.example.com'))
        return e
    })
    println((updated.at('config/server') or { panic('') }).attr('host') or { panic('') }.str())
    // prod.example.com

    // CXPath select
    for svc in doc.select_all('//server[@port>=8080]') {
        println(svc.attr('host') or { '' }.str())
    }
}
```

Conversion functions return `!string`; `version()` returns a plain `string`.
See `lang/v/README.md` for the full Document and CXPath API reference.

Run the examples:
```sh
v run lang/v/examples/demo.v
v run lang/v/examples/transform.v
```

### Rust

**Requires:** `libcx` built (`make build`). No crates.io dependencies.

```rust
use cxlib::ast::{parse, Value};

// Conversion API
let result = cxlib::to_json("[server [host localhost] [port :int 8080]]").unwrap();
// {"server": {"host": "localhost", "port": 8080}}

// Document API
let doc = parse("[config [server host=localhost port=8080]]").unwrap();
println!("{:?}", doc.at("config/server").unwrap().attr("host"));  // Some("localhost")

// CXPath select
let svcs = doc.select_all("//server[@port>=8080]").unwrap();
println!("{:?}", svcs[0].attr("host"));   // Some("localhost")

// Immutable transform
let updated = doc.transform("config/server", |mut el| {
    el.set_attr("host", Value::String("prod.example.com".into()), None);
    el
});
```

Errors return `Err(String)`. See `lang/rust/cxlib/README.md` for the full API reference.

Add to `Cargo.toml`:
```toml
[dependencies]
cxlib = { path = "lang/rust/cxlib" }
```

Run the full example:
```sh
cargo run --manifest-path lang/rust/cxlib/Cargo.toml --example transform
```

Run conformance:
```sh
make test-rust
```

### Ruby

**Requires:** `libcx` built (`make build`), Ruby 3+ with `ffi` gem (`gem install ffi`).

```ruby
require_relative 'lang/ruby/cxlib/lib/cxlib'

# Conversion API
result = CXLib.to_json('[server [host localhost] [port :int 8080]]')
# {"server": {"host": "localhost", "port": 8080}}

# Document API
doc = CXLib.parse('[config [server host=localhost port=8080]]')
puts doc.at('config/server').attr('host')   # localhost

# CXPath select
doc.select_all('//server[@port>=8080]').each { |el| puts el.attr('host') }

# Immutable transform
updated = doc.transform('config/server') { |el| el.set_attr('host', 'prod.example.com'); el }
puts updated.at('config/server').attr('host')  # prod.example.com
puts doc.at('config/server').attr('host')       # localhost
```

Errors raise `RuntimeError`. See `lang/ruby/cxlib/README.md` for the full API reference.

Run the full example:
```sh
/opt/homebrew/opt/ruby/bin/ruby lang/ruby/cxlib/examples/transform.rb
```

Run conformance:
```sh
make test-ruby
```

### Go

**Requires:** `libcx` built (`make build`), Go 1.21+, CGo toolchain.

```go
import cxlib "github.com/ardec/cx/lang/go"

// Conversion API
result, _ := cxlib.ToJson("[server [host localhost] [port :int 8080]]")
// {"server": {"host": "localhost", "port": 8080}}

// Document API
doc, _ := cxlib.Parse("[config [server host=localhost port=8080]]")
srv := doc.At("config/server")
fmt.Println(srv.Attr("host"))   // localhost

// CXPath select
svcs, _ := doc.SelectAll("//server[@port>=8080]")
fmt.Println(svcs[0].Attr("host"))   // localhost

// Immutable transform
updated := doc.Transform("config/server", func(el *cxlib.Element) *cxlib.Element {
    el.SetAttr("host", "prod.example.com", "")
    return el
})
fmt.Println(updated.At("config/server").Attr("host"))  // prod.example.com
fmt.Println(doc.At("config/server").Attr("host"))       // localhost
```

Errors return non-nil `error`. See `lang/go/cxlib/README.md` for the full API reference.

Run the full example:
```sh
cd lang/go/cxlib && go run ./examples/transform/
```

Run conformance:
```sh
make test-go
```

### TypeScript

**Requires:** `libcx` built (`make build`), Node.js 18+, `koffi` npm package.

```typescript
import * as cx from './lang/typescript/cxlib/src/index';
import { parse } from './lang/typescript/cxlib/src/ast';

// Conversion API
const result = cx.toJson('[server [host localhost] [port :int 8080]]');
// {"server": {"host": "localhost", "port": 8080}}

// Document API
const doc = parse('[config [server host=localhost port=8080]]');
console.log(doc.at('config/server')!.attr('host'));   // localhost

// CXPath select
const svcs = doc.selectAll('//server[@port>=8080]');
console.log(svcs[0].attr('host'));   // localhost

// Immutable transform
const updated = doc.transform('config/server', el => {
    el.setAttr('host', 'prod.example.com');
    return el;
});
console.log(updated.at('config/server')!.attr('host'));  // prod.example.com
console.log(doc.at('config/server')!.attr('host'));       // localhost
```

Errors throw `Error`. See `lang/typescript/cxlib/README.md` for the full API reference.

Run the full example:
```sh
cd lang/typescript/cxlib && npm run example
```

Run conformance:
```sh
make test-typescript
```

### Java

**Requires:** `libcx` built (`make build`), Java 21+, Maven, JNA 5.14.0 (fetched by Maven).

```java
import cx.CXDocument;

// Conversion API
String result = cx.CxLib.toJson("[server [host localhost] [port :int 8080]]");
// {"server": {"host": "localhost", "port": 8080}}

// Document API
CXDocument doc = CXDocument.parse("[config [server host=localhost port=8080]]");
System.out.println(doc.at("config/server").attr("host"));   // localhost

// CXPath select
doc.selectAll("//server[@port>=8080]").forEach(el -> System.out.println(el.attr("host")));

// Immutable transform
CXDocument updated = doc.transform("config/server", el -> {
    el.setAttr("host", "prod.example.com", null);
    return el;
});
System.out.println(updated.at("config/server").attr("host"));  // prod.example.com
System.out.println(doc.at("config/server").attr("host"));       // localhost
```

Errors throw `RuntimeException`. See `lang/java/cxlib/README.md` for the full API reference.

Run the full example:
```sh
mvn -f lang/java/cxlib/pom.xml exec:java -Dexec.mainClass=cx.examples.Transform
```

Run conformance:
```sh
make test-java
```

### Kotlin

**Requires:** `libcx` built (`make build`), Java 21 (arm64), Gradle, JNA 5.14.0.

```kotlin
import cx.CXDocument

// Conversion API
val result = cx.CxLib.toJson("[server [host localhost] [port :int 8080]]")
// {"server": {"host": "localhost", "port": 8080}}

// Document API
val doc = CXDocument.parse("[config [server host=localhost port=8080]]")
println(doc.at("config/server")?.attr("host"))   // localhost

// CXPath select
doc.selectAll("//server[@port>=8080]").forEach { println(it.attr("host")) }

// Immutable transform
val updated = doc.transform("config/server") { el ->
    el.setAttr("host", "prod.example.com")
    el
}
println(updated.at("config/server")?.attr("host"))  // prod.example.com
println(doc.at("config/server")?.attr("host"))       // localhost
```

Errors throw `RuntimeException`. See `lang/kotlin/cxlib/README.md` for the full API reference.

Run the full example:
```sh
cd lang/kotlin/cxlib && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home gradle run
```

Run conformance:
```sh
make test-kotlin
```

### C#

**Requires:** `libcx` built (`make build`), .NET 10 SDK.

```csharp
using CX;

// Conversion API
string result = CxLib.ToJson("[server [host localhost] [port :int 8080]]");
// {"server": {"host": "localhost", "port": 8080}}

// Document API
var doc = CXDocument.Parse("[config [server host=localhost port=8080]]");
Console.WriteLine(doc.At("config/server")?.Attr("host"));   // localhost

// CXPath select
foreach (var el in doc.SelectAll("//server[@port>=8080]"))
    Console.WriteLine(el.Attr("host"));   // localhost

// Immutable transform
var updated = doc.Transform("config/server", el => {
    el.SetAttr("host", "prod.example.com");
    return el;
});
Console.WriteLine(updated.At("config/server")?.Attr("host"));  // prod.example.com
Console.WriteLine(doc.At("config/server")?.Attr("host"));       // localhost
```

Errors throw `InvalidOperationException`. See `lang/csharp/cxlib/README.md` for the full API reference.

Run the full example:
```sh
DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec dotnet run --project lang/csharp/examples/transform/transform.csproj
```

Run conformance:
```sh
make test-csharp
```

### Swift

**Requires:** `libcx` built (`make build`), Xcode 15+ (Swift 5.9+), macOS.

```swift
import CXLib

// Conversion API
let result = try toJson("[server [host localhost] [port :int 8080]]")
// {"server": {"host": "localhost", "port": 8080}}

// Document API
let doc = try CXDocument.parse("[config [server host=localhost port=8080]]")
print(doc.at("config/server")?.attr("host") as Any)   // localhost

// CXPath select
let svcs = try doc.selectAll("//server[@port>=8080]")
print(svcs.first?.attr("host") as Any)   // localhost

// Immutable transform
let updated = doc.transform("config/server") { el in
    el.setAttr("host", value: "prod.example.com")
    return el
}
print(updated.at("config/server")?.attr("host") as Any)  // prod.example.com
print(doc.at("config/server")?.attr("host") as Any)       // localhost
```

Errors throw `CXError`. See `lang/swift/cxlib/README.md` for the full API reference.

Run the full example:
```sh
swift run --package-path lang/swift/cxlib transform
```

Run conformance:
```sh
make test-swift
```

---

## Building from source

```sh
# Build CLI binary + shared library
make build

# Run conformance tests
make test

# Install shared library and header to dist/
make dist
```

After `make dist`:
```
dist/
  lib/libcx.dylib     # (or libcx.so on Linux)
  include/cx.h        # C header — 49 exported functions (44 conversion + 5 utility/advanced)
```

### C ABI

The shared library exposes 49 C-exported functions: 44 conversion functions
(6×7 standard matrix plus `cx_to_cx_compact` and `cx_ast_to_cx`), plus
`cx_free`, `cx_version`, and 3 advanced streaming/binary functions
(`cx_to_events`, `cx_to_events_bin`, `cx_to_ast_bin`):

```c
#include "cx.h"

// version query
char* ver = cx_version();
printf("libcx %s\n", ver);
cx_free(ver);

// conversion
char* result = cx_to_json("[port :int 8080]", NULL);
// result → "{\"port\": 8080}"
cx_free(result);

// with error handling
char* err = NULL;
char* out = cx_yaml_to_toml(yaml_src, &err);
if (!out) {
    fprintf(stderr, "error: %s\n", err);
    cx_free(err);
}
```

Every string returned by the library (including `cx_version()`) is
heap-allocated and must be released with `cx_free()`. Never free with the
system `free()` directly.

### Conformance tests

The conformance suite lives in `conformance/` and covers:
- `core.txt` — documents, elements, comments, raw text, entity refs, PIs, DTD
- `extended.txt` — scalars, type annotations, arrays (auto-array, `:[]`, typed),
  anchors, merges, multi-doc, triple-quoted strings, block content, short aliases
- `xml.txt` — XML input parsing and round-trips
- `md.txt` — Markdown output from CX, and MD input parsing

```sh
make test          # all suites: V conformance + Rust cross-check + Python
make conform-vcx   # V conformance only (115 cases)
```
