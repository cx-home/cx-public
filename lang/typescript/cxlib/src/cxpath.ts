/**
 * CXPath parser, evaluator, and transform helpers.
 * Ported from the Python reference implementation (lang/python/cxlib/cxpath.py).
 */

// ── Minimal interface to avoid circular imports ────────────────────────────────

/**
 * CXElem is a duck-typed interface that Element satisfies.
 * Using this instead of importing Element directly prevents circular deps.
 */
export interface CXElem {
  name: string;
  attrs: Array<{ name: string; value: any; dataType?: string | null }>;
  items: any[];
  get(name: string): CXElem | null;
  attr(name: string): any;
}

// ── CXPath AST ────────────────────────────────────────────────────────────────

export interface CXPredAttrExists   { type: 'attrExists'; attr: string }
export interface CXPredAttrCmp      { type: 'attrCmp'; attr: string; op: string; val: any }
export interface CXPredChildExists  { type: 'childExists'; name: string }
export interface CXPredNot          { type: 'not'; inner: CXPred }
export interface CXPredBoolAnd      { type: 'and'; left: CXPred; right: CXPred }
export interface CXPredBoolOr       { type: 'or'; left: CXPred; right: CXPred }
export interface CXPredPosition     { type: 'position'; pos: number; isLast: boolean }
export interface CXPredFuncContains { type: 'contains'; attr: string; val: string }
export interface CXPredFuncStartsWith { type: 'startsWith'; attr: string; val: string }

export type CXPred =
  | CXPredAttrExists
  | CXPredAttrCmp
  | CXPredChildExists
  | CXPredNot
  | CXPredBoolAnd
  | CXPredBoolOr
  | CXPredPosition
  | CXPredFuncContains
  | CXPredFuncStartsWith;

export interface CXStep {
  axis: 'child' | 'descendant';
  name: string;   // '' = wildcard (*)
  preds: CXPred[];
}

export interface CXPathExpr {
  steps: CXStep[];
}

// ── Lexer ─────────────────────────────────────────────────────────────────────

class Lexer {
  src: string;
  pos: number;

  constructor(src: string) {
    this.src = src;
    this.pos = 0;
  }

  skipWs(): void {
    while (this.pos < this.src.length && this.src[this.pos] === ' ') {
      this.pos++;
    }
  }

  peekStr(s: string): boolean {
    return this.src.slice(this.pos).startsWith(s);
  }

  eatStr(s: string): boolean {
    if (this.peekStr(s)) {
      this.pos += s.length;
      return true;
    }
    return false;
  }

  eatChar(c: string): boolean {
    if (this.pos < this.src.length && this.src[this.pos] === c) {
      this.pos++;
      return true;
    }
    return false;
  }

  readIdent(): string {
    const start = this.pos;
    while (this.pos < this.src.length) {
      const c = this.src[this.pos];
      if (/[a-zA-Z0-9_\-.:%]/.test(c)) {
        this.pos++;
      } else {
        break;
      }
    }
    return this.src.slice(start, this.pos);
  }

  readQuoted(): string {
    if (!this.eatChar("'")) {
      throw new Error(`CXPath parse error: expected ' at pos ${this.pos}  expr: ${this.src}`);
    }
    const start = this.pos;
    while (this.pos < this.src.length && this.src[this.pos] !== "'") {
      this.pos++;
    }
    const s = this.src.slice(start, this.pos);
    if (!this.eatChar("'")) {
      throw new Error(`CXPath parse error: unterminated string at pos ${this.pos}  expr: ${this.src}`);
    }
    return s;
  }
}

// ── Parser ────────────────────────────────────────────────────────────────────

export function cxpathParse(expr: string): CXPathExpr {
  const l = new Lexer(expr);
  const steps = parseSteps(l);
  if (l.pos !== l.src.length) {
    throw new Error(`CXPath parse error: unexpected characters at pos ${l.pos}  expr: ${expr}`);
  }
  if (steps.length === 0) {
    throw new Error(`CXPath parse error: empty expression  expr: ${expr}`);
  }
  return { steps };
}

function parseSteps(l: Lexer): CXStep[] {
  const steps: CXStep[] = [];
  let axis: 'child' | 'descendant' = 'child';
  if (l.peekStr('//')) {
    l.pos += 2;
    axis = 'descendant';
  } else if (l.peekStr('/')) {
    l.pos += 1;
    axis = 'child';
  }
  steps.push(parseOneStep(l, axis));
  while (true) {
    l.skipWs();
    if (l.peekStr('//')) {
      l.pos += 2;
      steps.push(parseOneStep(l, 'descendant'));
    } else if (l.peekStr('/')) {
      l.pos += 1;
      steps.push(parseOneStep(l, 'child'));
    } else {
      break;
    }
  }
  return steps;
}

