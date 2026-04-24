# CX — Go

Go binding for the CX format library via CGo. Parses, streams, queries, and
transforms CX documents; converts between CX, XML, JSON, YAML, TOML, and
Markdown via `libcx`.

## Requirements

- Go 1.21+
- CGo enabled (default)
- A C compiler (clang or gcc)
- `libcx` built (see Install)

## Install / Build

Build `libcx` first, then compile the Go package:

```sh
# 1. Build the native library (from the repo root)
make build-vcx

# 2. Build the Go package
cd lang/go/cxlib
go build ./...
```

This produces `vcx/target/libcx.dylib` (macOS) or `vcx/target/libcx.so`
(Linux). The Go package's `cgo` directives point at that path automatically via
`-Wl,-rpath`, so no extra environment variables are needed.

## Quick Start

> **Required:** call `runtime.LockOSThread()` at the top of `main` before any
> cxlib call. libcx's GC panics if invoked from an unknown OS thread, and Go's
> scheduler moves goroutines between threads.

### Document Model

Parse a CX string into a `*Document`, query and mutate the tree, then
serialize back to CX.

```go
package main

import (
	"fmt"
	"runtime"

	cx "github.com/cx-home/cx/lang/go"
)

const cxStr = `[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]`

func main() {
	runtime.LockOSThread() // required: libcx GC must run on a consistent OS thread

	// 1. Parse
	doc, err := cx.Parse(cxStr)
	if err != nil {
		panic(err)
	}

	// 2. Read: get the server element and print attributes
	server := doc.At("config/server")
	fmt.Printf("server.host = %v\n", server.Attr("host"))
	fmt.Printf("server.port = %v\n", server.Attr("port"))

	// 3. Update: change host to prod address
	server.SetAttr("host", "prod.example.com", "")
	fmt.Printf("updated host = %v\n", server.Attr("host"))

	// 4. Create: append a timeout element with a text child
	timeout := &cx.Element{Name: "timeout"}
	timeout.Append(&cx.TextNode{Value: "30"})
	server.Append(timeout)

	// 5. Delete: remove the cache child from config
	config := doc.Root()
	cache := config.Get("cache")
	config.Remove(cache)

	// 6. Print the modified document as CX
	fmt.Println(doc.ToCx())
}
```

Expected output:

```
server.host = localhost
server.port = 8080
updated host = prod.example.com
[config version='1.0' debug=false
  [server host=prod.example.com port=8080
    [timeout '30']
  ]
  [database url=postgres://localhost/mydb pool=10]
]
```

### Transform (immutable update)

`Transform` and `TransformAll` return a **new document** — the original is
unchanged.

```go
package main

import (
	"fmt"
	"runtime"

	cx "github.com/cx-home/cx/lang/go"
)

const cxStr = `[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]`

func main() {
	runtime.LockOSThread()

	doc, _ := cx.Parse(cxStr)

	// Replace config/server — returns a new document
	updated := doc.Transform("config/server", func(el *cx.Element) *cx.Element {
		el.SetAttr("host", "prod.example.com", "")
		return el
	})

	fmt.Println(updated.At("config/server").Attr("host")) // prod.example.com
	fmt.Println(doc.At("config/server").Attr("host"))     // localhost  (original unchanged)

	// Chain multiple transforms
	result := doc.
		Transform("config/server", func(el *cx.Element) *cx.Element {
			el.SetAttr("host", "web.example.com", "")
			return el
		}).
		Transform("config/database", func(el *cx.Element) *cx.Element {
			el.SetAttr("host", "db.example.com", "")
			return el
		})

	fmt.Println(result.ToCx())
}
```

### CXPath: SelectAll / Select

`Select` and `SelectAll` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and
string functions.

