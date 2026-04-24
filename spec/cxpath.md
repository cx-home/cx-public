# CXPath Specification
# Version: 1.0
# Date: 2026-04-23

CXPath is the CX query expression language. It selects Elements from a Document
or Element tree using path steps, axis specifiers, and predicates. CXPath is to
CX what XPath is to XML — the same conceptual model, adapted for CX's typed
attribute system and bracket syntax.

CXPath expressions are passed to `select` and `select_all` methods on Document
and Element. The structural navigation API (`at`, `get`, `find_all`, etc.)
remains unchanged and is the substrate CXPath compiles down to.

---

## Conventions

- A **context node** is the Document or Element on which `select`/`select_all`
  is called. All paths are evaluated relative to it.
- CXPath selects **Elements only**. Text, Scalar, Comment, and other non-Element
  nodes are never returned.
- A missing result is `none` / `nil` from `select`, `[]` from `select_all`.
  An invalid expression is a **programming error** — implementations MUST
  panic/throw rather than return a soft error.
- Attribute values in predicates are **typed**. `true` is a bool, `8080` is an
  int, `localhost` is a string — the same auto-typing rules as the CX format.
  No silent coercion.

---

## Methods

### select(expr) → Element or none

Returns the first Element matching the expression, in depth-first document
order, or `none` if no element matches.

### select_all(expr) → Element[]

Returns all Elements matching the expression, in depth-first document order.
Returns `[]` if no element matches.

Both methods are available on **Document** and **Element**.

When called on a **Document**, the search context is the entire document.  
When called on an **Element**, the search context is that element's subtree.
The element itself is never included in results — only descendants are searched.

---

## Path syntax

A CXPath expression is a sequence of steps separated by `/`.

```
step               a single step
step/step          child of child
step//step         child, then any descendant
//step             any descendant of context (shorthand for descendant axis)
```

Each step is: `[axis] name-test [predicate]*`

### Axis

| Syntax | Meaning |
|--------|---------|
| `name` or `/name` | Direct children named `name` |
| `//name`          | All descendants named `name`, depth-first |

The leading `//` is shorthand for the descendant axis on the context node.
Within a path, `//` between two steps means "any depth between these steps":

```
config/server         → direct child named config, then its direct child server
config//p             → direct child named config, then any descendant p
//p                   → any descendant p of context
//section//p          → any descendant section, then any descendant p within each
```

### Name test

| Syntax | Meaning |
|--------|---------|
| `name` | Elements with this exact name |
| `*`    | Any element (wildcard) |

```
//service             → all service elements
//*                   → all elements at any depth
config/*              → all direct children of config
//*[@id]              → any element that has an id attr
```

---

## Predicates

A step may be followed by one or more predicates in `[...]`. All predicates
must be satisfied for an element to match.

```
//service[@active=true]                  one predicate
//service[@active=true][@region=us]      two predicates (both required)
//service[@active=true and @region=us]   same — and within one predicate
```

### Attribute comparison

```
[@name]              attr exists (any value)
[@name=value]        attr equals value
[@name!=value]       attr does not equal value
[@name>value]        attr greater than value  (numeric)
[@name<value]        attr less than value     (numeric)
[@name>=value]       attr greater than or equal
[@name<=value]       attr less than or equal
```

Values follow CX auto-typing:

| Written | Type   |
|---------|--------|
| `true` / `false` | bool |
| `42`, `-7`       | int  |
| `3.14`           | float |
| `null`           | null  |
| `localhost`, `'hello world'` | string |

String values that contain spaces or special characters must be quoted with
single quotes. Simple strings (letters, digits, hyphens, underscores, dots)
may be unquoted.

```
[@name=auth]               string "auth"
[@name='hello world']      string with space — must quote
[@port=8080]               int 8080
[@active=true]             bool true
[@ratio=1.5]               float 1.5
[@region!=eu]              not equal
[@port>=8000]              numeric range
```

Comparison operators `>`, `<`, `>=`, `<=` require both sides to be numeric.
Comparing a string attribute with a numeric literal produces a panic.

### Boolean operators

`and` and `or` combine conditions within a predicate. `and` binds tighter
than `or`.

```
[@active=true and @region=us]
[@port=80 or @port=443]
[@active=true and (@region=us or @region=eu)]
```

### not()

```
[not(@active=false)]     elements where active is not false
[not(@debug)]            elements without a debug attr
```

### Child existence

A bare name (no `@`) tests whether a direct child element with that name exists.

```
[meta]                   has a child named meta
[not(meta)]              does not have a child named meta
```

### Position

Position predicates select by index among the matched elements at that step,
in document order. Positions are **1-based**.

```
[1]                      first match
[2]                      second match
[last()]                 last match
```

