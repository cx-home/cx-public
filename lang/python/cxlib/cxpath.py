"""CXPath parser, evaluator, and transform helpers."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any, Callable, Optional


# ── CXPath AST ────────────────────────────────────────────────────────────────

@dataclass
class CXPredAttrExists:
    attr: str

@dataclass
class CXPredAttrCmp:
    attr: str
    op: str
    val: Any

@dataclass
class CXPredChildExists:
    name: str

@dataclass
class CXPredNot:
    inner: Any  # CXPred

@dataclass
class CXPredBoolAnd:
    left: Any
    right: Any

@dataclass
class CXPredBoolOr:
    left: Any
    right: Any

@dataclass
class CXPredPosition:
    pos: int = 0
    is_last: bool = False

@dataclass
class CXPredFuncContains:
    attr: str
    val: str

@dataclass
class CXPredFuncStartsWith:
    attr: str
    val: str

@dataclass
class _CXStep:
    axis: str   # 'child' | 'descendant'
    name: str   # '' = wildcard (*)
    preds: list = field(default_factory=list)

@dataclass
class _CXPathExpr:
    steps: list = field(default_factory=list)


# ── Tokenizer ─────────────────────────────────────────────────────────────────

class _Lexer:
    def __init__(self, src: str):
        self.src = src
        self.pos = 0

    def skip_ws(self):
        while self.pos < len(self.src) and self.src[self.pos] == ' ':
            self.pos += 1

    def peek_str(self, s: str) -> bool:
        return self.src[self.pos:].startswith(s)

    def eat_str(self, s: str) -> bool:
        if self.peek_str(s):
            self.pos += len(s)
            return True
        return False

    def eat_char(self, c: str) -> bool:
        if self.pos < len(self.src) and self.src[self.pos] == c:
            self.pos += 1
            return True
        return False

    def read_ident(self) -> str:
        start = self.pos
        while self.pos < len(self.src):
            c = self.src[self.pos]
            if c.isalnum() or c in '_-.:%':
                self.pos += 1
            else:
                break
        return self.src[start:self.pos]

    def read_quoted(self) -> str:
        if not self.eat_char("'"):
            raise ValueError(f"CXPath parse error: expected ' at pos {self.pos}  expr: {self.src}")
        start = self.pos
        while self.pos < len(self.src) and self.src[self.pos] != "'":
            self.pos += 1
        s = self.src[start:self.pos]
        if not self.eat_char("'"):
            raise ValueError(f"CXPath parse error: unterminated string at pos {self.pos}  expr: {self.src}")
        return s


# ── Parser ────────────────────────────────────────────────────────────────────

def cxpath_parse(expr: str) -> _CXPathExpr:
    l = _Lexer(expr)
    steps = _parse_steps(l)
    if l.pos != len(l.src):
        raise ValueError(f"CXPath parse error: unexpected characters at pos {l.pos}  expr: {expr}")
    if not steps:
        raise ValueError(f"CXPath parse error: empty expression  expr: {expr}")
    return _CXPathExpr(steps=steps)


def _parse_steps(l: _Lexer) -> list:
    steps = []
    axis = 'child'
    if l.peek_str('//'):
        l.pos += 2
        axis = 'descendant'
    elif l.peek_str('/'):
        l.pos += 1
        axis = 'child'
    steps.append(_parse_one_step(l, axis))
    while True:
        l.skip_ws()
        if l.peek_str('//'):
            l.pos += 2
            steps.append(_parse_one_step(l, 'descendant'))
        elif l.peek_str('/'):
            l.pos += 1
            steps.append(_parse_one_step(l, 'child'))
        else:
            break
    return steps


def _parse_one_step(l: _Lexer, axis: str) -> _CXStep:
    l.skip_ws()
    if l.eat_char('*'):
        name = ''
    else:
        name = l.read_ident()
        if not name:
            raise ValueError(f"CXPath parse error: expected element name at pos {l.pos}  expr: {l.src}")
    preds = []
    while True:
        l.skip_ws()
        if l.peek_str('['):
            preds.append(_parse_pred_bracket(l))
        else:
            break
    return _CXStep(axis=axis, name=name, preds=preds)


def _parse_pred_bracket(l: _Lexer) -> Any:
    if not l.eat_char('['):
        raise ValueError(f"CXPath parse error: expected [ at pos {l.pos}  expr: {l.src}")
    l.skip_ws()
    pred = _parse_pred_expr(l)
    l.skip_ws()
    if not l.eat_char(']'):
        raise ValueError(f"CXPath parse error: expected ] at pos {l.pos}  expr: {l.src}")
    return pred


def _parse_pred_expr(l: _Lexer) -> Any:
    left = _parse_pred_term(l)
    l.skip_ws()
    saved = l.pos
    word = l.read_ident()
    if word == 'or':
        l.skip_ws()
        right = _parse_pred_term(l)
        return CXPredBoolOr(left=left, right=right)
    l.pos = saved
    return left


def _parse_pred_term(l: _Lexer) -> Any:
    left = _parse_pred_factor(l)
    l.skip_ws()
    saved = l.pos
    word = l.read_ident()
    if word == 'and':
        l.skip_ws()
        right = _parse_pred_factor(l)
        return CXPredBoolAnd(left=left, right=right)
    l.pos = saved
    return left


def _parse_pred_factor(l: _Lexer) -> Any:
    l.skip_ws()
    # not(...)
    if l.peek_str('not(') or l.peek_str('not ('):
        l.read_ident()  # consume 'not'
        l.skip_ws()
        if not l.eat_char('('):
            raise ValueError(f"CXPath parse error: expected ( after not  expr: {l.src}")
        l.skip_ws()
        inner = _parse_pred_expr(l)
        l.skip_ws()
        if not l.eat_char(')'):
            raise ValueError(f"CXPath parse error: expected ) after not(...)  expr: {l.src}")
        return CXPredNot(inner=inner)
    # contains(@attr, val)
    if l.peek_str('contains('):
        l.read_ident()  # consume 'contains'
        l.skip_ws()
        if not l.eat_char('('):
            raise ValueError(f"CXPath parse error: expected ( after contains  expr: {l.src}")
        l.skip_ws()
        if not l.eat_char('@'):
            raise ValueError(f"CXPath parse error: expected @attr in contains()  expr: {l.src}")
        attr = l.read_ident()
        l.skip_ws()
        if not l.eat_char(','):
            raise ValueError(f"CXPath parse error: expected , in contains()  expr: {l.src}")
        l.skip_ws()
        val = _parse_scalar_str(l)
        l.skip_ws()
        if not l.eat_char(')'):
            raise ValueError(f"CXPath parse error: expected ) after contains(...)  expr: {l.src}")
        return CXPredFuncContains(attr=attr, val=val)
    # starts-with(@attr, val)
    if l.peek_str('starts-with('):
        while l.pos < len(l.src) and l.src[l.pos] != '(':
            l.pos += 1
        if not l.eat_char('('):
            raise ValueError(f"CXPath parse error: expected ( after starts-with  expr: {l.src}")
        l.skip_ws()
        if not l.eat_char('@'):
            raise ValueError(f"CXPath parse error: expected @attr in starts-with()  expr: {l.src}")
        attr = l.read_ident()
        l.skip_ws()
        if not l.eat_char(','):
            raise ValueError(f"CXPath parse error: expected , in starts-with()  expr: {l.src}")
        l.skip_ws()
        val = _parse_scalar_str(l)
        l.skip_ws()
        if not l.eat_char(')'):
            raise ValueError(f"CXPath parse error: expected ) after starts-with(...)  expr: {l.src}")
        return CXPredFuncStartsWith(attr=attr, val=val)
    # last()
    if l.peek_str('last()'):
        l.pos += 6
        return CXPredPosition(is_last=True)
    # (grouped expr)
    if l.peek_str('('):
        l.eat_char('(')
        l.skip_ws()
        inner = _parse_pred_expr(l)
        l.skip_ws()
        if not l.eat_char(')'):
            raise ValueError(f"CXPath parse error: expected ) at pos {l.pos}  expr: {l.src}")
        return inner
    # @attr comparison or existence
    if l.pos < len(l.src) and l.src[l.pos] == '@':
        l.eat_char('@')
        attr = l.read_ident()
        l.skip_ws()
        op = _parse_op(l)
        if not op:
            return CXPredAttrExists(attr=attr)
        l.skip_ws()
        val = _parse_scalar_val(l)
        return CXPredAttrCmp(attr=attr, op=op, val=val)
    # integer position predicate
    if l.pos < len(l.src) and l.src[l.pos].isdigit():
        start = l.pos
        while l.pos < len(l.src) and l.src[l.pos].isdigit():
            l.pos += 1
        return CXPredPosition(pos=int(l.src[start:l.pos]))
    # bare name → child existence
    name = l.read_ident()
    if name:
        return CXPredChildExists(name=name)
    raise ValueError(f"CXPath parse error: unexpected character at pos {l.pos}  expr: {l.src}")


def _parse_op(l: _Lexer) -> str:
    for op in ('!=', '>=', '<=', '=', '>', '<'):
        if l.eat_str(op):
            return op
    return ''


def _autotype_value(s: str) -> Any:
    if s == 'true':  return True
    if s == 'false': return False
    if s == 'null':  return None
    try:    return int(s)
    except ValueError: pass
    try:    return float(s)
    except ValueError: pass
    return s


def _parse_scalar_val(l: _Lexer) -> Any:
    if l.peek_str("'"):
        return l.read_quoted()
    s = l.read_ident()
    if not s:
        raise ValueError(f"CXPath parse error: expected value at pos {l.pos}  expr: {l.src}")
    return _autotype_value(s)


def _parse_scalar_str(l: _Lexer) -> str:
    if l.peek_str("'"):
        return l.read_quoted()
    return l.read_ident()


# ── Evaluator ─────────────────────────────────────────────────────────────────

def collect_step(ctx, expr: _CXPathExpr, step_idx: int, result: list) -> None:
    """Dispatch from context element into its children for the given step."""
    from .ast import Element
    if step_idx >= len(expr.steps):
        return
    step = expr.steps[step_idx]
    if step.axis == 'child':
        candidates = [i for i in ctx.items
                      if isinstance(i, Element) and (step.name == '' or i.name == step.name)]
        for i, child in enumerate(candidates):
            if _preds_match(child, step.preds, candidates, i):
                if step_idx == len(expr.steps) - 1:
                    result.append(child)
                else:
                    collect_step(child, expr, step_idx + 1, result)
    else:
        _collect_descendants(ctx, expr, step_idx, result)


def _collect_descendants(ctx, expr: _CXPathExpr, step_idx: int, result: list) -> None:
    """Descendant axis: match at every depth with proper sibling context for position preds."""
    from .ast import Element
    step = expr.steps[step_idx]
    is_last = step_idx == len(expr.steps) - 1
    candidates = [i for i in ctx.items
                  if isinstance(i, Element) and (step.name == '' or i.name == step.name)]
    for i, child in enumerate(candidates):
        if _preds_match(child, step.preds, candidates, i):
            if is_last:
                result.append(child)
            else:
                collect_step(child, expr, step_idx + 1, result)
        # Always recurse deeper (even after a match) for descendant axis
        _collect_descendants(child, expr, step_idx, result)
    # Also descend into non-matching children for named steps (not needed for wildcard)
    if step.name:
        for child in ctx.items:
            if isinstance(child, Element) and child.name != step.name:
                _collect_descendants(child, expr, step_idx, result)


# ── Predicate evaluators ──────────────────────────────────────────────────────

def _preds_match(el, preds: list, siblings: list, idx: int) -> bool:
    return all(_pred_eval(el, p, siblings, idx) for p in preds)


def _pred_eval(el, pred: Any, siblings: list, idx: int) -> bool:
    if isinstance(pred, CXPredAttrExists):
        return el.attr(pred.attr) is not None
    if isinstance(pred, CXPredAttrCmp):
        v = el.attr(pred.attr)
        if v is None:
            return False
        return _compare(v, pred.op, pred.val)
    if isinstance(pred, CXPredChildExists):
        return el.get(pred.name) is not None
    if isinstance(pred, CXPredNot):
        return not _pred_eval(el, pred.inner, siblings, idx)
    if isinstance(pred, CXPredBoolAnd):
        return (_pred_eval(el, pred.left, siblings, idx)
                and _pred_eval(el, pred.right, siblings, idx))
    if isinstance(pred, CXPredBoolOr):
        return (_pred_eval(el, pred.left, siblings, idx)
                or _pred_eval(el, pred.right, siblings, idx))
    if isinstance(pred, CXPredPosition):
        if pred.is_last:
            return idx == len(siblings) - 1
        return idx == pred.pos - 1
    if isinstance(pred, CXPredFuncContains):
        v = el.attr(pred.attr)
        return v is not None and pred.val in _val_to_str(v)
    if isinstance(pred, CXPredFuncStartsWith):
        v = el.attr(pred.attr)
        return v is not None and _val_to_str(v).startswith(pred.val)
    return False


def _val_to_str(v: Any) -> str:
    if v is None:           return 'null'
    if isinstance(v, bool): return 'true' if v else 'false'
    return str(v)


def _scalar_eq(a: Any, b: Any) -> bool:
    # bool is a subclass of int in Python — guard against cross-type matches
    a_bool = isinstance(a, bool)
    b_bool = isinstance(b, bool)
    if a_bool != b_bool:
        return False
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return float(a) == float(b)
    return a == b


def _compare(actual: Any, op: str, expected: Any) -> bool:
    if op == '=':  return _scalar_eq(actual, expected)
    if op == '!=': return not _scalar_eq(actual, expected)
    a = _to_f64(actual)
    b = _to_f64(expected)
    if op == '>':  return a > b
    if op == '<':  return a < b
    if op == '>=': return a >= b
    if op == '<=': return a <= b
    return False


def _to_f64(v: Any) -> float:
    if isinstance(v, bool):
        raise ValueError(f"CXPath: numeric comparison requires numeric value, got bool: {v}")
    if isinstance(v, (int, float)):
        return float(v)
    raise ValueError(f"CXPath: numeric comparison requires numeric attribute value, got: {v!r}")


# ── cxpath_elem_matches (for transform_all) ───────────────────────────────────

def cxpath_elem_matches(el, expr: _CXPathExpr) -> bool:
    if not expr.steps:
        return False
    last = expr.steps[-1]
    if last.name and last.name != el.name:
        return False
    non_pos = [p for p in last.preds if not isinstance(p, CXPredPosition)]
    return _preds_match(el, non_pos, [], 0)


# ── Transform helpers ─────────────────────────────────────────────────────────

def elem_detached(e) -> Any:
    """Return a copy of e with independent attrs/items lists so f cannot mutate the source."""
    from .ast import Element, Attr
    return Element(
        name=e.name,
        anchor=e.anchor,
        merge=e.merge,
        data_type=e.data_type,
        attrs=[Attr(a.name, a.value, a.data_type) for a in e.attrs],
        items=list(e.items),
    )


def doc_replace_at(d, idx: int, el) -> Any:
    from .ast import Document
    return Document(
        elements=[el if i == idx else n for i, n in enumerate(d.elements)],
        prolog=d.prolog,
        doctype=d.doctype,
    )


def elem_replace_item_at(e, idx: int, child) -> Any:
    from .ast import Element
    return Element(
        name=e.name,
        anchor=e.anchor,
        merge=e.merge,
        data_type=e.data_type,
        attrs=e.attrs,
        items=[child if i == idx else n for i, n in enumerate(e.items)],
    )


def path_copy_element(e, parts: list, f: Callable) -> Optional[Any]:
    """Returns a new Element with f applied at parts[...], or None if path not found."""
    from .ast import Element
    for i, item in enumerate(e.items):
        if isinstance(item, Element) and item.name == parts[0]:
            if len(parts) == 1:
                return elem_replace_item_at(e, i, f(elem_detached(item)))
            updated = path_copy_element(item, parts[1:], f)
            if updated is not None:
                return elem_replace_item_at(e, i, updated)
            return None
    return None


def rebuild_node(node, expr: _CXPathExpr, f: Callable) -> Any:
    """Recursively rebuild node tree, applying f to every element matching expr."""
    from .ast import Element
    if not isinstance(node, Element):
        return node
    new_items = [rebuild_node(item, expr, f) for item in node.items]
    new_el = Element(
        name=node.name,
        anchor=node.anchor,
        merge=node.merge,
        data_type=node.data_type,
        attrs=node.attrs,
        items=new_items,
    )
    if cxpath_elem_matches(new_el, expr):
        return f(elem_detached(new_el))
    return new_el