function parseOneStep(l: Lexer, axis: 'child' | 'descendant'): CXStep {
  l.skipWs();
  let name: string;
  if (l.eatChar('*')) {
    name = '';
  } else {
    name = l.readIdent();
    if (!name) {
      throw new Error(`CXPath parse error: expected element name at pos ${l.pos}  expr: ${l.src}`);
    }
  }
  const preds: CXPred[] = [];
  while (true) {
    l.skipWs();
    if (l.peekStr('[')) {
      preds.push(parsePredBracket(l));
    } else {
      break;
    }
  }
  return { axis, name, preds };
}

function parsePredBracket(l: Lexer): CXPred {
  if (!l.eatChar('[')) {
    throw new Error(`CXPath parse error: expected [ at pos ${l.pos}  expr: ${l.src}`);
  }
  l.skipWs();
  const pred = parsePredExpr(l);
  l.skipWs();
  if (!l.eatChar(']')) {
    throw new Error(`CXPath parse error: expected ] at pos ${l.pos}  expr: ${l.src}`);
  }
  return pred;
}

function parsePredExpr(l: Lexer): CXPred {
  const left = parsePredTerm(l);
  l.skipWs();
  const saved = l.pos;
  const word = l.readIdent();
  if (word === 'or') {
    l.skipWs();
    const right = parsePredTerm(l);
    return { type: 'or', left, right };
  }
  l.pos = saved;
  return left;
}

function parsePredTerm(l: Lexer): CXPred {
  const left = parsePredFactor(l);
  l.skipWs();
  const saved = l.pos;
  const word = l.readIdent();
  if (word === 'and') {
    l.skipWs();
    const right = parsePredFactor(l);
    return { type: 'and', left, right };
  }
  l.pos = saved;
  return left;
}

function parsePredFactor(l: Lexer): CXPred {
  l.skipWs();

  // not(...)
  if (l.peekStr('not(') || l.peekStr('not (')) {
    l.readIdent();  // consume 'not'
    l.skipWs();
    if (!l.eatChar('(')) {
      throw new Error(`CXPath parse error: expected ( after not  expr: ${l.src}`);
    }
    l.skipWs();
    const inner = parsePredExpr(l);
    l.skipWs();
    if (!l.eatChar(')')) {
      throw new Error(`CXPath parse error: expected ) after not(...)  expr: ${l.src}`);
    }
    return { type: 'not', inner };
  }

  // contains(@attr, val)
  if (l.peekStr('contains(')) {
    l.readIdent();  // consume 'contains'
    l.skipWs();
    if (!l.eatChar('(')) {
      throw new Error(`CXPath parse error: expected ( after contains  expr: ${l.src}`);
    }
    l.skipWs();
    if (!l.eatChar('@')) {
      throw new Error(`CXPath parse error: expected @attr in contains()  expr: ${l.src}`);
    }
    const attr = l.readIdent();
    l.skipWs();
    if (!l.eatChar(',')) {
      throw new Error(`CXPath parse error: expected , in contains()  expr: ${l.src}`);
    }
    l.skipWs();
    const val = parseScalarStr(l);
    l.skipWs();
    if (!l.eatChar(')')) {
      throw new Error(`CXPath parse error: expected ) after contains(...)  expr: ${l.src}`);
    }
    return { type: 'contains', attr, val };
  }

  // starts-with(@attr, val)
  if (l.peekStr('starts-with(')) {
    while (l.pos < l.src.length && l.src[l.pos] !== '(') {
      l.pos++;
    }
    if (!l.eatChar('(')) {
      throw new Error(`CXPath parse error: expected ( after starts-with  expr: ${l.src}`);
    }
    l.skipWs();
    if (!l.eatChar('@')) {
      throw new Error(`CXPath parse error: expected @attr in starts-with()  expr: ${l.src}`);
    }
    const attr = l.readIdent();
    l.skipWs();
    if (!l.eatChar(',')) {
      throw new Error(`CXPath parse error: expected , in starts-with()  expr: ${l.src}`);
    }
    l.skipWs();
    const val = parseScalarStr(l);
    l.skipWs();
    if (!l.eatChar(')')) {
      throw new Error(`CXPath parse error: expected ) after starts-with(...)  expr: ${l.src}`);
    }
    return { type: 'startsWith', attr, val };
  }

  // last()
  if (l.peekStr('last()')) {
    l.pos += 6;
    return { type: 'position', pos: 0, isLast: true };
  }

  // (grouped expr)
  if (l.peekStr('(')) {
    l.eatChar('(');
    l.skipWs();
    const inner = parsePredExpr(l);
    l.skipWs();
    if (!l.eatChar(')')) {
      throw new Error(`CXPath parse error: expected ) at pos ${l.pos}  expr: ${l.src}`);
    }
    return inner;
  }

  // @attr comparison or existence
  if (l.pos < l.src.length && l.src[l.pos] === '@') {
    l.eatChar('@');
    const attr = l.readIdent();
    l.skipWs();
    const op = parseOp(l);
    if (!op) {
      return { type: 'attrExists', attr };
    }
    l.skipWs();
    const val = parseScalarVal(l);
    return { type: 'attrCmp', attr, op, val };
  }

  // integer position predicate
  if (l.pos < l.src.length && /\d/.test(l.src[l.pos])) {
    const start = l.pos;
    while (l.pos < l.src.length && /\d/.test(l.src[l.pos])) {
      l.pos++;
    }
    return { type: 'position', pos: parseInt(l.src.slice(start, l.pos), 10), isLast: false };
  }

  // bare name → child existence
  const name = l.readIdent();
  if (name) {
    return { type: 'childExists', name };
  }

  throw new Error(`CXPath parse error: unexpected character at pos ${l.pos}  expr: ${l.src}`);
}

