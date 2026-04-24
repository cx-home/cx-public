# CX — C#

C# binding for the CX format library. Parses, streams, and converts
CX/XML/JSON/YAML/TOML/Markdown via P/Invoke into `libcx`.

---

## Requirements

- [.NET 10](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)
- `libcx` built from this repo (see Install)

---

## Install / Build

**Step 1 — build `libcx`** (the native shared library):

```sh
make build-vcx
```

This produces `vcx/target/libcx.dylib` (macOS) or `vcx/target/libcx.so` (Linux).

**Step 2 — build the C# library**:

```sh
dotnet build lang/csharp/cxlib/cxlib.csproj
```

**Step 3 — reference from your project**:

```sh
dotnet add reference /path/to/cx/lang/csharp/cxlib/cxlib.csproj
```

The library finds `libcx` automatically by walking up from the app's base
directory to locate the repo root. You can also set `LIBCX_PATH` to an
absolute path or `LIBCX_LIB_DIR` to a directory containing the `.dylib`/`.so`.

---

## Quick Start

### Document Model

Parse CX into a mutable tree. Read, update, create, and delete nodes, then
serialize back to CX (or any other supported format).

```csharp
using CX;

string cxStr = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
""";

// 1. Parse
var doc = CXDocument.Parse(cxStr);

// 2. Read — get the server element and print its attributes
var server = doc.At("config/server")!;
Console.WriteLine($"host: {server.Attr("host")}");   // host: localhost
Console.WriteLine($"port: {server.Attr("port")}");   // port: 8080

// 3. Update — change host to the production value
server.SetAttr("host", "prod.example.com");

// 4. Create — add a timeout child element to server
var timeout = new Element("timeout");
timeout.Attrs.Add(new Attr("seconds", 30L, "int"));
server.Append(timeout);

// 5. Delete — remove the cache element from config
var config = doc.Root()!;
var cache = config.Get("cache")!;
config.Remove(cache);

// 6. Print the modified document as CX
Console.WriteLine(doc.ToCx());
```

Output:

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

### Transform (immutable update)

`Transform` and `TransformAll` return a **new document** — the original is
unchanged.

```csharp
using CX;

var doc = CXDocument.Parse("""
[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]
""");

// Replace config/server — returns a new document
var updated = doc.Transform("config/server", el =>
{
    el.SetAttr("host", "prod.example.com");
    return el;
});

Console.WriteLine(updated.At("config/server")!.Attr("host"));  // prod.example.com
Console.WriteLine(doc.At("config/server")!.Attr("host"));      // localhost  (original unchanged)

// Chain multiple transforms
var result = doc
    .Transform("config/server",   el => { el.SetAttr("host", "web.example.com"); return el; })
    .Transform("config/database", el => { el.SetAttr("host", "db.example.com");  return el; });

Console.WriteLine(result.ToCx());
```

### CXPath: SelectAll / Select

`Select` and `SelectAll` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and
string functions.

```csharp
using CX;

var doc = CXDocument.Parse("""
[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]
""");

// First match
var first = doc.Select("//service");
Console.WriteLine(first!.Attr("name"));  // auth

// All active services
foreach (var svc in doc.SelectAll("//service[@active=true]"))
    Console.WriteLine(svc.Attr("name"));
// auth
// web

// Attribute predicate with numeric comparison
var high = doc.SelectAll("//service[@port>=8000]").ToList();
Console.WriteLine(high.Count);  // 2

// Position
var second = doc.Select("//service[2]");
Console.WriteLine(second!.Attr("name"));  // api

// Select on an Element searches only its subtree
var servicesEl = doc.At("services")!;
foreach (var svc in servicesEl.SelectAll("service[@active=true]"))
    Console.WriteLine(svc.Attr("name"));
```

### TransformAll

`TransformAll` applies a function to every element matching a CXPath
expression and returns a new document.

```csharp
using CX;

var doc = CXDocument.Parse("""
[services
  [service name=auth port=8080]
  [service name=api  port=9000]
]
""");

var updated = doc.TransformAll("//service", el =>
{
    el.SetAttr("active", true);
    return el;
});

foreach (var svc in updated.FindAll("service"))
    Console.WriteLine(svc.Attr("active"));  // True
```

### Streaming

Stream the same CX string as a sequence of events. Each event has a `Type`;
`StartElement` events also carry the element name and its attributes.

```csharp
using CX;

string cxStr = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
""";

foreach (var ev in CXDocument.Stream(cxStr))
{
    Console.Write($"event: {ev.Type}");
    if (ev.Type == "StartElement")
    {
        Console.Write($"  name={ev.Name}");
        foreach (var attr in ev.Attrs)
            Console.Write($"  {attr.Name}={attr.Value}");
    }
    Console.WriteLine();
}
```

Output:

```
event: StartDoc
event: StartElement  name=config  version=1.0  debug=False
event: StartElement  name=server  host=localhost  port=8080
event: EndElement
event: StartElement  name=database  url=postgres://localhost/mydb  pool=10
event: EndElement
event: StartElement  name=cache  enabled=True  ttl=300
event: EndElement
event: EndElement
event: EndDoc
```

---

## Run the Demo

A self-contained demo project lives at `lang/csharp/examples/readme_demo/`.
From the repo root:

```sh
dotnet run --project lang/csharp/examples/readme_demo/readme_demo.csproj
```

To run the full API test suite:

```sh
make test-csharp
```

---

## API Reference

### Conversion — `CxLib` (static)

All methods accept a string and return a string. Throws `InvalidOperationException` on parse error.

