"""CX native AST types — parse, emit, and query."""
from __future__ import annotations
import json
import re
from dataclasses import dataclass, field
from typing import Any, Optional, Union
from . import cx as _cx


# ── Node types ────────────────────────────────────────────────────────────────

@dataclass
class Attr:
    name: str
    value: Any          # str | int | float | bool | None
    data_type: Optional[str] = None  # None means string (omitted in JSON)


@dataclass
class Text:
    value: str


@dataclass
class Scalar:
    data_type: str      # int | float | bool | null | string | date | datetime | bytes
    value: Any          # native Python value


@dataclass
class Comment:
    value: str


@dataclass
class RawText:
    value: str


@dataclass
class EntityRef:
    name: str


@dataclass
class Alias:
    name: str


@dataclass
class PI:
    target: str
    data: Optional[str] = None


@dataclass
class XMLDecl:
    version: str = "1.0"
    encoding: Optional[str] = None
    standalone: Optional[str] = None


@dataclass
class CXDirective:
    attrs: list[Attr] = field(default_factory=list)


@dataclass
class BlockContent:
    items: list["Node"] = field(default_factory=list)


@dataclass
class DoctypeDecl:
    name: str
    external_id: Optional[dict] = None
    int_subset: list = field(default_factory=list)


@dataclass
class Element:
    name: str
    anchor: Optional[str] = None
    merge: Optional[str] = None
    data_type: Optional[str] = None  # TypeAnnotation e.g. "int[]"
    attrs: list[Attr] = field(default_factory=list)
    items: list["Node"] = field(default_factory=list)

    def get(self, name: str) -> Optional["Element"]:
        """First child Element with this name."""
        for item in self.items:
            if isinstance(item, Element) and item.name == name:
                return item
        return None

    def get_all(self, name: str) -> list["Element"]:
        """All child Elements with this name."""
        return [i for i in self.items if isinstance(i, Element) and i.name == name]

    def attr(self, name: str) -> Any:
        """Attribute value by name, or None."""
        for a in self.attrs:
            if a.name == name:
                return a.value
        return None

    def text(self) -> str:
        """Concatenated Text and Scalar child content."""
        parts = []
        for item in self.items:
            if isinstance(item, Text):
                parts.append(item.value)
            elif isinstance(item, Scalar):
                parts.append("null" if item.value is None else str(item.value))
        return " ".join(parts)

    def scalar(self) -> Any:
        """Value of first Scalar child, or None."""
        for item in self.items:
            if isinstance(item, Scalar):
                return item.value
        return None

    def children(self) -> list["Element"]:
        """All child Elements (excludes Text, Scalar, and other nodes)."""
        return [i for i in self.items if isinstance(i, Element)]

    def find_all(self, name: str) -> list["Element"]:
        """All descendant Elements with this name (depth-first)."""
        result = []
        for item in self.items:
            if isinstance(item, Element):
                if item.name == name:
                    result.append(item)
                result.extend(item.find_all(name))
        return result

    def find_first(self, name: str) -> Optional["Element"]:
        """First descendant Element with this name (depth-first)."""
        for item in self.items:
            if isinstance(item, Element):
                if item.name == name:
                    return item
                found = item.find_first(name)
                if found is not None:
                    return found
        return None

    def at(self, path: str) -> Optional["Element"]:
        """Navigate by slash-separated path: el.at('server/host')."""
        parts = [p for p in path.split('/') if p]
        cur: Optional[Element] = self
        for part in parts:
            if cur is None:
                return None
            cur = cur.get(part)
        return cur

    def append(self, node: "Node") -> None:
        """Append a child node."""
        self.items.append(node)

    def prepend(self, node: "Node") -> None:
        """Prepend a child node."""
        self.items.insert(0, node)

    def insert(self, index: int, node: "Node") -> None:
        """Insert a child node at index."""
        self.items.insert(index, node)

    def remove(self, node: "Node") -> None:
        """Remove a child node by identity."""
        self.items = [i for i in self.items if i is not node]

    def remove_child(self, name: str) -> None:
        """Remove all direct child Elements with the given name."""
        self.items = [i for i in self.items if not (isinstance(i, Element) and i.name == name)]

    def remove_at(self, index: int) -> None:
        """Remove child node at index; no-op if index is out of bounds."""
        if 0 <= index < len(self.items):
            self.items = self.items[:index] + self.items[index + 1:]

    def select(self, expr: str) -> Optional["Element"]:
        """First descendant matching a CXPath expression (excludes self)."""
        results = self.select_all(expr)
        return results[0] if results else None

    def select_all(self, expr: str) -> list["Element"]:
        """All descendants matching a CXPath expression (excludes self), depth-first."""
        from .cxpath import cxpath_parse, collect_step
        cx_expr = cxpath_parse(expr)
        result: list[Element] = []
        collect_step(self, cx_expr, 0, result)
        return result

    def set_attr(self, name: str, value: Any, data_type: Optional[str] = None) -> None:
        """Set an attribute value, updating if it already exists."""
        for a in self.attrs:
            if a.name == name:
                a.value = value
                a.data_type = data_type
                return
        self.attrs.append(Attr(name, value, data_type))

    def remove_attr(self, name: str) -> None:
        """Remove an attribute by name."""
        self.attrs = [a for a in self.attrs if a.name != name]