```go
package main

import (
	"fmt"
	"runtime"

	cx "github.com/cx-home/cx/lang/go"
)

const cxStr = `[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]`

func main() {
	runtime.LockOSThread()

	doc, _ := cx.Parse(cxStr)

	// First match
	first, _ := doc.Select("//service")
	fmt.Println(first.Attr("name")) // auth

	// All active services
	actives, _ := doc.SelectAll("//service[@active=true]")
	for _, svc := range actives {
		fmt.Println(svc.Attr("name"))
	}
	// auth
	// web

	// Attribute predicate with numeric comparison
	high, _ := doc.SelectAll("//service[@port>=8000]")
	fmt.Println(len(high)) // 2

	// Position
	second, _ := doc.Select("//service[2]")
	fmt.Println(second.Attr("name")) // api

	// Select on an Element searches only its subtree (excludes the element itself)
	servicesEl := doc.Root()
	results, _ := servicesEl.SelectAll("service[@active=true]")
	for _, svc := range results {
		fmt.Println(svc.Attr("name"))
	}
}
```

### TransformAll

`TransformAll` applies a function to every element matching a CXPath expression
and returns a new document.

```go
package main

import (
	"fmt"
	"runtime"

	cx "github.com/cx-home/cx/lang/go"
)

const cxStr = `[services
  [service name=auth port=8080]
  [service name=api  port=9000]
]`

func main() {
	runtime.LockOSThread()

	doc, _ := cx.Parse(cxStr)

	updated, _ := doc.TransformAll("//service", func(el *cx.Element) *cx.Element {
		el.SetAttr("active", true, "bool")
		return el
	})

	for _, svc := range updated.FindAll("service") {
		fmt.Println(svc.Attr("active")) // true
	}
}
```

### Streaming

Use `Stream` for a one-pass pull of all events without building a tree.

```go
package main

import (
	"fmt"
	"runtime"

	cx "github.com/cx-home/cx/lang/go"
)

const cxStr = `[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]`

func main() {
	runtime.LockOSThread()

	events, err := cx.Stream(cxStr)
	if err != nil {
		panic(err)
	}
	for _, e := range events {
		fmt.Printf("type=%s", e.Type)
		if e.Type == "StartElement" {
			fmt.Printf(" name=%s", e.Name)
			for _, a := range e.Attrs {
				fmt.Printf(" %s=%v", a.Name, a.Value)
			}
		}
		fmt.Println()
	}
}
```

Expected output:

```
type=StartDoc
type=StartElement name=config version=1.0 debug=false
type=StartElement name=server host=localhost port=8080
type=EndElement
type=StartElement name=database url=postgres://localhost/mydb pool=10
type=EndElement
type=StartElement name=cache enabled=true ttl=300
type=EndElement
type=EndElement
type=EndDoc
```

## Run the Demo

The demos above can be placed in a standalone module that uses a `replace`
directive to point at the local source:

```sh
# go.mod
module cxdemo

go 1.21

require github.com/cx-home/cx/lang/go v0.0.0

replace github.com/cx-home/cx/lang/go => /path/to/cx-public/lang/go/cxlib
```

Then run it:

```sh
go run main.go
```

To run the built-in transform example from the repo:

```sh
cd lang/go/cxlib
go run ./examples/transform/
```

## API Reference

### Conversion (CX string in, string out)

| Function | Input | Output |
|---|---|---|
| `ToCx(s)` | CX | canonical CX |
| `ToCxCompact(s)` | CX | compact CX |
| `ToXml(s)` | CX | XML |
| `ToJson(s)` | CX | JSON |
| `ToYaml(s)` | CX | YAML |
| `ToToml(s)` | CX | TOML |
| `ToMd(s)` | CX | Markdown |
| `XmlToCx(s)` | XML | CX |
| `JsonToCx(s)` | JSON | CX |
| `YamlToCx(s)` | YAML | CX |
| `TomlToCx(s)` | TOML | CX |
| `MdToCx(s)` | Markdown | CX |

All conversion functions return `(string, error)`. Additional cross-format
functions (`XmlToJson`, `YamlToXml`, etc.) follow the same pattern.

### Parse

| Function | Description |
|---|---|
| `Parse(s)` | Parse a CX string into a `*Document` |
| `ParseXml(s)` | Parse an XML string into a `*Document` |
| `ParseJson(s)` | Parse a JSON string into a `*Document` |
| `ParseYaml(s)` | Parse a YAML string into a `*Document` |
| `ParseToml(s)` | Parse a TOML string into a `*Document` |
| `ParseMd(s)` | Parse a Markdown string into a `*Document` |

