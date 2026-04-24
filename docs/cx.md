# CX

One format that replaces your config files and converts to any output.

```cx
[server
  [-dev and prod connection settings — update before deploying]
  [dev  host=localhost port=8080 debug=true]
  [prod host=0.0.0.0  port=443  debug=false]
]
```

One comment documents the block. Values are auto-typed: `8080` is int,
`true`/`false` are bool. Comments are first-class nodes — they round-trip
through all formats and appear in the streaming event sequence.

Read values directly:

```python
doc   = parse(cx_string)
prod  = doc.at("server/prod")
host  = prod.attr("host")    # "0.0.0.0"
port  = prod.attr("port")    # 443   (int)
debug = prod.attr("debug")   # False (bool)
```

All languages expose the same tree API: `parse`, `at(path)`, `get(name)`,
`attr(name)`, `scalar()`, `children`, `find_all(name)`.

## Convert to any format

```python
to_json(cx)     # {"server": {"host": "0.0.0.0", "port": 8080, "debug": false, ...}}
to_xml(cx)      # <server><host>0.0.0.0</host><port>8080</port>...</server>
to_yaml(cx)     # server:\n  host: 0.0.0.0\n  port: 8080...
to_toml(cx)     # [server]\nhost = "0.0.0.0"\nport = 8080...

json_to_cx(json)   # CX from JSON
yaml_to_cx(yaml)   # CX from YAML
xml_to_cx(xml)     # CX from XML
```

Lossless — all formats round-trip through the CX AST without information loss.

## Syntax

```cx
[name]                         empty element
[name body text]               element with body
[name key=value body]          element with attribute
[name :type value]             explicit type override
```

Every construct is `[name attrs... body]`. No closing tags. No indentation rules.

### Auto-typing

| Value          | Type    |
|----------------|---------|
| `42` `-7`      | int     |
| `3.14`         | float   |
| `true` `false` | bool    |
| `2026-04-19`   | date    |
| everything else | string |

Override when auto-typing would be wrong:

```cx
[zip :string 90210]     force string (would auto-type as int)
[ratio :float 1]        force float (would auto-type as int)
```

Short aliases: `:i` (int), `:f` (float), `:b` (bool), `:s` (string).

### Arrays

```cx
[tags :string[] api v2 stable]    explicit string array
[scores 10 20 30]                  auto-array (homogeneous → int[])
[data :[] 1 2.5 3]                 inferred (promotes to float[])
```

### Inline docs and comments

```cx
[server
  [-address for incoming HTTP connections — default binds all interfaces]
  [host 0.0.0.0]
  [-port must match the load balancer target group]
  [port 8080]
  [-set true only in dev; disables auth checks]
  [debug false]
]
```

Comments are nodes. They survive serialization and appear in the streaming
event sequence. Unlike `//` or `#` comments, they never silently disappear.

### Multi-line strings

```cx
[description '''
  First line of description.
  Second line.
''']
```

### Block content (code, prose)

```cx
[``` lang=bash [|
git clone https://github.com/ardec/cx
make build
|]]
```

### Anchors and aliases (DRY config)

```cx
[defaults &base timeout=30 retries=3]
[staging  *base host=staging.example.com]
[prod     *base host=prod.example.com retries=5]
```

## Document markup

The same format works for documents. Data and markup coexist in one file.

```cx
[guide title="Getting Started"
  [-internal note: audience is backend engineers]

  [# What is CX?]

  [p CX is a [** structured] format with [* clean] bracket syntax.]

  [ul
    [li Converts to XML, JSON, YAML, TOML, Markdown]
    [li Comments and processing instructions are first-class]
    [li Data and markup in a single file]
  ]

  [## Config example]

  [server [host 0.0.0.0] [port 8080] [debug false]]
]
```

Markup: `[# h1]`, `[## h2]`, `[p text]`, `[ul [li ...]]`, `[** bold]`,
`[* italic]`, `[~~ strike]`, `` [` code] ``, `[a href="..." text]`.

## Streaming

Process large documents without loading the full tree:

```python
for event in stream(cx):
    if event.type == "StartElement":
        print(event.name, event.attrs)
    elif event.type == "Scalar":
        print(event.value)   # typed: int, float, bool, str
```

Event types: `StartDoc`, `EndDoc`, `StartElement`, `EndElement`, `Text`,
`Scalar`, `Comment`, `RawText`, `EntityRef`, `Alias`, `PI`.

## Language bindings

All bindings expose the same API: parse, stream, to_json/xml/yaml/toml/md,
json/xml/yaml/toml_to_cx.

Build from source: `git clone https://github.com/ardec/cx && make build`

| Language   | Path in repo                   |
|------------|--------------------------------|
| Python     | `lang/python/cxlib/`           |
| Go         | `lang/go/cxlib/`               |
| Rust       | `lang/rust/cxlib/`             |
| TypeScript | `lang/typescript/cxlib/`       |
| Java       | `lang/java/cxlib/`             |
| Kotlin     | `lang/kotlin/cxlib/`           |
| C#         | `lang/csharp/cxlib/`           |
| Swift      | `lang/swift/cxlib/`            |
| Ruby       | `lang/ruby/cxlib/`             |
| V          | `lang/v/cxlib/`                |

## Format conversion matrix

| From → To | CX | XML | JSON | YAML | TOML | MD |
|-----------|----|-----|------|------|------|----|
| CX        | ✓  | ✓   | ✓    | ✓    | ✓    | ✓  |
| XML       | ✓  | ✓   | ✓    | ✓    | ✓    | ✓  |
| JSON      | ✓  | ✓   | ✓    | ✓    | ✓    | ✓  |
| YAML      | ✓  | ✓   | ✓    | ✓    | ✓    | ✓  |
| TOML      | ✓  | ✓   | ✓    | ✓    | ✓    | ✓  |
| Markdown  | ✓  | ✓   | ✓    | ✓    | ✓    | ✓  |

Spec: Grammar v3.3 · AST v2.3 · Conformance v1.0 · Library v1.0.0