Node = Union[
    Element, Text, Scalar, Comment, RawText, EntityRef, BlockContent,
    Alias, PI, XMLDecl, CXDirective, DoctypeDecl,
]


@dataclass
class Document:
    elements: list[Node] = field(default_factory=list)
    prolog: list[Node] = field(default_factory=list)
    doctype: Optional[DoctypeDecl] = None

    def root(self) -> Optional[Element]:
        """First top-level Element."""
        for e in self.elements:
            if isinstance(e, Element):
                return e
        return None

    def get(self, name: str) -> Optional[Element]:
        """First top-level Element with this name."""
        for e in self.elements:
            if isinstance(e, Element) and e.name == name:
                return e
        return None

    def at(self, path: str) -> Optional[Element]:
        """Navigate by slash-separated path from root: doc.at('article/body/p')."""
        parts = [p for p in path.split('/') if p]
        if not parts:
            return self.root()
        cur = self.get(parts[0])
        if cur is None or len(parts) == 1:
            return cur
        return cur.at('/'.join(parts[1:]))

    def find_all(self, name: str) -> list[Element]:
        """All descendant Elements with this name (depth-first through entire document)."""
        result = []
        for e in self.elements:
            if isinstance(e, Element):
                if e.name == name:
                    result.append(e)
                result.extend(e.find_all(name))
        return result

    def find_first(self, name: str) -> Optional[Element]:
        """First descendant Element with this name (depth-first through entire document)."""
        for e in self.elements:
            if isinstance(e, Element):
                if e.name == name:
                    return e
                found = e.find_first(name)
                if found is not None:
                    return found
        return None

    def append(self, node: Node) -> None:
        """Append a top-level node."""
        self.elements.append(node)

    def prepend(self, node: Node) -> None:
        """Prepend a top-level node."""
        self.elements.insert(0, node)

    def select(self, expr: str) -> Optional[Element]:
        """First element matching a CXPath expression."""
        results = self.select_all(expr)
        return results[0] if results else None

    def select_all(self, expr: str) -> list[Element]:
        """All elements matching a CXPath expression, depth-first."""
        from .cxpath import cxpath_parse, collect_step
        cx_expr = cxpath_parse(expr)
        # Virtual root gives top-level elements sibling context for position predicates.
        virtual_root = Element(name='#document', items=list(self.elements))
        result: list[Element] = []
        collect_step(virtual_root, cx_expr, 0, result)
        return result

    def transform(self, path: str, f) -> "Document":
        """Return a new Document with the element at path replaced by f(el). Original unchanged."""
        from .cxpath import elem_detached, doc_replace_at, path_copy_element
        parts = [p for p in path.split('/') if p]
        if not parts:
            return self
        for i, node in enumerate(self.elements):
            if isinstance(node, Element) and node.name == parts[0]:
                if len(parts) == 1:
                    return doc_replace_at(self, i, f(elem_detached(node)))
                updated = path_copy_element(node, parts[1:], f)
                if updated is not None:
                    return doc_replace_at(self, i, updated)
                return self
        return self

    def transform_all(self, expr: str, f) -> "Document":
        """Return a new Document with every element matching expr replaced by f(el). Original unchanged."""
        from .cxpath import cxpath_parse, rebuild_node
        cx_expr = cxpath_parse(expr)
        new_elements = [rebuild_node(n, cx_expr, f) for n in self.elements]
        return Document(elements=new_elements, prolog=self.prolog, doctype=self.doctype)

    def to_cx(self) -> str:
        return _emit_doc(self)

    def to_xml(self) -> str:
        return _cx.to_xml(self.to_cx())

    def to_json(self) -> str:
        return _cx.to_json(self.to_cx())

    def to_yaml(self) -> str:
        return _cx.to_yaml(self.to_cx())

    def to_toml(self) -> str:
        return _cx.to_toml(self.to_cx())

    def to_md(self) -> str:
        return _cx.to_md(self.to_cx())


