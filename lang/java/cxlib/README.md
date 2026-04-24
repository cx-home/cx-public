# CX — Java

Java binding for the [CX](https://github.com/cx-home/cx) format library via JNA.
Parse, query, mutate, stream, and convert CX/XML/JSON/YAML/TOML/Markdown — all from Java.

## Requirements

- **Java 21+** (the library uses sealed types and pattern matching)
- **Maven 3.8+**
- **libcx** built or installed (see below)

## Install / Build

### 1. Build libcx

From the repo root, build the native shared library:

```sh
make build-vcx          # produces vcx/target/libcx.dylib (macOS) or vcx/target/libcx.so (Linux)
```

Optionally install it system-wide so any project on the machine can find it:

```sh
sudo make install       # installs to /usr/local/lib/libcx.{dylib,so}
```

The Java binding automatically searches these locations (in order):

1. `LIBCX_PATH` environment variable — exact path to the library file
2. `LIBCX_LIB_DIR` environment variable — directory containing `libcx.dylib` / `libcx.so`
3. System paths: `/usr/local/lib`, `/opt/homebrew/lib`, `/usr/lib`, …
4. Repo-relative fallback: `vcx/target/libcx.dylib` (used during development)

### 2. Build the JAR

From the repo root:

```sh
mvn -f lang/java/cxlib/pom.xml package -DskipTests
```

To also install into your local Maven repository (`~/.m2`):

```sh
mvn -f lang/java/cxlib/pom.xml install -DskipTests
```

Then declare the dependency in your own project's `pom.xml`:

```xml
<dependency>
  <groupId>io.cxhome</groupId>
  <artifactId>cxlib</artifactId>
  <version>0.5.0</version>
</dependency>
```

## Quick Start

### Document Model

Parse a CX document into a live tree, read attributes, update values, add and remove
elements, then serialize back to CX.

```java
import cx.CXDocument;
import cx.Element;
import cx.ScalarNode;

String cxStr = """
    [config version='1.0' debug=false
      [server host=localhost port=8080]
      [database url='postgres://localhost/mydb' pool=10]
      [cache enabled=true ttl=300]
    ]""";

// 1. Parse
CXDocument doc = CXDocument.parse(cxStr);

// 2. Read — navigate to server, print attrs
Element server = doc.at("config/server");
System.out.println(server.attr("host"));   // localhost
System.out.println(server.attr("port"));   // 8080

// 3. Update — change host
server.setAttr("host", "prod.example.com");

// 4. Create — append a timeout child to server
Element timeout = new Element("timeout");
timeout.items.add(new ScalarNode("int", 30L));
server.append(timeout);

// 5. Delete — remove the cache child from config
Element config = doc.root();
config.remove(config.get("cache"));

// 6. Emit as CX
System.out.println(doc.toCx());
```

Expected output:

```
[config version='1.0' debug=false
  [server host=prod.example.com port=8080
    [timeout 30]
  ]
  [database url=postgres://localhost/mydb pool=10]
]
```

### Streaming

Use `CXDocument.stream()` for a SAX-like event stream — useful for large documents or
when you only need to inspect specific events.

```java
import cx.CXDocument;
import cx.StreamEvent;
import java.util.List;

String cxStr = """
    [config version='1.0' debug=false
      [server host=localhost port=8080]
      [database url='postgres://localhost/mydb' pool=10]
      [cache enabled=true ttl=300]
    ]""";

List<StreamEvent> events = CXDocument.stream(cxStr);
for (StreamEvent ev : events) {
    System.out.print("event: " + ev.type);
    if ("StartElement".equals(ev.type)) {
        System.out.print("  name=" + ev.name);
        if (ev.attrs != null) {
            ev.attrs.forEach(a -> System.out.print("  " + a.name + "=" + a.value));
        }
    }
    System.out.println();
}
```

Expected output:

```
event: StartDoc
event: StartElement  name=config  version=1.0  debug=false
event: StartElement  name=server  host=localhost  port=8080
event: EndElement
event: StartElement  name=database  url=postgres://localhost/mydb  pool=10
event: EndElement
event: StartElement  name=cache  enabled=true  ttl=300
event: EndElement
event: EndElement
event: EndDoc
```

## Run the Demo

The repo ships a runnable `Demo` class that exercises both the document model and
streaming APIs using the snippets above.

```sh
# From the repo root — build (skipping tests), then run
mvn -f lang/java/cxlib/pom.xml package -DskipTests
mvn -f lang/java/cxlib/pom.xml exec:java -Dexec.mainClass=cx.Demo
```

If libcx is not on a standard system path, point to it explicitly:

```sh
LIBCX_PATH=/path/to/libcx.dylib \
  mvn -f lang/java/cxlib/pom.xml exec:java -Dexec.mainClass=cx.Demo
```

To run the more extensive format-conversion example (`Transform`):

```sh
mvn -f lang/java/cxlib/pom.xml exec:java -Dexec.mainClass=cx.examples.Transform
```

## API Reference

### Conversion — `CxLib`

| Method | Input | Returns |
|---|---|---|
| `CxLib.toCx(s)` | CX string | canonical CX |
| `CxLib.toCxCompact(s)` | CX string | compact CX |
| `CxLib.toXml(s)` | CX string | XML |
| `CxLib.toJson(s)` | CX string | JSON |
| `CxLib.toYaml(s)` | CX string | YAML |
| `CxLib.toToml(s)` | CX string | TOML |
| `CxLib.toMd(s)` | CX string | Markdown |
| `CxLib.xmlToCx(s)` | XML string | CX |
| `CxLib.jsonToCx(s)` | JSON string | CX |
| `CxLib.yamlToCx(s)` | YAML string | CX |
| `CxLib.tomlToCx(s)` | TOML string | CX |
| `CxLib.mdToCx(s)` | Markdown string | CX |
| `CxLib.version()` | — | version string |

All `xmlTo*`, `jsonTo*`, `yamlTo*`, `tomlTo*`, `mdTo*` cross-format variants are also available.

### Document — `CXDocument`

| Method | Description |
|---|---|
| `CXDocument.parse(s)` | Parse CX string → `CXDocument` |
| `CXDocument.parseXml(s)` | Parse XML string → `CXDocument` |
| `CXDocument.parseJson(s)` | Parse JSON string → `CXDocument` |
| `CXDocument.parseYaml(s)` | Parse YAML string → `CXDocument` |
| `CXDocument.parseToml(s)` | Parse TOML string → `CXDocument` |
| `CXDocument.parseMd(s)` | Parse Markdown string → `CXDocument` |
| `doc.root()` | First top-level `Element` |
| `doc.get(name)` | First top-level element by name |
| `doc.at("a/b/c")` | Navigate by slash-separated path from root |
| `doc.findAll(name)` | All descendant elements by name (depth-first) |
| `doc.findFirst(name)` | First descendant element by name |
| `doc.select(expr)` | First element matching a CXPath expression |
| `doc.selectAll(expr)` | All elements matching a CXPath expression |
| `doc.transform(path, fn)` | Return new document with element at path replaced by `fn.apply(el)` |
| `doc.transformAll(expr, fn)` | Return new document with all matching elements replaced |
| `doc.append(node)` | Add a top-level node |
| `doc.toCx()` | Emit document as CX string |
| `doc.toXml()` / `toJson()` / `toYaml()` / `toToml()` / `toMd()` | Convert document |
| `CXDocument.loads(s)` | Deserialize CX data string → `Map`/`List`/scalar |
| `CXDocument.dumps(data)` | Serialize Java object → CX string |

### Document — `Element`

| Method | Description |
|---|---|
| `el.attr(name)` | Attribute value by name (`String`/`Long`/`Double`/`Boolean`/`null`) |
| `el.setAttr(name, value)` | Set or update a string attribute |
| `el.setAttr(name, value, dataType)` | Set or update a typed attribute (`"int"`, `"float"`, `"bool"`) |
| `el.removeAttr(name)` | Remove an attribute |
| `el.text()` | Concatenated text/scalar child content |
| `el.scalar()` | Value of the first scalar child |
| `el.children()` | All direct child `Element`s |
| `el.get(name)` | First direct child element by name |
| `el.getAll(name)` | All direct child elements by name |
| `el.at("a/b")` | Navigate by slash-separated path |
| `el.findAll(name)` | All descendant elements by name (depth-first) |
| `el.findFirst(name)` | First descendant element by name |
| `el.select(expr)` | First descendant matching a CXPath expression |
| `el.selectAll(expr)` | All descendants matching a CXPath expression |
| `el.append(node)` | Append a child node |
| `el.prepend(node)` | Prepend a child node |
| `el.insert(index, node)` | Insert a child node at index |
| `el.remove(node)` | Remove a child node by identity |
| `el.removeChild(name)` | Remove all direct child elements with the given name |
| `el.removeAt(index)` | Remove child node at index (no-op if out of bounds) |
| `el.toCx()` | Emit element as CX string |

### CXPath expressions

| Syntax | Matches |
|---|---|
| `//name` | All descendants named `name` |
| `a/b/c` | Child path |
| `*` | Any element (wildcard) |
| `[@attr]` | Has attribute |
| `[@attr=val]` | Attribute equals value (auto-typed) |
| `[@attr!=val]` | Attribute not equal |
| `[@attr>=val]` | Numeric comparison (`>`, `<`, `>=`, `<=`) |
| `[@a=x and @b=y]` | Boolean `and` / `or` |
| `[not(@attr)]` | Negation |
| `[childname]` | Has a direct child element named `childname` |
| `[1]`, `[2]`, `[last()]` | Position (1-based) |
| `[contains(@k, v)]` | Attribute contains substring |
| `[starts-with(@k, v)]` | Attribute starts with prefix |

Attribute values auto-type: `true`/`false` → `Boolean`, integers → `Long`,
decimals → `Double`, everything else → `String`. An invalid expression throws
`IllegalArgumentException`.

### Stream — `CXDocument.stream` / `StreamEvent`

| Method / Field | Description |
|---|---|
| `CXDocument.stream(s)` | Stream CX string → `List<StreamEvent>` |
| `ev.type` | Event type: `StartDoc`, `EndDoc`, `StartElement`, `EndElement`, `Text`, `Scalar`, `Comment`, `PI`, `EntityRef`, `RawText`, `Alias` |
| `ev.name` | Element name (`StartElement`, `EndElement`) |
| `ev.attrs` | Attribute list (`StartElement`) |
| `ev.value` | Text/scalar/comment value |
| `ev.dataType` | Type annotation (`StartElement`, `Scalar`) |
| `ev.anchor` | Anchor name (`StartElement`) |
| `ev.target` / `ev.data` | PI target and data |

## Tests

```sh
make test-java
```
