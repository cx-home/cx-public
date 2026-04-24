# CX — TypeScript

TypeScript binding for the CX format library. Parses, streams, queries, and
transforms CX documents; converts between CX, XML, JSON, YAML, TOML, and
Markdown via `libcx`.

## Requirements

- **Node.js 18+**
- **V compiler** (`v`) — to build `libcx` from source
- **npm** — to install Node dependencies

## Install / Build

```sh
# 1. Build libcx (from repo root)
make -C vcx build

# 2. Install Node dependencies and compile TypeScript
cd lang/typescript/cxlib
npm install
npm run build
```

`libcx.dylib` (macOS) or `libcx.so` (Linux) is picked up automatically from
`vcx/target/`. To use a library installed elsewhere, set `LIBCX_PATH` to the
full `.dylib`/`.so` path before running.

## Quick Start

### Parse and read

```typescript
import { parse } from './src/ast';

const src = `[config version='1.0'
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]`;

const doc = parse(src);

// Navigate by path
const server = doc.at('config/server')!;
console.log(server.attr('host'));  // localhost
console.log(server.attr('port'));  // 8080

// Find all descendants named 'server'
for (const el of doc.findAll('server')) {
  console.log(el.name);
}
```

### Transform (immutable update)

`transform` and `transformAll` return a **new document** — the original is
unchanged.

```typescript
import { parse } from './src/ast';

const doc = parse(`[config
  [server host=localhost port=8080]
  [database host=db.local port=5432]
]`);

// Replace config/server — returns a new document
const updated = doc.transform('config/server', el => {
  el.setAttr('host', 'prod.example.com');
  return el;
});

console.log(updated.at('config/server')!.attr('host'));  // prod.example.com
console.log(doc.at('config/server')!.attr('host'));       // localhost  (original unchanged)

// Chain multiple transforms
const result = doc
  .transform('config/server',   el => { el.setAttr('host', 'web.example.com'); return el; })
  .transform('config/database', el => { el.setAttr('host', 'db.example.com');  return el; });

console.log(result.to_cx());
```

### CXPath: selectAll / select

`select` and `selectAll` evaluate CXPath expressions against a document or
element. Expressions support descendant axes (`//`), child paths (`a/b/c`),
wildcards (`*`), attribute predicates, boolean operators, position, and
string functions.

```typescript
import { parse } from './src/ast';

const doc = parse(`[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]`);

// First match
const first = doc.select('//service');
console.log(first!.attr('name'));  // auth

// All active services
for (const svc of doc.selectAll('//service[@active=true]')) {
  console.log(svc.attr('name'));
}
// auth
// web

// Attribute predicate with numeric comparison
const high = doc.selectAll('//service[@port>=8000]');
console.log(high.length);  // 2

// Position
const second = doc.select('//service[2]');
console.log(second!.attr('name'));  // api

// select on an Element searches only its subtree
const servicesEl = doc.at('services')!;
for (const svc of servicesEl.selectAll('service[@active=true]')) {
  console.log(svc.attr('name'));
}
```

### transformAll

`transformAll` applies a function to every element matching a CXPath
expression and returns a new document.

```typescript
import { parse } from './src/ast';

const doc = parse(`[services
  [service name=auth port=8080]
  [service name=api  port=9000]
]`);

const updated = doc.transformAll('//service', el => {
  el.setAttr('active', true);
  return el;
});

for (const svc of updated.findAll('service')) {
  console.log(svc.attr('active'));  // true
}
```

### Streaming

```typescript
import { stream } from './src/index';

const cxStr = `[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]`;

const events = stream(cxStr);
for (const event of events) {
  if (event.type === 'StartElement') {
    const attrStr = (event.attrs ?? [])
      .map(a => `${a.name}=${a.value}`)
      .join(' ');
    console.log(`${event.type} name=${event.name} ${attrStr}`.trim());
  } else {
    console.log(event.type);
  }
}
```

Expected output:

```
StartDoc
StartElement name=config version=1.0 debug=false
StartElement name=server host=localhost port=8080
EndElement
StartElement name=database url=postgres://localhost/mydb pool=10
EndElement
StartElement name=cache enabled=true ttl=300
EndElement
EndElement
EndDoc
```

## Run the Demo