# ── Deserialization: AST JSON dict → native types ─────────────────────────────

def _node_from_dict(d: dict) -> Node:
    t = d.get("type", "")
    if t == "Element":
        return Element(
            name=d["name"],
            anchor=d.get("anchor"),
            merge=d.get("merge"),
            data_type=d.get("dataType"),
            attrs=[Attr(a["name"], a["value"], a.get("dataType")) for a in d.get("attrs", [])],
            items=[_node_from_dict(n) for n in d.get("items", [])],
        )
    if t == "Text":
        return Text(d["value"])
    if t == "Scalar":
        return Scalar(d["dataType"], d["value"])
    if t == "Comment":
        return Comment(d["value"])
    if t == "RawText":
        return RawText(d["value"])
    if t == "EntityRef":
        return EntityRef(d["name"])
    if t == "Alias":
        return Alias(d["name"])
    if t == "PI":
        return PI(d["target"], d.get("data"))
    if t == "XMLDecl":
        return XMLDecl(d.get("version", "1.0"), d.get("encoding"), d.get("standalone"))
    if t == "CXDirective":
        return CXDirective([Attr(a["name"], a["value"]) for a in d.get("attrs", [])])
    if t == "DoctypeDecl":
        return DoctypeDecl(d["name"], d.get("externalID"), d.get("intSubset", []))
    if t == "BlockContent":
        return BlockContent([_node_from_dict(n) for n in d.get("items", [])])
    return Text(str(d))  # unknown node — preserve as text


def _doc_from_dict(d: dict) -> Document:
    doctype = None
    if "doctype" in d:
        dt = d["doctype"]
        doctype = DoctypeDecl(dt["name"], dt.get("externalID"), dt.get("intSubset", []))
    return Document(
        prolog=[_node_from_dict(n) for n in d.get("prolog", [])],
        doctype=doctype,
        elements=[_node_from_dict(n) for n in d.get("elements", [])],
    )


def parse(cx_str: str) -> Document:
    """Parse a CX string into a Document."""
    from .binary import ast_bin, decode_ast
    return decode_ast(ast_bin(cx_str))


def parse_xml(xml_str: str) -> Document:
    """Parse an XML string into a Document."""
    return _doc_from_dict(json.loads(_cx.xml_to_ast(xml_str)))


def parse_json(json_str: str) -> Document:
    """Parse a JSON string into a Document."""
    return _doc_from_dict(json.loads(_cx.json_to_ast(json_str)))


def parse_yaml(yaml_str: str) -> Document:
    """Parse a YAML string into a Document."""
    return _doc_from_dict(json.loads(_cx.yaml_to_ast(yaml_str)))


