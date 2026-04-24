# CX Document API Specification
# Version: 2.0
# Date: 2026-04-23

The Document API is the uniform interface for navigating, reading, and modifying
a parsed CX tree. It is implemented identically in every language binding.

---

## Mental model

A CX document is a tree of **Elements**. Each Element has a **name**, zero or
more **attrs** (typed key-value pairs), and zero or more **items** (child nodes:
Elements, Text, Scalars, Comments, etc.).

```cx
[config
  [server host=localhost port=8080 debug=false]
  [database host=db.local port=5432]
]
```

```
Document
  └─ Element "config"
       ├─ Element "server"    attrs: host="localhost", port=8080, debug=false
       └─ Element "database"  attrs: host="db.local",  port=5432
```

### Immutability

**Documents are immutable values.** Modifying a document returns a new document.
The original is unchanged. Unchanged nodes are shared between the old and new
document — only the nodes on the path from root to the changed element are
copied. This is O(depth), not O(total nodes).

```
Before transform:                After transform:

Document                         Document' (new value)
  └─ config ──────────────────────└─ config' (new copy)
       ├─ server ──────────────────────├─ server' (new copy — changed)
       └─ database (shared) ──────────└─ database (shared — unchanged)
```

This makes Documents safe to share across threads with no locks. Multiple
threads reading or transforming the same document produce independent new
values without interference.

---

## 1 — Find

All find methods are available on both **Document** and **Element**. On Document
they search from the top level. On Element they search within that subtree.

### at(path)

The primary navigation method. A `/`-separated chain of element names, where
each segment is a direct-child lookup.

```
doc.at("config/server")          → Element "server"
doc.at("config/server/timeout")  → Element "timeout"
doc.at("config/missing")         → none
el.at("head/title")              → relative navigation from el
```

Returns the element at the path, or `none` if any step is missing. Never raises
an error on a missing path — always returns `none`.

Empty or redundant slashes are ignored: `"/config/"` is the same as `"config"`.

### get(name)

Returns the **first direct child Element** with the given name, or `none`.

```
config.get("server")    → Element "server"
config.get("missing")   → none
```

Direct children only. For any-depth search, use `find_first`.

### get_all(name)

Returns **all direct child Elements** with the given name, in document order.
Returns `[]` if none match.

```
root.get_all("item")   → [Element, Element, ...]
root.get_all("none")   → []
```

Direct children only. For any-depth search, use `find_all`.

### children()

Returns **all direct child Elements**, in document order. Excludes Text, Scalar,
Comment, and other non-Element nodes.

```
config.children()   → [Element "server", Element "database"]
```

### find_first(name)

Searches the **entire subtree** depth-first and returns the **first** matching
Element, or `none`.

```
doc.find_first("p")     → first <p> anywhere in document
el.find_first("title")  → first <title> anywhere inside el
```

Depth-first order: children are visited before their siblings. Does not include
the element itself — only its descendants are searched.

### find_all(name)

Searches the **entire subtree** depth-first and returns **all** matching
Elements, in the order encountered.

```
doc.find_all("p")    → all <p> elements, depth-first
el.find_all("item")  → all <item> elements inside el
```

Returns `[]` if none match. Does not include the element itself.

### root()

Returns the **first top-level Element** in the document, or `none` on empty
input. Available on Document only.

```
doc.root()   → Element "config"  (first element in doc.elements)
```

---

## 2 — Extract

Extraction methods read content from a single Element. All return value types —
safe to read from any number of threads simultaneously.

### attr(name)

Returns the value of the named attribute, typed, or `none` if absent.

```cx
[server host=localhost port=8080 debug=false]
```

```
el.attr("host")   → "localhost"   (string)
el.attr("port")   → 8080          (int)
el.attr("debug")  → false         (bool)
el.attr("nope")   → none
```

Values are native types: int, float, bool, null, string, date, datetime.

### text()

Returns the element's body content as a single string. Joins adjacent Text and
Scalar children with a single space. Returns `""` if the body has no text or
scalar content (e.g. only child Elements).

