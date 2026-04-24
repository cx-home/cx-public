---
title: CX Language Guide
author: Erik
---

# CX Language Guide

CX is a **structured** markup language with *clean* bracket syntax.
It exports to XML, JSON, YAML, TOML, and **Markdown**.

## Quick Start

Install and build:

```bash
git clone https://github.com/example/cx
make build
```

Then try `cx --help` to see all options.

## Core Concepts

### Inline Formatting

Supports **bold**, *italic*, ~~strikethrough~~, ~subscript~, ^superscript^, and `inline code`.

### Lists

- Clean bracket syntax
- Typed attributes on any element
- Multiple output formats

### Ordered Steps

1. Clone the repository
2. Run make build
3. Run the tests

### Links

See the [full documentation](https://example.com/docs) for details.

---

### Tables

| Format | Input | Output |
|--------|-------|--------|
| CX     | yes   | yes    |
| XML    | yes   | yes    |
| JSON   | yes   | yes    |
| YAML   | yes   | yes    |
| TOML   | yes   | yes    |
| MD     | yes   | yes    |