### Document

| Method | Description |
|---|---|
| `doc.Root()` | Return the first top-level `*Element` |
| `doc.Get(name)` | Return the first top-level element with the given name |
| `doc.At(path)` | Navigate by slash-separated path from the root (e.g. `"config/server"`) |
| `doc.FindFirst(name)` | Return the first descendant element with the given name (depth-first) |
| `doc.FindAll(name)` | Return all descendant elements with the given name |
| `doc.Select(expr)` | Return the first `*Element` matching a CXPath expression, or `(nil, error)` |
| `doc.SelectAll(expr)` | Return all `[]*Element` matching a CXPath expression, or `(nil, error)` |
| `doc.Transform(path, fn)` | Return a new `*Document` with the element at path replaced by `fn(el)` |
| `doc.TransformAll(expr, fn)` | Return a new `*Document` with all matching elements replaced, or `(nil, error)` |
| `doc.Append(n)` | Append a top-level node |
| `doc.Prepend(n)` | Insert a top-level node at position 0 |
| `doc.ToCx()` | Serialize the document back to a CX string |
| `doc.ToXml()` | Serialize to XML via the C library |
| `doc.ToJson()` | Serialize to JSON via the C library |
| `doc.ToYaml()` | Serialize to YAML via the C library |
| `doc.ToToml()` | Serialize to TOML via the C library |
| `doc.ToMd()` | Serialize to Markdown via the C library |

### Element

| Method | Description |
|---|---|
| `el.Get(name)` | Return the first direct child `*Element` by name |
| `el.GetAll(name)` | Return all direct child `*Element`s by name |
| `el.At(path)` | Navigate by slash-separated path from this element |
| `el.Attr(name)` | Return the value of the named attribute (`string \| int64 \| float64 \| bool \| nil`) |
| `el.Text()` | Return the concatenated text and scalar child content |
| `el.Scalar()` | Return the value of the first `ScalarNode` child |
| `el.Children()` | Return all direct child `*Element` nodes |
| `el.FindFirst(name)` | Return the first descendant element with the given name (depth-first) |
| `el.FindAll(name)` | Return all descendant elements with the given name (depth-first) |
| `el.Select(expr)` | Return the first `*Element` matching a CXPath expression, or `(nil, error)` |
| `el.SelectAll(expr)` | Return all `[]*Element` matching a CXPath expression, or `(nil, error)` |
| `el.SetAttr(name, value, dataType)` | Upsert an attribute; pass `""` for `dataType` to infer from value |
| `el.RemoveAttr(name)` | Remove an attribute by name |
| `el.Append(n)` | Append a child node |
| `el.Prepend(n)` | Insert a child node at position 0 |
| `el.Insert(i, n)` | Insert a child node at index `i` |
| `el.Remove(n)` | Remove a child node by pointer identity |
| `el.RemoveAt(i)` | Remove the child node at index `i` (no-op if out of bounds) |
| `el.RemoveChild(name)` | Remove all direct child `*Element`s with the given name |

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

Attribute values auto-type: `true`/`false` → `bool`, integers → `int64`,
decimals → `float64`, everything else → `string`. An invalid expression returns
a non-nil `error`.

### Stream

| Function | Description |
|---|---|
| `Stream(s)` | Return all events for a CX string as `([]StreamEvent, error)` |

`StreamEvent` fields:

| Field | Type | Set for |
|---|---|---|
| `Type` | `string` | all events (`StartDoc`, `EndDoc`, `StartElement`, `EndElement`, `Text`, `Scalar`, `Comment`, `PI`, `EntityRef`, `RawText`, `Alias`) |
| `Name` | `string` | `StartElement`, `EndElement` |
| `Attrs` | `[]Attr` | `StartElement` |
| `Anchor` | `*string` | `StartElement` (when present) |
| `DataType` | `*string` | `StartElement`, `Scalar` (when present) |
| `Value` | `any` | `Text`, `Scalar`, `Comment`, `RawText`, `EntityRef`, `Alias` |
| `Target` | `string` | `PI` |
| `Data` | `*string` | `PI` (when present) |

## Tests

```sh
make test-golang
```