```
//item[1]                first item descendant
//item[last()]           last item descendant
config/*[1]              first direct child of config (any name)
```

### Functions

| Function | Tests |
|----------|-------|
| `contains(@k, val)`    | attr value contains the string val |
| `starts-with(@k, val)` | attr value starts with the string val |
| `not(expr)`            | negates any predicate expression |

```
//p[contains(@class, note)]         class attr contains "note"
//service[starts-with(@name, auth)] name starts with "auth"
//item[not(contains(@tags, beta))]  tags does not contain "beta"
```

---

## Examples

```cx
[services
  [service name=auth  port=8080 active=true  region=us
    [tags :string[] core internal]
  ]
  [service name=api   port=9000 active=false region=eu]
  [service name=web   port=80   active=true  region=us
    [tags :string[] public]
  ]
]
[docs
  [section id=intro
    [h1 Introduction]
    [p class=lead First paragraph.]
    [p Second paragraph.]
  ]
  [section id=detail
    [h2 Details]
    [p class=note A note.]
  ]
]
```

```
// All active services
doc.select_all("//service[@active=true]")
→ [service name=auth ..., service name=web ...]

// First active service
doc.select("//service[@active=true]")
→ service name=auth ...

// Services in us region with port over 8000
doc.select_all("//service[@region=us and @port>8000]")
→ [service name=auth ...]

// Service named exactly "api"
doc.select("//service[@name=api]")
→ service name=api ...

// Any element that has an id attribute
doc.select_all("//*[@id]")
→ [section id=intro, section id=detail]

// All p elements inside any section
doc.select_all("//section//p")
→ [p class=lead ..., p ..., p class=note ...]

// Only p elements with class=note
doc.select_all("//p[@class=note]")
→ [p class=note A note.]

// Paragraphs that contain "lead" in their class
doc.select_all("//p[contains(@class, lead)]")
→ [p class=lead ...]

// Services that have a tags child
doc.select_all("//service[tags]")
→ [service name=auth ..., service name=web ...]

// First direct child of services (any name)
doc.select("services/*[1]")
→ service name=auth ...

// All direct children of any section
doc.select_all("//section/*")
→ [h1, p, p, h2, p]

// Select relative to an element
services := doc.at("services") or { return }
services.select_all("service[@active=true]")
→ [service name=auth ..., service name=web ...]
```

---

## Relation to structural API

CXPath expressions without predicates or `//` are equivalent to the structural
API. Implementations MAY optimise these to direct structural calls.

| CXPath expression    | Structural equivalent          |
|----------------------|--------------------------------|
| `name`               | `get(name)`                    |
| `a/b/c`              | `at("a/b/c")`                  |
| `//name`             | `find_all(name)` / `find_first(name)` |
| `//name[1]`          | `find_first(name)`             |
| `*`                  | `children()`                   |

---

## Error contract

**Invalid expression** — any syntax error in the CXPath string is a programming
error. Implementations MUST panic or raise an unrecoverable exception. CXPath
expressions are always program literals, never user-supplied data.

**No match** — not an error. `select` returns `none`, `select_all` returns `[]`.

**Type mismatch in predicate** — comparing a string attribute with `<`, `>`,
`<=`, `>=` is a programming error. Implementations MUST panic.

---

## v1 scope

### In scope

- Descendant axis (`//name`, `a//b`)
- Direct child axis (`name`, `a/b/c`)
- Wildcard name test (`*`)
- Attribute predicates — existence, equality, inequality, numeric comparisons
- Boolean operators — `and`, `or`, `not()`
- Child existence predicate (`[name]`)
- Position predicates — `[n]`, `[last()]`
- String functions — `contains()`, `starts-with()`
- Relative evaluation — `select` / `select_all` on Element as well as Document

### Deferred

**Parent and sibling axes** — `parent::`, `ancestor::`, `following-sibling::`,
`preceding-sibling::` require upward traversal context.

Documents are immutable values (see `spec/api.md` §Immutability). Elements have
no `parent` field and are not connected to the tree after extraction. Parent and
sibling context is available to the CXPath evaluator during traversal — it
threads a parent stack internally — so these axes work correctly inside
expressions. They are not available as standalone API calls outside of
evaluation.

```
//p[parent::section]                  works — evaluator has context
//h2/following-sibling::p             works — evaluator has sibling list
el.parent()                           does not exist — Elements are values
```

No AST changes required. Deferred to v2.

**Attribute as path endpoint** — `config/server/@port` returning the attribute
value `8080` directly rather than an Element. Deferred to v2 alongside a typed
return variant of `select`.

**Union operator** — `//p | //li` combining two expressions. Deferred.

**XQuery / FLWOR** — `for`/`let`/`where`/`return` expressions, aggregates
(`count()`, `sum()`), transforms. Out of scope for CXPath — separate spec if
pursued.
