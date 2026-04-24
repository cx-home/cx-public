# CX — Swift

Swift binding for the CX format library. Parses, queries, mutates, and
converts CX, XML, JSON, YAML, TOML, and Markdown via a thin wrapper around
`libcx`.

## Requirements

| Tool | Version |
|---|---|
| Swift / Xcode | 5.9+ (Xcode 15+) |
| macOS | 12+ |
| libcx | built from repo (see Install) |

## Install / Build

From the repo root, build `libcx` and then the Swift package:

```sh
make build-vcx          # builds vcx/target/libcx.dylib
make build-swift        # swift build --package-path lang/swift/cxlib -c release
```

If you are building outside Xcode's default environment (e.g. on CI), set the
SDK paths that the Makefile uses automatically:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT=$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
```

To use `CXLib` in your own Swift package, add a path dependency:

```swift
// Package.swift
.package(path: "/path/to/cx/lang/swift/cxlib")

// your target
.target(name: "MyApp", dependencies: ["CXLib"])
```

## Quick Start

### CXPath: select

`select` and `selectAll` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and string
functions. Both methods `throw` on an invalid expression.

```swift
import CXLib

let cxInput = """
[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]
"""

let doc = try CXDocument.parse(cxInput)

// First match
let first = try doc.select("//service")
print(first?.attr("name") ?? "nil")  // auth

// All active services
for svc in try doc.selectAll("//service[@active=true]") {
    print(svc.attr("name") ?? "nil")
}
// auth
// web

// Attribute predicate with numeric comparison
let high = try doc.selectAll("//service[@port>=8000]")
print(high.count)  // 2

// Position (1-based)
let second = try doc.select("//service[2]")
print(second?.attr("name") ?? "nil")  // api

// select on an Element searches only its subtree (excludes the element itself)
let servicesEl = doc.at("services")!
for svc in try servicesEl.selectAll("service[@active=true]") {
    print(svc.attr("name") ?? "nil")
}
```

### transform / transformAll

`transform` and `transformAll` return **new** `CXDocument` instances — the
original is not mutated.

```swift
import CXLib

let doc = try CXDocument.parse("""
[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]
""")

// Replace config/server — returns a new document
let updated = doc.transform("config/server") { el in
    el.setAttr("host", value: "prod.example.com")
    return el
}
print(updated.at("config/server")?.attr("host") ?? "nil")  // prod.example.com
print(doc.at("config/server")?.attr("host") ?? "nil")       // localhost (original unchanged)

// Chain multiple transforms
let result = doc
    .transform("config/server")   { el in el.setAttr("host", value: "web.example.com"); return el }
    .transform("config/database") { el in el.setAttr("host", value: "db.example.com");  return el }
print(result.toCx())

// transformAll: apply to every element matching a CXPath expression
let doc2 = try CXDocument.parse("""
[services
  [service name=auth port=8080]
  [service name=api  port=9000]
]
""")

let activated = try doc2.transformAll("//service") { el in
    el.setAttr("active", value: true)
    return el
}
for svc in activated.findAll("service") {
    print(svc.attr("active") ?? "nil")  // true
}
```

### removeChild / removeAt

```swift
import CXLib

let doc = try CXDocument.parse("""
[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
  [logging level=info]
]
""")
let config = doc.root()!

// Remove all direct child elements named "database"
config.removeChild("database")
print(config.get("database"))  // nil

// Remove child node at index 0 (the server element)
config.removeAt(0)
print(config.children().map { $0.name })  // ["logging"]
```

### Document Model

Parse a CX string into a live document tree, then read, update, add, remove,
and re-emit.

```swift
import CXLib