```cx
[h1 Introduction]       → el.text() == "Introduction"
[label 'hello world']   → el.text() == "hello world"
[section [p ...]]       → el.text() == ""
```

### scalar()

Returns the **typed value** of the first Scalar child, or `none`. Use this when
an element holds a single typed value.

```cx
[count 42]     → el.scalar() == 42      (int)
[active true]  → el.scalar() == true    (bool)
[ratio 1.5]    → el.scalar() == 1.5     (float)
[label Hello]  → el.scalar() == none    (Text node, not Scalar)
```

Unquoted body values (`42`, `true`, `1.5`) auto-type to Scalar. Quoted body
text (`'hello'`) produces a Text node — `scalar()` returns `none` for those.

---

## 3 — Mutate

There are two mutation modes with different semantics. Using the wrong one for
the wrong context is the most common source of bugs.

### Mode 1 — Build (in-place, on elements you own)

In-place methods mutate `mut` Element values directly. Use these when
**constructing** new elements before inserting them into a document.

```v
// V
mut el := cxlib.Element{ name: 'server' }
el.set_attr('host', cxlib.ScalarVal('localhost'))
el.set_attr('port', cxlib.ScalarVal(i64(8080)))
el.append(cxlib.Node(cxlib.Element{ name: 'timeout' }))
doc.append(cxlib.Node(el))
```

```python
# Python
el = Element("server")
el.set_attr("host", "localhost")
el.set_attr("port", 8080)
el.append(Element("timeout"))
doc.append(el)
```

```rust
// Rust
let mut el = Element::new("server");
el.set_attr("host", "localhost");
el.set_attr("port", 8080);
el.append(Element::new("timeout"));
doc.append(el);
```

**In-place methods on Element:**

`set_attr(name, value)` — set or update an attribute. Preserves order for
existing attributes; appends new ones.

`remove_attr(name)` — remove an attribute by name. No-op if absent.

`append(node)` — add a child node at the end.

`prepend(node)` — insert a child node at the start.

`insert(index, node)` — insert at position. Index 0 equals `prepend`.
Out-of-range indices clamp to end.

`remove_at(index)` — remove the node at this position across all node types.
No-op if out of range.

`remove_child(name)` — remove all direct child Elements with this name.
No-op if none match.

**These methods do not propagate back into a Document.** An Element extracted
from a document via `at()`, `find_first()`, etc. is a value copy. Mutating it
does not change the document. To update a document, use `transform`.

### Mode 2 — Transform (functional, on existing documents)

`transform` applies a function to the element at a given path and returns a
**new Document** with that change applied. The original document is unchanged.
Only the nodes on the path from root to the target are copied; all other nodes
are shared.

```v
// V
updated := doc.transform('config/server', fn(el cxlib.Element) cxlib.Element {
    mut e := el
    e.set_attr('host', cxlib.ScalarVal('newhost'))
    e.remove_attr('debug')
    return e
})
// doc is unchanged. updated is a new Document.
```

```python
# Python
def update_server(el):
    el.set_attr("host", "newhost")
    el.remove_attr("debug")
    return el

updated = doc.transform("config/server", update_server)
# doc is unchanged. updated is a new Document.
```

```rust
// Rust
let updated = doc.transform("config/server", |mut el| {
    el.set_attr("host", "newhost");
    el.remove_attr("debug");
    el
});
// doc is unchanged. updated is a new Document.
```

If the path does not exist, `transform` returns the original document unchanged.

**Chaining transforms:**

Since each `transform` returns a Document, changes can be composed:

```v
updated := doc
    .transform('config/server',   fn(el cxlib.Element) cxlib.Element { ... })
    .transform('config/database', fn(el cxlib.Element) cxlib.Element { ... })
```

**`transform_all(cxpath, fn)` — transform every match**

Applies the function to every element matching a CXPath expression. Returns a
new Document. Requires CXPath (see `spec/cxpath.md`).

