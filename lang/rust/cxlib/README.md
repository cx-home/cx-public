# CX — Rust

Rust binding for [CX](https://github.com/cx-org/cx), a concise markup format
with first-class support for XML, JSON, YAML, TOML, and Markdown conversion.
The crate wraps `libcx` via `extern "C"` and exposes a typed Document AST,
a streaming event API, and direct format-conversion functions.

---

## Requirements

- Rust 2021 edition (cargo 1.56+)
- `libcx` shared library — built from the repo root (see below)

---

## Install / Build

**Step 1 — build libcx** (one-time; from the repository root):

```sh
make build-vcx          # produces vcx/target/libcx.dylib (macOS) or libcx.so (Linux)
```

**Step 2 — add the crate** to your `Cargo.toml`:

```toml
[dependencies]
cxlib     = { path = "/path/to/cx/lang/rust/cxlib" }
serde_json = "1"   # needed only when constructing attribute values directly
```

**Step 3 — build your project**, pointing cargo at the library:

```sh
LIBCX_LIB_DIR=/path/to/cx/vcx/target cargo build
```

The `build.rs` script searches for `libcx` in this order:

1. `LIBCX_LIB_DIR` environment variable (explicit path)
2. `pkg-config --libs cx` (set by `sudo make install`)
3. System paths (`/usr/local/lib`, `/opt/homebrew/lib`, …)
4. Repo-relative fallback (`vcx/target/` or `dist/lib/`)

If you install system-wide with `sudo make install` you can drop the
environment variable entirely.

---

## Quick Start

### Document Model

Parse a CX document, read attributes, mutate the tree, then emit canonical CX.

```rust
use cxlib::ast::{self, Element, Node};
use serde_json::Value;

const CX: &str = r#"[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]"#;

fn main() {
    // 1. Parse
    let mut doc = ast::parse(CX).expect("parse failed");

    // 2. Read: get the server element and print attribute values
    {
        let config = doc.root().expect("no root");
        let server = config.get("server").expect("no server");
        println!("host = {}", server.attr("host").unwrap());   // "localhost"
        println!("port = {}", server.attr("port").unwrap());   // 8080
    }

    // 3. Update: change host to "prod.example.com"
    {
        let config = doc.elements.iter_mut()
            .find_map(|n| if let Node::Element(e) = n { Some(e) } else { None })
            .unwrap();
        let server = config.items.iter_mut()
            .find_map(|n| if let Node::Element(e) = n {
                if e.name == "server" { Some(e) } else { None }
            } else { None })
            .unwrap();
        server.set_attr("host", Value::String("prod.example.com".into()), None);

        // 4. Create: append a <timeout>30</timeout>-style element to server
        let mut timeout_el = Element::new("timeout");
        timeout_el.append(Node::Text("30".into()));
        server.append(Node::Element(timeout_el));
    }

    // 5. Delete: remove the cache child from config
    {
        let config = doc.elements.iter_mut()
            .find_map(|n| if let Node::Element(e) = n { Some(e) } else { None })
            .unwrap();
        config.remove_named("cache");
    }

    // 6. Emit
    println!("{}", doc.to_cx());
}
```

Expected output:

```
host = "localhost"
port = 8080

[config version='1.0' debug=false
  [server host=prod.example.com port=8080
    [timeout '30']
  ]
  [database url=postgres://localhost/mydb pool=10]
]
```

> Attribute values are `serde_json::Value`, so string values display with
> surrounding quotes when printed with `{}`.

---

### Streaming

`cxlib::stream()` parses a CX string and returns a flat `Vec<StreamEvent>`.
Each event's payload is a `StreamEventType` variant.

```rust
use cxlib::stream::StreamEventType;

const CX: &str = r#"[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]"#;

fn main() {
    let events = cxlib::stream(CX).expect("stream failed");

    for ev in &events {
        match &ev.event_type {
            StreamEventType::StartDoc => println!("StartDoc"),
            StreamEventType::EndDoc   => println!("EndDoc"),
            StreamEventType::StartElement { name, attrs, .. } => {
                print!("StartElement  name={}", name);
                for a in attrs {
                    print!("  {}={}", a.name, a.value);
                }
                println!();
            }
            StreamEventType::EndElement { name } => println!("EndElement    name={}", name),
            StreamEventType::Text(s)             => println!("Text          {:?}", s),
            StreamEventType::Scalar { data_type, value } => {
                println!("Scalar        type={}  value={}", data_type, value)
            }
            StreamEventType::Comment(s)        => println!("Comment       {:?}", s),
            StreamEventType::PI { target, .. } => println!("PI            target={}", target),
            StreamEventType::EntityRef(s)      => println!("EntityRef     {}", s),
            StreamEventType::RawText(s)        => println!("RawText       {:?}", s),
            StreamEventType::Alias(s)          => println!("Alias         {}", s),
        }
    }
}
```

Expected output:

```
StartDoc
StartElement  name=config  version="1.0"  debug=false
StartElement  name=server  host="localhost"  port=8080
EndElement    name=server
StartElement  name=database  url="postgres://localhost/mydb"  pool=10
EndElement    name=database
StartElement  name=cache  enabled=true  ttl=300
EndElement    name=cache
EndElement    name=config
EndDoc
```

---

## Run the Demo

Create a new project and paste both demos into `src/main.rs`:

```sh
cargo new cxdemo && cd cxdemo
```

`Cargo.toml`:

```toml
[dependencies]
cxlib      = { path = "/path/to/cx/lang/rust/cxlib" }
serde_json = "1"
```

```sh
LIBCX_LIB_DIR=/path/to/cx/vcx/target cargo run
```

Or run the built-in transform example from inside the cxlib crate itself:

```sh
LIBCX_LIB_DIR=/path/to/cx/vcx/target \
  cargo run --example transform --manifest-path lang/rust/cxlib/Cargo.toml
```

Tests (libcx is not thread-safe; force single-threaded):

```sh
LIBCX_LIB_DIR=/path/to/cx/vcx/target \
  cargo test --manifest-path lang/rust/cxlib/Cargo.toml -- --test-threads=1
```

---

## CXPath: select

`select` and `select_all` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and
string functions. Both return `Result<_, String>` — an invalid expression
returns `Err`.

```rust
use cxlib::ast;

let doc = ast::parse(r#"[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]"#).unwrap();

// First match
let first = doc.select("//service").unwrap().unwrap();
println!("{}", first.attr("name").unwrap());   // auth

// All with port >= 8000
let high = doc.select_all("//service[@port>=8000]").unwrap();
println!("{}", high.len());  // 2

// select on an Element searches only its subtree
let services = doc.at("services").unwrap();
let active = services.select_all("service[@active=true]").unwrap();
println!("{}", active.len());  // 2

// Invalid expression
assert!(doc.select_all("[@@@bad").is_err());
```

### transform / transform_all

`transform` and `transform_all` return a **new document** — the original is
unchanged.

```rust
use cxlib::ast;
use serde_json::json;

let doc = ast::parse(r#"[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]"#).unwrap();

// Replace config/server — returns a new document
let updated = doc.transform("config/server", |mut el| {
    el.set_attr("host", json!("prod.example.com"), None);
    el
});

println!("{}", updated.at("config/server").unwrap().attr("host").unwrap());
// prod.example.com
println!("{}", doc.at("config/server").unwrap().attr("host").unwrap());
// localhost  (original unchanged)

// Chain multiple transforms
let result = doc
    .transform("config/server",   |mut el| { el.set_attr("host", json!("web.example.com"), None); el })
    .transform("config/database", |mut el| { el.set_attr("host", json!("db.example.com"),  None); el });

// Apply to every matching element
let flagged = doc.transform_all("//server", |mut el| {
    el.set_attr("active", json!(true), Some("bool".to_string()));
    el
}).unwrap();
```

---

## API Reference

### Conversion

| Function | Input | Returns |
|---|---|---|
| `to_cx(s)` | CX string | `Result<String, String>` — canonical CX |
| `to_cx_compact(s)` | CX string | `Result<String, String>` — compact CX |
| `to_xml(s)` | CX string | `Result<String, String>` |
| `to_json(s)` | CX string | `Result<String, String>` |
| `to_yaml(s)` | CX string | `Result<String, String>` |
| `to_toml(s)` | CX string | `Result<String, String>` |
| `to_md(s)` | CX string | `Result<String, String>` |
| `xml_to_cx(s)` | XML string | `Result<String, String>` |
| `json_to_cx(s)` | JSON string | `Result<String, String>` |
| `yaml_to_cx(s)` | YAML string | `Result<String, String>` |
| `toml_to_cx(s)` | TOML string | `Result<String, String>` |
| `md_to_cx(s)` | Markdown string | `Result<String, String>` |
| `version()` | — | `String` — libcx version |

Cross-format conversions follow the same pattern: `xml_to_json`, `json_to_xml`,
`yaml_to_json`, etc. (every source × every target is available).

### Document

| Item | Description |
|---|---|
| `ast::parse(s)` | Parse CX string into `Document` |
| `ast::parse_xml(s)` | Parse XML string into `Document` |
| `ast::parse_json(s)` | Parse JSON string into `Document` |
| `ast::parse_yaml(s)` | Parse YAML string into `Document` |
| `ast::parse_toml(s)` | Parse TOML string into `Document` |
| `ast::parse_md(s)` | Parse Markdown string into `Document` |
| `ast::loads(s)` | Deserialize CX into `serde_json::Value` |
| `ast::dumps(v)` | Serialize `serde_json::Value` to CX string |
| `Document::root()` | First top-level `Element` |
| `Document::get(name)` | First top-level element with this name |
| `Document::at(path)` | Navigate by slash path, e.g. `"config/server"` |
| `Document::find_all(name)` | All descendant elements with this name |
| `Document::find_first(name)` | First descendant element with this name |
| `Document::select(expr)` | First element matching a CXPath expression (`Result<Option<Element>, String>`) |
| `Document::select_all(expr)` | All elements matching a CXPath expression (`Result<Vec<Element>, String>`) |
| `Document::transform(path, fn)` | Return new doc with element at path replaced by `fn(el)` |
| `Document::transform_all(expr, fn)` | Return new doc with all matching elements replaced (`Result<Document, String>`) |
| `Document::append(node)` | Append a top-level node |
| `Document::to_cx()` | Emit canonical CX (no C library call) |
| `Document::to_xml()` | Emit XML via libcx |
| `Document::to_json()` | Emit JSON via libcx |
| `Document::to_yaml()` | Emit YAML via libcx |
| `Document::to_toml()` | Emit TOML via libcx |
| `Document::to_md()` | Emit Markdown via libcx |

### Element

| Item | Description |
|---|---|
| `Element::attr(name)` | Attribute value by name (`Option<&Value>`) |
| `Element::set_attr(name, value, type)` | Set or update an attribute |
| `Element::remove_attr(name)` | Remove an attribute by name |
| `Element::get(name)` | First child element with this name |
| `Element::get_all(name)` | All child elements with this name |
| `Element::find_all(name)` | All descendant elements (depth-first) |
| `Element::find_first(name)` | First descendant element (depth-first) |
| `Element::at(path)` | Navigate by slash path from this element |
| `Element::select(expr)` | First descendant matching a CXPath expression (`Result<Option<Element>, String>`) |
| `Element::select_all(expr)` | All descendants matching a CXPath expression (`Result<Vec<Element>, String>`) |
| `Element::children()` | All child `Element`s (excludes text/scalar) |
| `Element::text()` | Concatenated text/scalar child content |
| `Element::scalar()` | Value of the first `Scalar` child |
| `Element::append(node)` | Append a child node |
| `Element::prepend(node)` | Prepend a child node |
| `Element::remove_named(name)` | Remove first child element with this name |
| `Element::remove_child(name)` | Remove all direct child elements with this name |
| `Element::remove_child_at(i)` | Remove child node at index (no-op if out of bounds) |
| `Element::remove_at(i)` | Remove child node at index (alias for `remove_child_at`) |
| `Element::new(name)` | Create an empty element |

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
| `[contains(@k, 'v')]` | Attribute contains substring |
| `[starts-with(@k, 'v')]` | Attribute starts with prefix |

Attribute values auto-type: `true`/`false` → `bool`, integers → `int`,
decimals → `float`, everything else → `str`. An invalid expression returns
`Err(String)`.

### Stream

| Item | Description |
|---|---|
| `stream(s)` | Parse CX string into `Vec<StreamEvent>` |
| `StreamEvent::event_type` | The `StreamEventType` variant for this event |
| `StreamEventType::StartDoc` | Document start |
| `StreamEventType::EndDoc` | Document end |
| `StreamEventType::StartElement { name, anchor, data_type, merge, attrs }` | Element open |
| `StreamEventType::EndElement { name }` | Element close |
| `StreamEventType::Text(String)` | Text content |
| `StreamEventType::Scalar { data_type, value }` | Typed scalar value |
| `StreamEventType::Comment(String)` | Comment node |
| `StreamEventType::PI { target, data }` | Processing instruction |
| `StreamEventType::EntityRef(String)` | Entity reference |
| `StreamEventType::RawText(String)` | Raw text block |
| `StreamEventType::Alias(String)` | YAML-style alias |
