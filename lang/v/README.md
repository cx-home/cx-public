# CX — V

V binding for the CX format library. V is the native implementation language —
the `vcx/` core is written in V and compiled to `libcx`. All other language
bindings link the same shared library.

## Requirements

- V 0.5 or later (`v --version` to check)
- The `libcx` shared library — built from the repo root with `make build-vcx`

## Install

This binding wraps `libcx` and requires the shared library to be built first.
For a pure V install with no C dependency, use
[cx-home/cx-v](https://github.com/cx-home/cx-v) (`v install cx-home.cx`).

```sh
# 1. Build the shared library (from repo root)
make build-vcx

# 2. Point V at the module (add to your shell profile)
export VMODULES=/path/to/cx/lang/v

# 3. Import cxlib in any V file
v run myapp.v
```

**Within the repo** you do not need to set `VMODULES` — V finds `cxlib`
automatically via the `v.mod` file at `lang/v/`. Run files from the repo root:

```sh
v run lang/v/examples/demo.v
```

## Quick Start

### Parse and read

```v
import cxlib

fn main() {
    src := "[config version='1.0'
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]"

    doc := cxlib.parse(src) or { panic(err) }

    // Navigate by path
    server := doc.at('config/server') or { panic('no server') }
    println(server.attr('host') or { '' }.str())  // localhost
    println(server.attr('port') or { '' }.str())  // 8080

    // Find all descendants named 'server'
    for el in doc.find_all('server') {
        println(el.name)
    }
}
```

### Transform (immutable update)

Documents are immutable values. `transform` and `transform_all` return a new
document with the specified elements replaced — the original is unchanged.

```v
import cxlib

fn main() {
    doc := cxlib.parse("[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]") or { panic(err) }

    // Replace config/server — returns a new document
    updated := doc.transform('config/server', fn (el cxlib.Element) cxlib.Element {
        mut e := el
        e.set_attr('host', cxlib.ScalarVal('prod.example.com'))
        return e
    })

    println(updated.at('config/server') or { panic('') }.attr('host') or { '' }.str())
    // prod.example.com

    println(doc.at('config/server') or { panic('') }.attr('host') or { '' }.str())
    // localhost  (original unchanged)

    // Chain multiple transforms
    result := doc
        .transform('config/server',   fn (el cxlib.Element) cxlib.Element {
            mut e := el; e.set_attr('host', cxlib.ScalarVal('web.example.com')); return e
        })
        .transform('config/database', fn (el cxlib.Element) cxlib.Element {
            mut e := el; e.set_attr('host', cxlib.ScalarVal('db.example.com')); return e
        })

    println(result.to_cx())
}
```

### CXPath: select

`select` and `select_all` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and
string functions.

```v
import cxlib

fn main() {
    doc := cxlib.parse("[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]") or { panic(err) }

    // First match
    first := doc.select('//service') or { panic('') }
    println(first.attr('name') or { '' }.str())  // auth

    // All active services
    for svc in doc.select_all('//service[@active=true]') {
        println(svc.attr('name') or { '' }.str())
    }
    // auth
    // web

    // Attribute predicate with numeric comparison
    high := doc.select_all('//service[@port>=8000]')
    println(high.len)  // 2

    // Position
    second := doc.select('//service[2]') or { panic('') }
    println(second.attr('name') or { '' }.str())  // api

    // select on an Element searches only its subtree (excludes the element itself)
    services_el := doc.at('services') or { panic('') }
    for svc in services_el.select_all('service[@active=true]') {
        println(svc.attr('name') or { '' }.str())
    }
}
```

### transform_all

`transform_all` applies a function to every element matching a CXPath
expression and returns a new document.

```v
import cxlib

fn main() {
    doc := cxlib.parse("[services
  [service name=auth port=8080]
  [service name=api  port=9000]
]") or { panic(err) }

    updated := doc.transform_all('//service', fn (el cxlib.Element) cxlib.Element {
        mut e := el
        e.set_attr('active', cxlib.ScalarVal(true))
        return e
    })

    for svc in updated.find_all('service') {
        println(svc.attr('active') or { '' }.str())  // true
    }
}
```

### Streaming

`cxlib.stream(src)` parses CX and returns all events as `![]StreamEvent`.

```v
import cxlib

fn main() {
    src := "[config version='1.0'
  [server host=localhost port=8080]
]"
    events := cxlib.stream(src) or { panic(err) }
    for ev in events {
        if ev.typ == .start_element {
            print('${ev.name}')
            for a in ev.attrs {
                print('  ${a.name}=${a.value.str()}')
            }
            println('')
        }
    }
}
```

Output:
```
config  version=1.0
server  host=localhost  port=8080
```

## Run the Examples

```sh
v run lang/v/examples/demo.v      # document model + streaming
v run lang/v/examples/transform.v # format-conversion showcase
```

## API Reference

### Parse

| Function | Description |
|---|---|
| `parse(src) !Document` | Parse CX source |
| `parse_xml(src) !Document` | Parse XML |
| `parse_json(src) !Document` | Parse JSON |
| `parse_yaml(src) !Document` | Parse YAML |
| `parse_toml(src) !Document` | Parse TOML |
| `parse_md(src) !Document` | Parse Markdown |

### Document

| Method | Description |
|---|---|
| `doc.root() ?Element` | First top-level Element |
| `doc.get(name) ?Element` | Top-level Element by name |
| `doc.at(path) ?Element` | Navigate by slash-separated path (`'config/server'`) |
| `doc.find_first(name) ?Element` | First matching descendant, depth-first |
| `doc.find_all(name) []Element` | All matching descendants |
| `doc.select(expr) ?Element` | First element matching a CXPath expression |
| `doc.select_all(expr) []Element` | All elements matching a CXPath expression |
| `doc.transform(path, fn) Document` | Return new doc with element at path replaced by fn(el) |
| `doc.transform_all(expr, fn) Document` | Return new doc with all matching elements replaced |
| `doc.append(node)` | Add a top-level node |
| `doc.prepend(node)` | Insert a top-level node at position 0 |
| `doc.to_cx() string` | Emit canonical CX |
| `doc.to_xml() !string` | Emit XML |
| `doc.to_json() !string` | Emit JSON |
| `doc.to_yaml() !string` | Emit YAML |
| `doc.to_toml() !string` | Emit TOML |
| `doc.to_md() !string` | Emit Markdown |

### Element

| Method | Description |
|---|---|
| `el.get(name) ?Element` | First direct child Element by name |
| `el.get_all(name) []Element` | All direct child Elements by name |
| `el.at(path) ?Element` | Navigate relative path from this element |
| `el.attr(name) ?ScalarVal` | Read an attribute value |
| `el.text() string` | Concatenated text and scalar child content |
| `el.scalar() ?ScalarVal` | Value of the first ScalarNode child |
| `el.children() []Element` | All direct child Elements |
| `el.find_first(name) ?Element` | First matching descendant |
| `el.find_all(name) []Element` | All matching descendants |
| `el.select(expr) ?Element` | First descendant matching a CXPath expression |
| `el.select_all(expr) []Element` | All descendants matching a CXPath expression |
| `el.set_attr(name, ScalarVal)` | Set or update an attribute |
| `el.remove_attr(name)` | Remove an attribute |
| `el.append(node)` | Add a child node at the end |
| `el.prepend(node)` | Insert a child node at position 0 |
| `el.insert(index, node)` | Insert a child node at a given index |
| `el.remove_at(index)` | Remove child node at a given index |
| `el.remove_child(name)` | Remove all direct child Elements with the given name |

### CXPath expressions

| Syntax | Matches |
|---|---|
| `//name` | All descendants named `name` |
| `a/b/c` | Child path |
| `*` | Any element (wildcard) |
| `[@attr]` | Has attribute |
| `[@attr=val]` | Attribute equals value (typed) |
| `[@attr!=val]` | Attribute not equal |
| `[@attr>=val]` | Numeric comparison (`>`, `<`, `>=`, `<=`) |
| `[@a=x and @b=y]` | Boolean `and` / `or` |
| `[not(@attr)]` | Negation |
| `[childname]` | Has a direct child element named `childname` |
| `[1]`, `[2]`, `[last()]` | Position (1-based) |
| `[contains(@k, v)]` | Attribute contains substring |
| `[starts-with(@k, v)]` | Attribute starts with prefix |

Attribute values auto-type: `true`/`false` → bool, integers → i64, decimals → f64, everything else → string. An invalid expression panics.

### Stream

| Function | Description |
|---|---|
| `stream(src) ![]StreamEvent` | Parse CX and return all events |
| `ev.typ` | `EventType` enum value |
| `ev.is_start_element(names...)` | True if `.start_element` and name matches (if given) |
| `ev.is_end_element(names...)` | True if `.end_element` and name matches (if given) |
| `ev.name` | Element name (`.start_element` / `.end_element`) |
| `ev.attrs` | `[]Attr` (`.start_element`) |
| `ev.anchor`, `ev.merge`, `ev.data_type` | Element metadata (`.start_element`) |
| `ev.value` | Text / comment / entity ref / alias / scalar raw value |
| `ev.target`, `ev.data` | PI target and data (`.pi`) |

Event types: `.start_doc` `.end_doc` `.start_element` `.end_element`
`.text` `.scalar` `.comment` `.pi` `.entity_ref` `.raw_text` `.alias_`

### Conversion functions

| Function | Description |
|---|---|
| `to_cx(src) !string` | CX → canonical CX |
| `to_xml(src) !string` | CX → XML |
| `to_json(src) !string` | CX → JSON |
| `to_yaml(src) !string` | CX → YAML |
| `to_toml(src) !string` | CX → TOML |
| `to_md(src) !string` | CX → Markdown |
| `xml_to_cx(src) !string` | XML → CX |
| `json_to_cx(src) !string` | JSON → CX |
| `yaml_to_cx(src) !string` | YAML → CX |
| `toml_to_cx(src) !string` | TOML → CX |
| `md_to_cx(src) !string` | Markdown → CX |
| `loads(cx_str) !json2.Any` | Parse CX into native V types (map/array/scalar) |
| `dumps(data json2.Any) !string` | Serialize V types back to CX |
| `version() string` | Return the libcx version string |

## Tests

```sh
make test-v
```