```v
// activate all services in us region
updated := doc.transform_all('//service[@region=us]', fn(el cxlib.Element) cxlib.Element {
    mut e := el
    e.set_attr('active', cxlib.ScalarVal(true))
    return e
})
```

```python
updated = doc.transform_all('//service[@region=us]',
    lambda el: el.set_attr('active', True) or el
)
```

### Document-level append and prepend

`Document.append(node)` and `Document.prepend(node)` follow build-mode
semantics: they mutate the document in place. Use these during initial document
construction. For adding top-level elements to an existing document, use
`transform` on the root element.

---

## 4 — Missing-value contract

A missing result is always `none` / `nil` / `null` in the host language —
**never an error**. Parse errors are the only thing that can fail. Navigation
and extraction are always safe to call.

| Method               | Missing returns |
|----------------------|-----------------|
| `root()`             | `none`          |
| `get(name)`          | `none`          |
| `at(path)`           | `none`          |
| `find_first(name)`   | `none`          |
| `attr(name)`         | `none`          |
| `scalar()`           | `none`          |
| `get_all(name)`      | `[]`            |
| `find_all(name)`     | `[]`            |
| `children()`         | `[]`            |
| `text()`             | `""`            |

`transform` called with a path that does not exist returns the original document
unchanged — not an error.

---

## 5 — Direct children vs. descendants

| Method               | Scope                             |
|----------------------|-----------------------------------|
| `get(name)`          | Direct children only              |
| `get_all(name)`      | Direct children only              |
| `children()`         | Direct children only              |
| `at(path)`           | Chain of direct-child `get` calls |
| `find_first(name)`   | All descendants, depth-first      |
| `find_all(name)`     | All descendants, depth-first      |

Use `get` / `get_all` / `at` when the structure is known and the element is at
a specific position. Use `find_first` / `find_all` when searching across
variable-depth structure or when the element's position is not known.

---

## 6 — Parallel safety

Documents are immutable values. Any number of threads may read or call `select`,
`select_all`, `find_all`, `at`, and all extract methods on the same Document
simultaneously with no synchronisation.

`transform` and `transform_all` return new Documents. Threads that transform the
same source document produce independent output values — they do not interfere
with each other or with threads still reading the original.

```v
// V — parallel transforms over the same source document
results := parallels.map(regions, fn(region string) cxlib.Document {
    return doc.transform_all('//service[@region=${region}]',
        fn(el cxlib.Element) cxlib.Element {
            mut e := el
            e.set_attr('active', cxlib.ScalarVal(true))
            return e
        }
    )
})
```

---

## 7 — API surface by receiver

| Method                    | Document | Element | Returns          |
|---------------------------|----------|---------|------------------|
| `root()`                  | ✓        |         | Element or none  |
| `get(name)`               | ✓        | ✓       | Element or none  |
| `get_all(name)`           |          | ✓       | Element[]        |
| `at(path)`                | ✓        | ✓       | Element or none  |
| `find_first(name)`        | ✓        | ✓       | Element or none  |
| `find_all(name)`          | ✓        | ✓       | Element[]        |
| `children()`              |          | ✓       | Element[]        |
| `attr(name)`              |          | ✓       | value or none    |
| `text()`                  |          | ✓       | string           |
| `scalar()`                |          | ✓       | value or none    |
| `set_attr(name, val)`     |          | ✓       | — (build mode)   |
| `remove_attr(name)`       |          | ✓       | — (build mode)   |
| `append(node)`            | ✓        | ✓       | — (build mode)   |
| `prepend(node)`           | ✓        | ✓       | — (build mode)   |
| `insert(i, node)`         |          | ✓       | — (build mode)   |
| `remove_at(i)`            |          | ✓       | — (build mode)   |
| `remove_child(name)`      |          | ✓       | — (build mode)   |
| `transform(path, fn)`     | ✓        |         | Document         |
| `transform_all(expr, fn)` | ✓        |         | Document         |