def parse_toml(toml_str: str) -> Document:
    """Parse a TOML string into a Document."""
    return _doc_from_dict(json.loads(_cx.toml_to_ast(toml_str)))


def parse_md(md_str: str) -> Document:
    """Parse a Markdown string into a Document."""
    return _doc_from_dict(json.loads(_cx.md_to_ast(md_str)))


# ── Data binding: loads / dumps ───────────────────────────────────────────────

def loads(cx_str: str) -> Any:
    """Deserialize CX data string into native Python types (dict/list/scalar)."""
    return json.loads(_cx.to_json(cx_str))

def loads_xml(xml_str: str) -> Any:
    """Deserialize XML string into native Python types."""
    return json.loads(_cx.xml_to_json(xml_str))

def loads_json(json_str: str) -> Any:
    """Deserialize JSON string via the CX semantic bridge."""
    return json.loads(_cx.json_to_json(json_str))

def loads_yaml(yaml_str: str) -> Any:
    """Deserialize YAML string into native Python types."""
    return json.loads(_cx.yaml_to_json(yaml_str))

def loads_toml(toml_str: str) -> Any:
    """Deserialize TOML string into native Python types."""
    return json.loads(_cx.toml_to_json(toml_str))

def loads_md(md_str: str) -> Any:
    """Deserialize Markdown string into native Python types."""
    return json.loads(_cx.md_to_json(md_str))

def dumps(data: Any) -> str:
    """Serialize native Python types (dict/list/scalar) to a CX string."""
    return _cx.json_to_cx(json.dumps(data))


# ── CX emitter ────────────────────────────────────────────────────────────────

_DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
_DATETIME_RE = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
_HEX_RE = re.compile(r'^0[xX][0-9a-fA-F]+$')


def _would_autotype(s: str) -> bool:
    if ' ' in s:
        return False
    if _HEX_RE.match(s):
        return True
    try:
        int(s); return True
    except ValueError:
        pass
    if ('.' in s or 'e' in s.lower()):
        try:
            float(s); return True
        except ValueError:
            pass
    if s in ('true', 'false', 'null'):
        return True
    if _DATETIME_RE.match(s):
        return True
    if _DATE_RE.match(s):
        return True
    return False


def _cx_choose_quote(s: str) -> str:
    if "'" not in s:
        return f"'{s}'"
    if '"' not in s:
        return f'"{s}"'
    if "'''" not in s:
        return f"'''{s}'''"
    return f'"{s}"'  # best effort; embedded ''' stays as-is


def _cx_quote_text(s: str) -> str:
    needs = (
        s.startswith(' ') or s.endswith(' ')
        or '  ' in s or '\n' in s or '\t' in s
        or '[' in s or ']' in s or '&' in s
        or s.startswith(':') or s.startswith("'") or s.startswith('"')
        or _would_autotype(s)
    )
    return _cx_choose_quote(s) if needs else s


def _cx_quote_attr(s: str) -> str:
    if not s or ' ' in s or "'" in s or '"' in s:
        return f"'{s}'"
    return s


def _emit_scalar(s: Scalar) -> str:
    v = s.value
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        f = f'{v}'
        return f if ('.' in f or 'e' in f.lower()) else f + '.0'
    return str(v)


def _emit_attr(a: Attr) -> str:
    dt = a.data_type
    if dt == 'int':
        return f'{a.name}={int(a.value)}'
    if dt == 'float':
        f = f'{float(a.value)}'
        v = f if ('.' in f or 'e' in f.lower()) else f + '.0'
        return f'{a.name}={v}'
    if dt == 'bool':
        return f'{a.name}={"true" if a.value else "false"}'
    if dt == 'null':
        return f'{a.name}=null'
    # string attr — quote if would autotype
    s = str(a.value)
    v = _cx_choose_quote(s) if _would_autotype(s) else _cx_quote_attr(s)
    return f'{a.name}={v}'