function parseOp(l: Lexer): string {
  for (const op of ['!=', '>=', '<=', '=', '>', '<']) {
    if (l.eatStr(op)) return op;
  }
  return '';
}

function autotypeValue(s: string): any {
  if (s === 'true')  return true;
  if (s === 'false') return false;
  if (s === 'null')  return null;
  // Try integer
  if (/^-?\d+$/.test(s)) {
    const n = Number(s);
    if (!isNaN(n)) return n;
  }
  // Try float
  const f = Number(s);
  if (!isNaN(f) && s.trim() !== '') return f;
  return s;
}

function parseScalarVal(l: Lexer): any {
  if (l.peekStr("'")) {
    return l.readQuoted();
  }
  const s = l.readIdent();
  if (!s) {
    throw new Error(`CXPath parse error: expected value at pos ${l.pos}  expr: ${l.src}`);
  }
  return autotypeValue(s);
}

function parseScalarStr(l: Lexer): string {
  if (l.peekStr("'")) {
    return l.readQuoted();
  }
  return l.readIdent();
}

// ── Evaluator ─────────────────────────────────────────────────────────────────

export function collectStep(ctx: CXElem, expr: CXPathExpr, stepIdx: number, result: CXElem[]): void {
  if (stepIdx >= expr.steps.length) return;
  const step = expr.steps[stepIdx];
  if (step.axis === 'child') {
    const candidates = ctx.items.filter(
      (i: any) => isElem(i) && (step.name === '' || i.name === step.name),
    ) as CXElem[];
    for (let i = 0; i < candidates.length; i++) {
      const child = candidates[i];
      if (predsMatch(child, step.preds, candidates, i)) {
        if (stepIdx === expr.steps.length - 1) {
          result.push(child);
        } else {
          collectStep(child, expr, stepIdx + 1, result);
        }
      }
    }
  } else {
    collectDescendants(ctx, expr, stepIdx, result);
  }
}

export function collectDescendants(ctx: CXElem, expr: CXPathExpr, stepIdx: number, result: CXElem[]): void {
  const step = expr.steps[stepIdx];
  const isLast = stepIdx === expr.steps.length - 1;
  const candidates = ctx.items.filter(
    (i: any) => isElem(i) && (step.name === '' || i.name === step.name),
  ) as CXElem[];
  for (let i = 0; i < candidates.length; i++) {
    const child = candidates[i];
    if (predsMatch(child, step.preds, candidates, i)) {
      if (isLast) {
        result.push(child);
      } else {
        collectStep(child, expr, stepIdx + 1, result);
      }
    }
    // Always recurse deeper (even after a match) for descendant axis
    collectDescendants(child, expr, stepIdx, result);
  }
  // Also descend into non-matching children for named steps (not wildcard)
  if (step.name) {
    for (const child of ctx.items) {
      if (isElem(child) && child.name !== step.name) {
        collectDescendants(child as CXElem, expr, stepIdx, result);
      }
    }
  }
}

function isElem(v: any): boolean {
  return v !== null && typeof v === 'object' && typeof v.name === 'string' && Array.isArray(v.items);
}

// ── Predicate evaluators ──────────────────────────────────────────────────────

export function predsMatch(el: CXElem, preds: CXPred[], siblings: CXElem[], idx: number): boolean {
  return preds.every(p => predEval(el, p, siblings, idx));
}

