# CX — Python

Python binding for the CX format library. Parses, streams, queries, and
transforms CX documents; converts between CX, XML, JSON, YAML, TOML, and
Markdown via `libcx`.

## Requirements

- Python 3.10 or newer
- `libcx` built from source (one command — see Install)

## Install

```sh
# 1. Clone the repo and build libcx (requires the V compiler — ships with devbox)
git clone https://github.com/cx-lang/cx
cd cx
make build-vcx          # produces vcx/target/libcx.dylib  (or .so on Linux)

# 2. Point Python at the binding
export PYTHONPATH="$PWD/lang/python:$PYTHONPATH"
```

The binding discovers `libcx` automatically relative to its own file. No
extra environment variables are needed as long as you run from the repo root
or have `make install` installed the library to `/usr/local/lib`.

## Quick Start

### Parse and read

```python
import cxlib

src = """[config version='1.0'
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]"""

doc = cxlib.parse(src)

# Navigate by path
server = doc.at('config/server')
print(server.attr('host'))   # localhost
print(server.attr('port'))   # 8080

# Find all descendants named 'server'
for el in doc.find_all('server'):
    print(el.name)
```

### Transform (immutable update)

`transform` and `transform_all` return a **new document** — the original is
unchanged.

```python
import cxlib

doc = cxlib.parse("""[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]""")

# Replace config/server — returns a new document
def update_host(el):
    el.set_attr('host', 'prod.example.com')
    return el

updated = doc.transform('config/server', update_host)

print(updated.at('config/server').attr('host'))  # prod.example.com
print(doc.at('config/server').attr('host'))       # localhost  (original unchanged)

# Chain multiple transforms
result = (doc
    .transform('config/server',   lambda el: (el.set_attr('host', 'web.example.com') or el))
    .transform('config/database', lambda el: (el.set_attr('host', 'db.example.com')  or el)))

print(result.to_cx())
```

### CXPath: select

`select` and `select_all` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and
string functions.

```python
import cxlib

doc = cxlib.parse("""[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]""")

# First match
first = doc.select('//service')
print(first.attr('name'))  # auth

# All active services
for svc in doc.select_all('//service[@active=true]'):
    print(svc.attr('name'))
# auth
# web

# Attribute predicate with numeric comparison
high = doc.select_all('//service[@port>=8000]')
print(len(high))  # 2

# Position
second = doc.select('//service[2]')
print(second.attr('name'))  # api

# select on an Element searches only its subtree (excludes the element itself)
services_el = doc.at('services')
for svc in services_el.select_all('service[@active=true]'):
    print(svc.attr('name'))
```

### transform_all

`transform_all` applies a function to every element matching a CXPath
expression and returns a new document.

```python
import cxlib

doc = cxlib.parse("""[services
  [service name=auth port=8080]
  [service name=api  port=9000]
]""")

def activate(el):
    el.set_attr('active', True)
    return el

updated = doc.transform_all('//service', activate)

for svc in updated.find_all('service'):
    print(svc.attr('active'))  # True
```

### Streaming

`cxlib.stream(src)` returns a `Stream` iterator over all events.

```python
import cxlib

src = """[config version='1.0'
  [server host=localhost port=8080]
]"""

for ev in cxlib.stream(src):
    if ev.is_start_element():
        attrs = '  '.join(f'{a.name}={a.value}' for a in ev.attrs)
        print(f'{ev.name}  {attrs}')
```

Output:
```
config  version=1.0
server  host=localhost  port=8080
```

## Run the Examples

```sh
python lang/python/examples/transform.py
```

## API Reference

### Parse

| Function | Description |
|---|---|
| `parse(s)` | Parse a CX string into a `Document` |
| `parse_xml(s)` | Parse XML into a `Document` |
| `parse_json(s)` | Parse JSON into a `Document` |
| `parse_yaml(s)` | Parse YAML into a `Document` |
| `parse_toml(s)` | Parse TOML into a `Document` |
| `parse_md(s)` | Parse Markdown into a `Document` |

