# CX — Kotlin

Kotlin binding for the CX format library via JNA.  Parses, streams, queries,
transforms, and converts CX / XML / JSON / YAML / TOML / Markdown.

---

## Requirements

| Tool | Minimum version |
|---|---|
| JDK | 21 |
| Gradle | 8 |
| `kotlinc` | 2.x (only needed to compile standalone demos) |

Gradle downloads Kotlin automatically; you only need `kotlinc` on your `PATH`
if you want to compile and run demo files outside of Gradle.

---

## Install / Build

### 1. Build `libcx` (native library)

From the **repository root**:

```sh
make build
```

This compiles `vcx/target/libcx.dylib` (macOS) or `vcx/target/libcx.so`
(Linux) and builds all language bindings including the Kotlin jar.

To install `libcx` system-wide so no environment variable is needed at
runtime:

```sh
sudo make install        # installs to /usr/local/lib/libcx.dylib
```

### 2. Build the Kotlin jar

If you did not run `make build` above, build the jar and its runtime
dependencies from `lang/kotlin/cxlib/`:

```sh
cd lang/kotlin/cxlib
gradle assemble installDist
```

`gradle installDist` copies the jar and all dependency jars into
`build/install/cxlib/lib/`, which is what the demo commands below use as the
classpath.

---

## Quick Start

All commands in this section are run from `lang/kotlin/cxlib/`.

### Document Model

```kotlin
import cx.CXDocument
import cx.Element
import cx.Attr

fun main() {
    val cxStr = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
""".trimIndent()

    val doc = CXDocument.parse(cxStr)

    // Read — navigate to server and inspect attributes
    val server = doc.at("config/server")!!
    println("host: ${server.attr("host")}")   // host: localhost
    println("port: ${server.attr("port")}")   // port: 8080

    // Update — change host in-place
    server.setAttr("host", "prod.example.com")

    // Create — add a timeout child element to server
    server.append(Element(
        name  = "timeout",
        attrs = mutableListOf(Attr("seconds", 30L, "int")),
    ))

    // Delete — remove the cache element from config
    val config = doc.root()!!
    config.remove(config.get("cache")!!)

    // Serialize back to CX
    println()
    println(doc.toCx())
}
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

### CXPath: select and transform

`select` and `selectAll` evaluate CXPath expressions against a document or
element.  `transform` and `transformAll` return a **new document** — the
original is unchanged.

```kotlin
import cx.CXDocument

fun main() {
    val cxStr = """
[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]
""".trimIndent()

    val doc = CXDocument.parse(cxStr)

    // First match
    val first = doc.select("//service")
    println(first?.attr("name"))   // auth

    // All active services
    for (svc in doc.selectAll("//service[@active=true]")) {
        println(svc.attr("name"))
    }
    // auth
    // web

    // Numeric comparison
    val high = doc.selectAll("//service[@port>=8000]")
    println(high.size)   // 2

    // Position
    val second = doc.select("//service[2]")
    println(second?.attr("name"))   // api

    // transform: returns new document, original unchanged
    val updated = doc.transform("services/service") { el ->
        el.setAttr("region", "us-east")
        el
    }
    println(updated.at("services/service")!!.attr("region"))  // us-east
    println(doc.at("services/service")!!.attr("region"))      // null

    // transformAll: apply to every matching element
    val activated = doc.transformAll("//service[@active=false]") { el ->
        el.setAttr("active", true)
        el
    }
    println(activated.findAll("service").all { it.attr("active") == true })  // true
}
```

### Streaming

```kotlin
import cx.CXDocument