```sh
# From lang/typescript/cxlib/
node_modules/.bin/tsx demo.ts
```

## API Reference

### Parse

| Function | Input | Returns |
|---|---|---|
| `parse(s)` | CX string | `Document` |
| `parseXml(s)` | XML string | `Document` |
| `parseJson(s)` | JSON string | `Document` |
| `parseYaml(s)` | YAML string | `Document` |
| `parseToml(s)` | TOML string | `Document` |
| `parseMd(s)` | Markdown string | `Document` |

### Document

| Method | Description |
|---|---|
| `doc.root()` | First top-level `Element`, or `null` |
| `doc.get(name)` | First top-level `Element` with this name, or `null` |
| `doc.at('a/b/c')` | Navigate by slash-separated path from root |
| `doc.findFirst(name)` | First matching descendant, depth-first |
| `doc.findAll(name)` | All matching descendants |
| `doc.select(expr)` | First element matching a CXPath expression |
| `doc.selectAll(expr)` | All elements matching a CXPath expression |
| `doc.transform(path, fn)` | Return new doc with element at path replaced by `fn(el)` |
| `doc.transformAll(expr, fn)` | Return new doc with all matching elements replaced |
| `doc.append(node)` | Append a top-level node |
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
| `el.getAll(name)` | All direct child `Element`s by name |
| `el.at('a/b')` | Navigate relative path from this element |
| `el.attr(name)` | Read an attribute value (`number`/`boolean`/`string`/`null`) |
| `el.text()` | Concatenated text and scalar child content |
| `el.scalar()` | Value of the first `Scalar` child, or `null` |
| `el.children()` | All direct child `Element`s |
| `el.findFirst(name)` | First matching descendant |
| `el.findAll(name)` | All matching descendants |
| `el.select(expr)` | First descendant matching a CXPath expression |
| `el.selectAll(expr)` | All descendants matching a CXPath expression |
| `el.setAttr(name, value)` | Set or update an attribute |
| `el.removeAttr(name)` | Remove an attribute |
| `el.append(node)` | Append a child node |
| `el.prepend(node)` | Insert a child node at position 0 |
| `el.insert(index, node)` | Insert a child node at a given index |
| `el.remove(node)` | Remove a child node by identity |
| `el.removeAt(index)` | Remove child node at a given index |
| `el.removeChild(name)` | Remove all direct child `Element`s with the given name |

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

Attribute values auto-type: `true`/`false` → `boolean`, integers → `number`,
decimals → `number`, everything else → `string`. An invalid expression throws
`Error`.

### Conversion

| Function | Input | Returns |
|---|---|---|
| `loads(s)` | CX string | native JS value (`object`/`array`/scalar) |
| `dumps(v)` | JS value | CX string |
| `loadsXml(s)` | XML string | native JS value |
| `loadsJson(s)` | JSON string | native JS value |
| `loadsYaml(s)` | YAML string | native JS value |
| `loadsToml(s)` | TOML string | native JS value |
| `loadsMd(s)` | Markdown string | native JS value |

### Stream

| Function | Description |
|---|---|
| `stream(s)` | Return `StreamEvent[]` for a CX string |

**`StreamEvent`** fields (present depending on event type):

| Field | Types where present |
|---|---|
| `type` | All — one of `StartDoc`, `EndDoc`, `StartElement`, `EndElement`, `Text`, `Scalar`, `Comment`, `PI`, `EntityRef`, `RawText`, `Alias` |
| `name` | `StartElement`, `EndElement` |
| `attrs` | `StartElement` — `Attr[]` with `name`, `value`, `dataType` |
| `anchor` / `dataType` / `merge` | `StartElement` |
| `value` | `Text`, `Scalar`, `Comment`, `RawText`, `EntityRef`, `Alias` |
| `target` / `data` | `PI` |

**Node types**

`TextNode(value)`, `ScalarNode(dataType, value)`, `CommentNode(value)`,
`RawTextNode(value)`, `EntityRefNode(name)`, `AliasNode(name)`,
`PINode(target, data?)`, `XMLDeclNode(version, encoding?, standalone?)`,
`CXDirectiveNode(attrs)`, `BlockContentNode(items)`, `DoctypeDeclNode(name, ...)`

## Tests

```sh
cd /path/to/cx
npx tsx lang/typescript/api_test.ts
```