function predEval(el: CXElem, pred: CXPred, siblings: CXElem[], idx: number): boolean {
  switch (pred.type) {
    case 'attrExists':
      return el.attr(pred.attr) !== null;

    case 'attrCmp': {
      const v = el.attr(pred.attr);
      if (v === null) return false;
      return compare(v, pred.op, pred.val);
    }

    case 'childExists':
      return el.get(pred.name) !== null;

    case 'not':
      return !predEval(el, pred.inner, siblings, idx);

    case 'and':
      return predEval(el, pred.left, siblings, idx) && predEval(el, pred.right, siblings, idx);

    case 'or':
      return predEval(el, pred.left, siblings, idx) || predEval(el, pred.right, siblings, idx);

    case 'position':
      if (pred.isLast) return idx === siblings.length - 1;
      return idx === pred.pos - 1;

    case 'contains': {
      const v = el.attr(pred.attr);
      return v !== null && valToStr(v).includes(pred.val);
    }

    case 'startsWith': {
      const v = el.attr(pred.attr);
      return v !== null && valToStr(v).startsWith(pred.val);
    }
  }
}

function valToStr(v: any): string {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'boolean')        return v ? 'true' : 'false';
  return String(v);
}

function scalarEq(a: any, b: any): boolean {
  const aBool = typeof a === 'boolean';
  const bBool = typeof b === 'boolean';
  if (aBool !== bBool) return false;
  if (typeof a === 'number' && typeof b === 'number') return a === b;
  return a === b;
}

function compare(actual: any, op: string, expected: any): boolean {
  if (op === '=')  return scalarEq(actual, expected);
  if (op === '!=') return !scalarEq(actual, expected);
  const a = toF64(actual);
  const b = toF64(expected);
  if (op === '>')  return a > b;
  if (op === '<')  return a < b;
  if (op === '>=') return a >= b;
  if (op === '<=') return a <= b;
  return false;
}

function toF64(v: any): number {
  if (typeof v === 'boolean') {
    throw new Error(`CXPath: numeric comparison requires numeric value, got bool: ${v}`);
  }
  if (typeof v === 'number') return v;
  throw new Error(`CXPath: numeric comparison requires numeric attribute value, got: ${JSON.stringify(v)}`);
}

// ── cxpathElemMatches (for transformAll) ──────────────────────────────────────

export function cxpathElemMatches(el: CXElem, expr: CXPathExpr): boolean {
  if (expr.steps.length === 0) return false;
  const last = expr.steps[expr.steps.length - 1];
  if (last.name && last.name !== el.name) return false;
  const nonPos = last.preds.filter(p => p.type !== 'position');
  return predsMatch(el, nonPos, [], 0);
}

// ── Transform helpers ─────────────────────────────────────────────────────────

/**
 * Return a shallow copy of e with independent attrs/items arrays
 * so that f cannot mutate the source document.
 */
export function elemDetached(e: any): any {
  // We use 'any' here to avoid importing Element (circular dependency).
  // The caller (ast.ts) passes a proper Element instance.
  const { Element } = require('./ast');
  return new Element({
    name: e.name,
    anchor: e.anchor,
    merge: e.merge,
    dataType: e.dataType,
    attrs: e.attrs.map((a: any) => ({ name: a.name, value: a.value, dataType: a.dataType ?? null })),
    items: [...e.items],
  });
}

export function docReplaceAt(d: any, idx: number, el: any): any {
  const { Document } = require('./ast');
  return new Document({
    elements: d.elements.map((n: any, i: number) => (i === idx ? el : n)),
    prolog: d.prolog,
    doctype: d.doctype,
  });
}

export function elemReplaceItemAt(e: any, idx: number, child: any): any {
  const { Element } = require('./ast');
  return new Element({
    name: e.name,
    anchor: e.anchor,
    merge: e.merge,
    dataType: e.dataType,
    attrs: e.attrs,
    items: e.items.map((n: any, i: number) => (i === idx ? child : n)),
  });
}

export function pathCopyElement(e: any, parts: string[], f: (el: any) => any): any | null {
  const { Element } = require('./ast');
  for (let i = 0; i < e.items.length; i++) {
    const item = e.items[i];
    if (item instanceof Element && item.name === parts[0]) {
      if (parts.length === 1) {
        return elemReplaceItemAt(e, i, f(elemDetached(item)));
      }
      const updated = pathCopyElement(item, parts.slice(1), f);
      if (updated !== null) {
        return elemReplaceItemAt(e, i, updated);
      }
      return null;
    }
  }
  return null;
}

export function rebuildNode(node: any, expr: CXPathExpr, f: (el: any) => any): any {
  const { Element } = require('./ast');
  if (!(node instanceof Element)) return node;
  const newItems = node.items.map((item: any) => rebuildNode(item, expr, f));
  const newEl = new Element({
    name: node.name,
    anchor: node.anchor,
    merge: node.merge,
    dataType: node.dataType,
    attrs: node.attrs,
    items: newItems,
  });
  if (cxpathElemMatches(newEl, expr)) {
    return f(elemDetached(newEl));
  }
  return newEl;
}