fun main() {
    val cxStr = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
""".trimIndent()

    CXDocument.stream(cxStr).forEach { ev ->
        if (ev.type == "StartElement") {
            val attrs = ev.attrs.joinToString(" ") { "${it.name}=${it.value}" }
            println("${ev.type}  name=${ev.name}  attrs=[$attrs]")
        } else {
            println(ev.type)
        }
    }
}
```

Expected output:

```
StartDoc
StartElement  name=config  attrs=[version=1.0 debug=false]
StartElement  name=server  attrs=[host=localhost port=8080]
EndElement
StartElement  name=database  attrs=[url=postgres://localhost/mydb pool=10]
EndElement
StartElement  name=cache  attrs=[enabled=true ttl=300]
EndElement
EndElement
EndDoc
```

---

## Run the Demo

### Bundled Transform example

The project ships a comprehensive format-conversion demo (`Transform.kt`) that
reads CX, XML, JSON, YAML, TOML, and Markdown example files and prints each
conversion.  Run it from `lang/kotlin/cxlib/`:

```sh
gradle run
```

Or from the repository root:

```sh
make example-kotlin
```

### Document model + streaming demo

1. Copy both code snippets above into `Demo.kt` (combine the two `main`
   functions, or keep them separate and adjust the class name).

   A ready-to-run combined version is below — save it anywhere as `Demo.kt`:

```kotlin
import cx.CXDocument
import cx.Element
import cx.Attr

fun main() {
    val cxStr = """
[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]
""".trimIndent()

    // ── Document model ────────────────────────────────────────────────────
    val doc    = CXDocument.parse(cxStr)
    val server = doc.at("config/server")!!

    println("host: ${server.attr("host")}")
    println("port: ${server.attr("port")}")

    server.setAttr("host", "prod.example.com")
    server.append(Element(name = "timeout", attrs = mutableListOf(Attr("seconds", 30L, "int"))))
    doc.root()!!.remove(doc.root()!!.get("cache")!!)

    println()
    println(doc.toCx())

    // ── Streaming ─────────────────────────────────────────────────────────
    println("── Stream events ──")
    CXDocument.stream(cxStr).forEach { ev ->
        if (ev.type == "StartElement") {
            val attrs = ev.attrs.joinToString(" ") { "${it.name}=${it.value}" }
            println("${ev.type}  name=${ev.name}  attrs=[$attrs]")
        } else {
            println(ev.type)
        }
    }
}
```

2. From `lang/kotlin/cxlib/`, compile and run:

```sh
# Collect the dependency jars (all in one directory after installDist)
LIBS=build/install/cxlib/lib
CP=$(echo $LIBS/*.jar | tr ' ' ':')

# Compile
kotlinc -cp "$CP" Demo.kt -include-runtime -d demo.jar

# Run — JAVA must be JDK 21+.
# If `java -version` reports 21+, use it directly.
# Otherwise point JAVA_HOME at your JDK 21 installation, e.g.:
#   macOS (Homebrew): export JAVA_HOME=$(/usr/libexec/java_home -v 21)
#   Linux:            export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java

# If libcx is installed system-wide (sudo make install), omit LIBCX_PATH
LIBCX_PATH="$(pwd)/../../../vcx/target/libcx.dylib" \
$JAVA --enable-native-access=ALL-UNNAMED -cp "$CP:demo.jar" DemoKt
```

On Linux, replace `libcx.dylib` with `libcx.so`.

> **Note on `--enable-native-access`:** JNA loads `libcx` as a native library.
> Java 21+ prints a warning unless `--enable-native-access=ALL-UNNAMED` is
> passed.  The flag is harmless; Gradle suppresses it automatically when running
> tests and examples via `gradle run`.

---

## API Reference

### Conversion — `CxLib`

| Method | Input | Returns |
|---|---|---|
| `CxLib.toCx(s)` | CX string | canonical CX string |
| `CxLib.toCxCompact(s)` | CX string | compact (single-line) CX |
| `CxLib.toXml(s)` | CX string | XML string |
| `CxLib.toJson(s)` | CX string | JSON string |
| `CxLib.toYaml(s)` | CX string | YAML string |
| `CxLib.toToml(s)` | CX string | TOML string |
| `CxLib.toMd(s)` | CX string | Markdown string |
| `CxLib.xmlToCx(s)` | XML string | CX string |
| `CxLib.jsonToCx(s)` | JSON string | CX string |
| `CxLib.yamlToCx(s)` | YAML string | CX string |
| `CxLib.tomlToCx(s)` | TOML string | CX string |
| `CxLib.mdToCx(s)` | Markdown string | CX string |
| `CxLib.version()` | — | library version string |
| `CxLib.astBin(s)` | CX string | binary-encoded AST (`ByteArray`) |
| `CxLib.eventsBin(s)` | CX string | binary-encoded event stream (`ByteArray`) |

Cross-format helpers follow the same `<from>To<To>` pattern:
`xmlToJson`, `jsonToYaml`, `yamlToToml`, `tomlToXml`, etc.

### Document — `CXDocument`

| Method | Description |
|---|---|
| `CXDocument.parse(s)` | Parse a CX string into a `CXDocument` |
| `CXDocument.parseXml(s)` | Parse XML into a `CXDocument` |
| `CXDocument.parseJson(s)` | Parse JSON into a `CXDocument` |
| `CXDocument.parseYaml(s)` | Parse YAML into a `CXDocument` |
| `CXDocument.parseToml(s)` | Parse TOML into a `CXDocument` |
| `CXDocument.parseMd(s)` | Parse Markdown into a `CXDocument` |
| `CXDocument.stream(s)` | Stream CX as `List<StreamEvent>` |
| `CXDocument.loads(s)` | Parse CX and return a native Kotlin value (`Map`/`List`/scalar) |
| `CXDocument.dumps(v)` | Serialize a Kotlin value to a CX string |
| `doc.root()` | First top-level `Element`, or `null` |
| `doc.get(name)` | First top-level element with the given name |
| `doc.at(path)` | Navigate by `/`-separated path (e.g. `"config/server"`) |
| `doc.findAll(name)` | All elements with the given name, depth-first |
| `doc.findFirst(name)` | First element with the given name, depth-first |
| `doc.append(node)` | Append a node at the document level |
| `doc.prepend(node)` | Prepend a node at the document level |
| `doc.select(expr)` | First element matching a CXPath expression |
| `doc.selectAll(expr)` | All elements matching a CXPath expression |
| `doc.transform(path, fn)` | Return new doc with element at path replaced by `fn(el)` |
| `doc.transformAll(expr, fn)` | Return new doc with all matching elements replaced |
| `doc.toCx()` | Serialize back to a CX string |
| `doc.toXml()` / `toJson()` / `toYaml()` / `toToml()` / `toMd()` | Convert to other formats |

### Element (navigation and mutation)

| Method | Description |
|---|---|
| `el.name` | Element tag name |
| `el.attrs` | `MutableList<Attr>` — all attributes |
| `el.items` | `MutableList<Node>` — all child nodes (elements, text, …) |
| `el.attr(name)` | Attribute value (`String`, `Long`, `Double`, `Boolean`, or `null`) |
| `el.setAttr(name, value, dataType?)` | Set or update an attribute |
| `el.removeAttr(name)` | Remove an attribute by name |
| `el.children()` | Direct child `Element`s (excludes text/comment nodes) |
| `el.get(name)` | First direct child element with the given name |
| `el.getAll(name)` | All direct child elements with the given name |
| `el.at(path)` | Navigate by `/`-separated path relative to this element |
| `el.findFirst(name)` | First descendant element with the given name |
| `el.findAll(name)` | All descendant elements with the given name |
| `el.select(expr)` | First descendant matching a CXPath expression |
| `el.selectAll(expr)` | All descendants matching a CXPath expression |
| `el.text()` | Concatenated text content of direct text/scalar children |
| `el.scalar()` | Scalar value of the first `ScalarNode` child, or `null` |
| `el.append(node)` | Append a child node |
| `el.prepend(node)` | Prepend a child node |
| `el.insert(index, node)` | Insert a child node at the given index |
| `el.remove(node)` | Remove a child node (by identity) |
| `el.removeChild(name)` | Remove all direct child `Element`s with the given name |
| `el.removeAt(index)` | Remove the child node at the given index |
| `el.toCx()` | Serialize this element subtree to a CX string |

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

Attribute values auto-type: `true`/`false` → `Boolean`, integers → `Long`,
decimals → `Double`, everything else → `String`. An invalid expression throws
`IllegalArgumentException`.

### Stream — `StreamEvent`

| Field | Type | Description |
|---|---|---|
| `type` | `String` | Event kind: `StartDoc`, `EndDoc`, `StartElement`, `EndElement`, `Text`, `Scalar`, `Comment`, `PI`, `EntityRef`, `RawText`, `Alias` |
| `name` | `String?` | Element name (for `StartElement` / `EndElement`) |
| `attrs` | `List<Attr>` | Attributes (for `StartElement`) |
| `value` | `Any?` | Typed scalar or text value |
| `dataType` | `String?` | Scalar type: `"int"`, `"float"`, `"bool"`, `"null"`, `"string"` |
| `anchor` | `String?` | YAML-style anchor name |
| `target` | `String?` | Processing-instruction target |
| `data` | `String?` | Processing-instruction data |

---

## Tests

From the repository root:

```sh
make test-kotlin
```

Or from `lang/kotlin/cxlib/`:

```sh
gradle test
```