| Method | Input format | Output format |
|---|---|---|
| `CxLib.ToCx(s)` | CX | CX (canonical) |
| `CxLib.ToCxCompact(s)` | CX | CX (compact, single line) |
| `CxLib.ToXml(s)` | CX | XML |
| `CxLib.ToJson(s)` | CX | JSON |
| `CxLib.ToYaml(s)` | CX | YAML |
| `CxLib.ToToml(s)` | CX | TOML |
| `CxLib.ToMd(s)` | CX | Markdown |
| `CxLib.ToAst(s)` | CX | AST JSON |
| `CxLib.XmlToCx(s)` | XML | CX |
| `CxLib.JsonToCx(s)` | JSON | CX |
| `CxLib.YamlToCx(s)` | YAML | CX |
| `CxLib.TomlToCx(s)` | TOML | CX |
| `CxLib.MdToCx(s)` | Markdown | CX |
| `CxLib.Version()` | — | version string |

Cross-format conversions follow the same `{From}To{To}` naming pattern:
`CxLib.XmlToJson`, `CxLib.JsonToYaml`, `CxLib.YamlToToml`, etc.

### Document — `CXDocument`

| Method / Property | Description |
|---|---|
| `CXDocument.Parse(cxStr)` | Parse a CX string into a `CXDocument` |
| `CXDocument.ParseXml(s)` | Parse XML into a `CXDocument` |
| `CXDocument.ParseJson(s)` | Parse JSON into a `CXDocument` |
| `CXDocument.ParseYaml(s)` | Parse YAML into a `CXDocument` |
| `CXDocument.ParseToml(s)` | Parse TOML into a `CXDocument` |
| `CXDocument.ParseMd(s)` | Parse Markdown into a `CXDocument` |
| `CXDocument.Loads(cxStr)` | Deserialize CX to native .NET types (`Dictionary`/`List`/scalar) |
| `CXDocument.Dumps(obj)` | Serialize native .NET types to a CX string |
| `doc.Root()` | First top-level `Element`, or `null` |
| `doc.Get(name)` | First top-level element with this name |
| `doc.At("a/b/c")` | Navigate by slash-separated path from the document root |
| `doc.FindAll(name)` | All descendant elements with this name (depth-first) |
| `doc.FindFirst(name)` | First descendant element with this name (depth-first) |
| `doc.Select(expr)` | First element matching a CXPath expression, or `null` |
| `doc.SelectAll(expr)` | All elements matching a CXPath expression (`IEnumerable<Element>`) |
| `doc.Transform(path, fn)` | Return new doc with element at path replaced by `fn(el)` |
| `doc.TransformAll(expr, fn)` | Return new doc with all elements matching CXPath replaced by `fn(el)` |
| `doc.Append(node)` | Append a top-level node |
| `doc.ToCx()` | Serialize the document back to CX |
| `doc.ToXml()` | Serialize to XML |
| `doc.ToJson()` | Serialize to JSON |
| `doc.ToYaml()` | Serialize to YAML |
| `doc.ToToml()` | Serialize to TOML |

### Document — `Element`

| Method / Property | Description |
|---|---|
| `el.Name` | Element tag name (`string`) |
| `el.Attrs` | Attribute list (`List<Attr>`) |
| `el.Items` | All child nodes (`List<Node>`) |
| `el.Attr(name)` | Attribute value by name, or `null` |
| `el.SetAttr(name, value, dataType?)` | Set or update an attribute |
| `el.RemoveAttr(name)` | Remove an attribute by name |
| `el.Children()` | Child `Element` nodes (excludes text/scalar/etc.) |
| `el.Get(name)` | First direct child element with this name |
| `el.GetAll(name)` | All direct child elements with this name |
| `el.At("a/b")` | Navigate by slash-separated path from this element |
| `el.FindAll(name)` | All descendant elements with this name (depth-first) |
| `el.FindFirst(name)` | First descendant element with this name (depth-first) |
| `el.Select(expr)` | First descendant matching a CXPath expression, or `null` |
| `el.SelectAll(expr)` | All descendants matching a CXPath expression (`IEnumerable<Element>`) |
| `el.Text()` | Concatenated text and scalar child content |
| `el.Scalar()` | Value of the first scalar child, or `null` |
| `el.Append(node)` | Append a child node |
| `el.Prepend(node)` | Prepend a child node |
| `el.Insert(index, node)` | Insert a child node at an index |
| `el.Remove(node)` | Remove a child node by identity |
| `el.RemoveAt(index)` | Remove child node at index (no-op if out of bounds) |
| `el.RemoveChild(name)` | Remove all direct child `Element`s with the given name |
| `el.ToCx()` | Emit this element as a CX string |

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

Attribute values auto-type: `true`/`false` → `bool`, integers → `long`,
decimals → `double`, everything else → `string`. An invalid expression throws
`ArgumentException`.

### Stream — `CXDocument.Stream` / `StreamEvent`

| Method / Property | Description |
|---|---|
| `CXDocument.Stream(cxStr)` | Stream CX as `List<StreamEvent>` |
| `ev.Type` | `"StartDoc"`, `"EndDoc"`, `"StartElement"`, `"EndElement"`, `"Text"`, `"Scalar"`, `"Comment"`, `"PI"`, `"EntityRef"`, `"RawText"`, `"Alias"` |
| `ev.Name` | Element name (set on `StartElement` and `EndElement`) |
| `ev.Attrs` | Attribute list (set on `StartElement`) |
| `ev.Value` | Text/scalar/entity value (set on `Text`, `Scalar`, `Comment`, `EntityRef`, `RawText`, `Alias`) |
| `ev.DataType` | Scalar type string — `"int"`, `"float"`, `"bool"`, `"null"`, `"string"` (set on `Scalar`) |
| `ev.Target` / `ev.Data` | Processing instruction fields (set on `PI`) |
| `ev.Anchor` / `ev.Merge` | Anchor and merge-key fields (set on `StartElement`) |