let cxInput = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
"""

// 1. Parse
let doc = try CXDocument.parse(cxInput)

// 2. Read — navigate by path, get typed attribute values
let server = doc.at("config/server")!
print("host:", server.attr("host") ?? "nil")  // "localhost"
print("port:", server.attr("port") ?? "nil")  // 8080 (Int)

// 3. Update — setAttr updates in-place or appends
server.setAttr("host", value: "prod.example.com")

// 4. Create — build an Element and append it as a child
let timeout = Element("timeout", attrs: [Attr("seconds", 30, dataType: "int")])
server.append(.element(timeout))

// 5. Delete — remove a child by object identity
let config = doc.at("config")!
let cache  = config.get("cache")!
config.remove(.element(cache))

// 6. Re-emit
print(doc.toCx())
```

Expected output:

```
host: localhost
port: 8080

[config version='1.0' debug=false
  [server host=prod.example.com port=8080
    [timeout seconds=30]
  ]
  [database url=postgres://localhost/mydb pool=10]
]
```

### Streaming

`CXDocument.stream(_:)` parses a CX string and returns the full event
sequence as `[StreamEvent]` in one call — no callbacks needed.

```swift
import CXLib

let cxInput = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
"""

let events = try CXDocument.stream(cxInput)
for ev in events {
    if ev.type == "StartElement" {
        let attrStr = ev.attrs
            .map { "\($0.name)=\($0.value ?? "nil")" }
            .joined(separator: " ")
        print("\(ev.type) \(ev.name ?? "") \(attrStr)")
    } else {
        print(ev.type)
    }
}
```

Expected output:

```
StartDoc
StartElement config version=1.0 debug=false
StartElement server host=localhost port=8080
EndElement
StartElement database url=postgres://localhost/mydb pool=10
EndElement
StartElement cache enabled=true ttl=300
EndElement
EndElement
EndDoc
```

## Run the Demo

The package includes a runnable `Demo` target containing both examples above.
From the repo root:

```sh
make build-vcx
make build-swift
swift run --package-path lang/swift/cxlib -c release Demo
```

Or using the Makefile's `SWIFT_FLAGS` directly if `swift` is not in your PATH:

```sh
make build-vcx
SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  run --package-path lang/swift/cxlib -c release Demo
```

To run the full format-conversion showcase:

```sh
make example-swift          # runs the transform example
```

To run the test suite:

```sh
make test-swift
```

## API Reference

### Conversion — `CXLib.*`

All functions take a string and return a string (all `throws`).

| Method | Input | Output |
|---|---|---|
| `CXLib.toCx(_:)` | CX | canonical CX |
| `CXLib.toCxCompact(_:)` | CX | compact CX |
| `CXLib.toXml(_:)` | CX | XML |
| `CXLib.toJson(_:)` | CX | JSON |
| `CXLib.toYaml(_:)` | CX | YAML |
| `CXLib.toToml(_:)` | CX | TOML |
| `CXLib.toMd(_:)` | CX | Markdown |
| `CXLib.xmlToCx(_:)` | XML | CX |
| `CXLib.jsonToCx(_:)` | JSON | CX |
| `CXLib.yamlToCx(_:)` | YAML | CX |
| `CXLib.tomlToCx(_:)` | TOML | CX |
| `CXLib.mdToCx(_:)` | Markdown | CX |
| `CXLib.version()` | — | version string |

Full cross-format matrix (XML/JSON/YAML/TOML/MD → XML/JSON/YAML/TOML/MD) is
also available; see `CXLib.swift` for the complete list.

### Document — `CXDocument`

| Method | Returns | Notes |
|---|---|---|
| `CXDocument.parse(_:)` | `CXDocument` (throws) | parse CX string |
| `CXDocument.parseXml(_:)` | `CXDocument` (throws) | parse XML |
| `CXDocument.parseJson(_:)` | `CXDocument` (throws) | parse JSON |
| `CXDocument.parseYaml(_:)` | `CXDocument` (throws) | parse YAML |
| `CXDocument.parseToml(_:)` | `CXDocument` (throws) | parse TOML |
| `CXDocument.parseMd(_:)` | `CXDocument` (throws) | parse Markdown |
| `CXDocument.loads(_:)` | `Any` (throws) | CX → native Swift dict/array |
| `CXDocument.dumps(_:)` | `String` (throws) | native Swift → CX string |
| `doc.root()` | `Element?` | first top-level element |
| `doc.get(_:)` | `Element?` | top-level element by name |
| `doc.at(_:)` | `Element?` | navigate by slash path, e.g. `"config/server"` |
| `doc.findAll(_:)` | `[Element]` | all descendants with name (depth-first) |
| `doc.findFirst(_:)` | `Element?` | first descendant with name |
| `doc.select(_:)` | `Element?` (throws) | first element matching a CXPath expression |
| `doc.selectAll(_:)` | `[Element]` (throws) | all elements matching a CXPath expression |
| `doc.transform(_:_:)` | `CXDocument` | new doc with element at path replaced by closure |
| `doc.transformAll(_:_:)` | `CXDocument` (throws) | new doc with all matching elements replaced |
| `doc.append(_:)` | `Void` | append a `Node` to top-level elements |
| `doc.prepend(_:)` | `Void` | prepend a `Node` to top-level elements |
| `doc.toCx()` | `String` | emit document as CX string |
| `doc.toXml()` | `String` (throws) | emit as XML |
| `doc.toJson()` | `String` (throws) | emit as JSON |
| `doc.toYaml()` | `String` (throws) | emit as YAML |
| `doc.toToml()` | `String` (throws) | emit as TOML |

**`Element` methods:**

| Method | Returns | Notes |
|---|---|---|
| `el.attr(_:)` | `Any?` | attribute value by name (typed: `Int`, `Bool`, `Double`, `String`) |
| `el.setAttr(_:value:dataType:)` | `Void` | update or append attribute |
| `el.removeAttr(_:)` | `Void` | remove attribute by name |
| `el.get(_:)` | `Element?` | first direct child element with name |
| `el.getAll(_:)` | `[Element]` | all direct child elements with name |
| `el.at(_:)` | `Element?` | navigate by slash path relative to this element |
| `el.findAll(_:)` | `[Element]` | all descendants with name |
| `el.findFirst(_:)` | `Element?` | first descendant with name |
| `el.select(_:)` | `Element?` (throws) | first descendant matching a CXPath expression |
| `el.selectAll(_:)` | `[Element]` (throws) | all descendants matching a CXPath expression |
| `el.children()` | `[Element]` | all direct child elements |
| `el.text()` | `String` | concatenated text/scalar child content |
| `el.scalar()` | `Any?` | value of first scalar child |
| `el.append(_:)` | `Void` | append a `Node` |
| `el.prepend(_:)` | `Void` | prepend a `Node` |
| `el.insert(_:_:)` | `Void` | insert a `Node` at index |
| `el.remove(_:)` | `Void` | remove child node by object identity |
| `el.removeAt(_:)` | `Void` | remove child node at index (no-op if out of bounds) |
| `el.removeChild(_:)` | `Void` | remove all direct child elements with the given name |
| `el.toCx()` | `String` | emit this element as a CX string |

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

Attribute values in predicates auto-type: `true`/`false` → `Bool`, integers →
`Int`, decimals → `Double`, `null` → `nil`, everything else → `String`. An
invalid expression throws `CXPathError`.

### Stream — `CXDocument.stream`

| Method | Returns | Notes |
|---|---|---|
| `CXDocument.stream(_:)` | `[StreamEvent]` (throws) | parse CX into event list |
| `ev.type` | `String` | `StartDoc`, `EndDoc`, `StartElement`, `EndElement`, `Text`, `Scalar`, `Comment`, `PI`, `EntityRef`, `RawText`, `Alias` |
| `ev.name` | `String?` | element name (StartElement / EndElement) |
| `ev.attrs` | `[Attr]` | element attributes (StartElement only) |
| `ev.value` | `Any?` | typed value for Text, Scalar, Comment, etc. |
| `ev.isStartElement(_:)` | `Bool` | helper: `ev.isStartElement("config")` |
| `ev.isEndElement(_:)` | `Bool` | helper: `ev.isEndElement("config")` |