### Document

| Method | Description |
|---|---|
| `doc.root()` | First top-level `Element` |
| `doc.get(name)` | First top-level `Element` by name |
| `doc.at(path)` | Navigate by slash-separated path (`'config/server'`) |
| `doc.find_first(name)` | First matching descendant, depth-first |
| `doc.find_all(name)` | All matching descendants |
| `doc.select(expr)` | First element matching a CXPath expression |
| `doc.select_all(expr)` | All elements matching a CXPath expression |
| `doc.transform(path, fn)` | Return new doc with element at path replaced by `fn(el)` |
| `doc.transform_all(expr, fn)` | Return new doc with all matching elements replaced |
| `doc.append(node)` | Add a top-level node |
| `doc.prepend(node)` | Insert a top-level node at position 0 |
| `doc.to_cx()` | Emit canonical CX |
| `doc.to_xml()` | Emit XML |
| `doc.to_json()` | Emit JSON |
| `doc.to_yaml()` | Emit YAML |
| `doc.to_toml()` | Emit TOML |
| `doc.to_md()` | Emit Markdown |

### Element

| Method | Description |
|---|---|
| `el.get(name)` | First direct child `Element` by name |
| `el.get_all(name)` | All direct child `Element`s by name |
| `el.at(path)` | Navigate relative path from this element |
| `el.attr(name)` | Read an attribute value (`int`/`float`/`bool`/`str`/`None`) |
| `el.text()` | Concatenated text and scalar child content |
| `el.scalar()` | Value of the first `Scalar` child |
| `el.children()` | All direct child `Element`s |
| `el.find_first(name)` | First matching descendant |
| `el.find_all(name)` | All matching descendants |
| `el.select(expr)` | First descendant matching a CXPath expression |
| `el.select_all(expr)` | All descendants matching a CXPath expression |
| `el.set_attr(name, value)` | Set or update an attribute |
| `el.remove_attr(name)` | Remove an attribute |
| `el.append(node)` | Add a child node at the end |
| `el.prepend(node)` | Insert a child node at position 0 |
| `el.insert(index, node)` | Insert a child node at a given index |
| `el.remove(node)` | Remove a child node by identity |
| `el.remove_at(index)` | Remove child node at a given index |
| `el.remove_child(name)` | Remove all direct child `Element`s with the given name |

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

Attribute values auto-type: `true`/`false` → `bool`, integers → `int`,
decimals → `float`, everything else → `str`. An invalid expression raises
`ValueError`.

### Stream

| Function / Method | Description |
|---|---|
| `stream(s)` | Return a `Stream` iterator over a CX string |
| `ev.type` | Event type string: `StartDoc` `EndDoc` `StartElement` `EndElement` `Text` `Scalar` `Comment` `PI` `EntityRef` `RawText` `Alias` |
| `ev.name` | Element name (set on `StartElement` and `EndElement`) |
| `ev.attrs` | `list[Attr]` (set on `StartElement`) |
| `ev.value` | Text / comment / scalar raw value |
| `ev.is_start_element(name)` | `True` if `StartElement`, optionally matching `name` |
| `ev.is_end_element(name)` | `True` if `EndElement`, optionally matching `name` |

### Conversion functions

| Function | Description |
|---|---|
| `to_cx(s)` | CX → canonical CX |
| `to_xml(s)` | CX → XML |
| `to_json(s)` | CX → JSON |
| `to_yaml(s)` | CX → YAML |
| `to_toml(s)` | CX → TOML |
| `to_md(s)` | CX → Markdown |
| `xml_to_cx(s)`, `json_to_cx(s)`, … | Any format → CX |
| `loads(s)` | Parse CX into native Python types (`dict`/`list`/scalar) |
| `dumps(data)` | Serialize Python types back to CX |
| `version()` | Return the libcx version string |

## Tests

```sh
make test-python
```