def _emit_inline(node: Node) -> str:
    if isinstance(node, Text):
        return _cx_quote_text(node.value) if node.value.strip() else ''
    if isinstance(node, Scalar):
        return _emit_scalar(node)
    if isinstance(node, EntityRef):
        return f'&{node.name};'
    if isinstance(node, RawText):
        return f'[#{node.value}#]'
    if isinstance(node, Element):
        return _emit_element(node, 0).rstrip('\n')
    if isinstance(node, BlockContent):
        inner = ''.join(
            (n.value if isinstance(n, Text) else _emit_element(n, 0).rstrip('\n'))
            for n in node.items
        )
        return f'[|{inner}|]'
    return ''


def _emit_element(e: Element, depth: int) -> str:
    ind = '  ' * depth
    has_child_elems = any(isinstance(i, Element) for i in e.items)
    has_text = any(isinstance(i, (Text, Scalar, EntityRef, RawText)) for i in e.items)
    is_multiline = has_child_elems and not has_text

    meta_parts = []
    if e.anchor:
        meta_parts.append(f'&{e.anchor}')
    if e.merge:
        meta_parts.append(f'*{e.merge}')
    if e.data_type:
        meta_parts.append(f':{e.data_type}')
    for a in e.attrs:
        meta_parts.append(_emit_attr(a))
    meta = (' ' + ' '.join(meta_parts)) if meta_parts else ''

    if is_multiline:
        lines = [f'{ind}[{e.name}{meta}\n']
        for item in e.items:
            lines.append(_emit_node(item, depth + 1))
        lines.append(f'{ind}]\n')
        return ''.join(lines)

    if not e.items and not meta:
        return f'{ind}[{e.name}]\n'

    body_parts = [p for p in (_emit_inline(i) for i in e.items) if p]
    body = ' '.join(body_parts)
    sep = ' ' if body else ''
    return f'{ind}[{e.name}{meta}{sep}{body}]\n'


def _emit_node(node: Node, depth: int) -> str:
    ind = '  ' * depth
    if isinstance(node, Element):
        return _emit_element(node, depth)
    if isinstance(node, Text):
        return _cx_quote_text(node.value)
    if isinstance(node, Scalar):
        return _emit_scalar(node)
    if isinstance(node, Comment):
        return f'{ind}[-{node.value}]\n'
    if isinstance(node, RawText):
        return f'{ind}[#{node.value}#]\n'
    if isinstance(node, EntityRef):
        return f'&{node.name};'
    if isinstance(node, Alias):
        return f'{ind}[*{node.name}]\n'
    if isinstance(node, BlockContent):
        inner = ''.join(_emit_node(i, 0) for i in node.items)
        return f'{ind}[|{inner}|]\n'
    if isinstance(node, PI):
        data = f' {node.data}' if node.data else ''
        return f'{ind}[?{node.target}{data}]\n'
    if isinstance(node, XMLDecl):
        parts = [f'version={node.version}']
        if node.encoding:
            parts.append(f'encoding={node.encoding}')
        if node.standalone:
            parts.append(f'standalone={node.standalone}')
        return f'[?xml {" ".join(parts)}]\n'
    if isinstance(node, CXDirective):
        attrs = ' '.join(f'{a.name}={_cx_quote_attr(str(a.value))}' for a in node.attrs)
        return f'[?cx {attrs}]\n'
    if isinstance(node, DoctypeDecl):
        ext = ''
        if node.external_id:
            if 'public' in node.external_id:
                pub, sys = node.external_id['public'], node.external_id.get('system', '')
                ext = f" PUBLIC '{pub}' '{sys}'"
            elif 'system' in node.external_id:
                ext = f" SYSTEM '{node.external_id['system']}'"
        return f'[!DOCTYPE {node.name}{ext}]\n'
    return ''


def _emit_doc(doc: Document) -> str:
    parts = []
    for node in doc.prolog:
        parts.append(_emit_node(node, 0))
    if doc.doctype:
        parts.append(_emit_node(doc.doctype, 0))
    for node in doc.elements:
        parts.append(_emit_node(node, 0))
    return ''.join(parts).rstrip('\n')
