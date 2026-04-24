/**
 * CX Document API — AST types, parse, query, mutation, CX emitter, loads/dumps.
 */
import {
  toAstBin as _toAstBin,
  toJson as _toJson,
  toXml as _toXml,
  toYaml as _toYaml,
  toToml as _toToml,
  toMd as _toMd,
  jsonToCx as _jsonToCx,
  xmlToAst as _xmlToAst,
  jsonToAst as _jsonToAst,
  yamlToAst as _yamlToAst,
  tomlToAst as _tomlToAst,
  mdToAst as _mdToAst,
  xmlToJson as _xmlToJson,
  jsonToJson as _jsonToJson,
  yamlToJson as _yamlToJson,
  tomlToJson as _tomlToJson,
  mdToJson as _mdToJson,
} from './index';
import { decodeAST as _decodeAST } from './binary';

// ── Node types ────────────────────────────────────────────────────────────────

export interface Attr {
  name: string;
  value: any;       // string | number | boolean | null
  dataType?: string | null;  // null/undefined means string (omitted in JSON)
}

export class TextNode {
  readonly type = 'Text' as const;
  constructor(public value: string) {}
}

export class ScalarNode {
  readonly type = 'Scalar' as const;
  constructor(public dataType: string, public value: any) {}
}

export class CommentNode {
  readonly type = 'Comment' as const;
  constructor(public value: string) {}
}

export class RawTextNode {
  readonly type = 'RawText' as const;
  constructor(public value: string) {}
}

export class EntityRefNode {
  readonly type = 'EntityRef' as const;
  constructor(public name: string) {}
}

export class AliasNode {
  readonly type = 'Alias' as const;
  constructor(public name: string) {}
}

export class PINode {
  readonly type = 'PI' as const;
  constructor(public target: string, public data?: string | null) {}
}

export class XMLDeclNode {
  readonly type = 'XMLDecl' as const;
  constructor(
    public version: string = '1.0',
    public encoding?: string | null,
    public standalone?: string | null,
  ) {}
}

export class CXDirectiveNode {
  readonly type = 'CXDirective' as const;
  constructor(public attrs: Attr[] = []) {}
}

export class BlockContentNode {
  readonly type = 'BlockContent' as const;
  constructor(public items: Node[] = []) {}
}

export class DoctypeDeclNode {
  readonly type = 'DoctypeDecl' as const;
  constructor(
    public name: string,
    public externalID?: any,
    public intSubset: any[] = [],
  ) {}
}

export type Node =
  | Element
  | TextNode
  | ScalarNode
  | CommentNode
  | RawTextNode
  | EntityRefNode
  | AliasNode
  | PINode
  | XMLDeclNode
  | CXDirectiveNode
  | BlockContentNode
  | DoctypeDeclNode;

// ── Element ───────────────────────────────────────────────────────────────────

export class Element {
  readonly type = 'Element' as const;
  name: string;
  anchor?: string | null;
  merge?: string | null;
  dataType?: string | null;
  attrs: Attr[];
  items: Node[];

  constructor(opts: {
    name: string;
    anchor?: string | null;
    merge?: string | null;
    dataType?: string | null;
    attrs?: Attr[];
    items?: Node[];
  }) {
    this.name = opts.name;
    this.anchor = opts.anchor ?? null;
    this.merge = opts.merge ?? null;
    this.dataType = opts.dataType ?? null;
    this.attrs = opts.attrs ?? [];
    this.items = opts.items ?? [];
  }

  /** First child Element with this name. */
  get(name: string): Element | null {
    for (const item of this.items) {
      if (item instanceof Element && item.name === name) return item;
    }
    return null;
  }

  /** All child Elements with this name. */
  getAll(name: string): Element[] {
    return this.items.filter(
      (i): i is Element => i instanceof Element && i.name === name,
    );
  }

  /** Attribute value by name, or null. */
  attr(name: string): any {
    for (const a of this.attrs) {
      if (a.name === name) return a.value;
    }
    return null;
  }

  /** Concatenated Text and Scalar child content. */
  text(): string {
    const parts: string[] = [];
    for (const item of this.items) {
      if (item instanceof TextNode) {
        parts.push(item.value);
      } else if (item instanceof ScalarNode) {
        parts.push(item.value === null ? 'null' : String(item.value));
      }
    }
    return parts.join(' ');
  }

  /** Value of first Scalar child, or null. */
  scalar(): any {
    for (const item of this.items) {
      if (item instanceof ScalarNode) return item.value;
    }
    return null;
  }

  /** All child Elements (excludes Text, Scalar, and other nodes). */
  children(): Element[] {
    return this.items.filter((i): i is Element => i instanceof Element);
  }

  /** All descendant Elements with this name (depth-first). */
  findAll(name: string): Element[] {
    const result: Element[] = [];
    for (const item of this.items) {
      if (item instanceof Element) {
        if (item.name === name) result.push(item);
        result.push(...item.findAll(name));
      }
    }
    return result;
  }

  /** First descendant Element with this name (depth-first). */
  findFirst(name: string): Element | null {
    for (const item of this.items) {
      if (item instanceof Element) {
        if (item.name === name) return item;
        const found = item.findFirst(name);
        if (found !== null) return found;
      }
    }
    return null;
  }

  /** Navigate by slash-separated path: el.at('server/host'). */
  at(path: string): Element | null {
    const parts = path.split('/').filter(p => p.length > 0);
    let cur: Element | null = this;
    for (const part of parts) {
      if (cur === null) return null;
      cur = cur.get(part);
    }
    return cur;
  }

  /** Append a child node. */
  append(node: Node): void {
    this.items.push(node);
  }

  /** Prepend a child node. */
  prepend(node: Node): void {
    this.items.unshift(node);
  }

  /** Insert a child node at index. */
  insert(index: number, node: Node): void {
    this.items.splice(index, 0, node);
  }

  /** Remove a child node by identity. */
  remove(node: Node): void {
    this.items = this.items.filter(i => i !== node);
  }

  /** Set an attribute value, updating if it already exists. */
  setAttr(name: string, value: any, dataType?: string | null): void {
    for (const a of this.attrs) {
      if (a.name === name) {
        a.value = value;
        a.dataType = dataType ?? null;
        return;
      }
    }
    this.attrs.push({ name, value, dataType: dataType ?? null });
  }

  /** Remove an attribute by name. */
  removeAttr(name: string): void {
    this.attrs = this.attrs.filter(a => a.name !== name);
  }

  /** Remove all direct child Elements with this name. */
  removeChild(name: string): void {
    this.items = this.items.filter(i => !(i instanceof Element && i.name === name));
  }

  /** Remove child node at index (no-op if out of bounds). */
  removeAt(index: number): void {
    if (index >= 0 && index < this.items.length) {
      this.items.splice(index, 1);
    }
  }

  /** First Element matching a CXPath expression (subtree of this element). */
  select(expr: string): Element | null {
    const results = this.selectAll(expr);
    return results.length > 0 ? results[0] : null;
  }

  /** All Elements matching a CXPath expression (subtree of this element). */
  selectAll(expr: string): Element[] {
    const { cxpathParse, collectStep } = require('./cxpath');
    const cx = cxpathParse(expr);
    const result: Element[] = [];
    collectStep(this, cx, 0, result);
    return result;
  }
}

// ── Document ──────────────────────────────────────────────────────────────────

export class Document {
  elements: Node[];
  prolog: Node[];
  doctype?: DoctypeDeclNode | null;

  constructor(opts: {
    elements?: Node[];
    prolog?: Node[];
    doctype?: DoctypeDeclNode | null;
  } = {}) {
    this.elements = opts.elements ?? [];
    this.prolog = opts.prolog ?? [];
    this.doctype = opts.doctype ?? null;
  }

  /** First top-level Element. */
  root(): Element | null {
    for (const e of this.elements) {
      if (e instanceof Element) return e;
    }
    return null;
  }

  /** First top-level Element with this name. */
  get(name: string): Element | null {
    for (const e of this.elements) {
      if (e instanceof Element && e.name === name) return e;
    }
    return null;
  }

  /** Navigate by slash-separated path from root: doc.at('article/body/p'). */
  at(path: string): Element | null {
    const parts = path.split('/').filter(p => p.length > 0);
    if (parts.length === 0) return this.root();
    const cur = this.get(parts[0]);
    if (cur === null || parts.length === 1) return cur;
    return cur.at(parts.slice(1).join('/'));
  }

  /** All descendant Elements with this name (depth-first through entire document). */
  findAll(name: string): Element[] {
    const result: Element[] = [];
    for (const e of this.elements) {
      if (e instanceof Element) {
        if (e.name === name) result.push(e);
        result.push(...e.findAll(name));
      }
    }
    return result;
  }

  /** First descendant Element with this name (depth-first through entire document). */
  findFirst(name: string): Element | null {
    for (const e of this.elements) {
      if (e instanceof Element) {
        if (e.name === name) return e;
        const found = e.findFirst(name);
        if (found !== null) return found;
      }
    }
    return null;
  }

  /** Append a top-level node. */
  append(node: Node): void {
    this.elements.push(node);
  }

  /** Prepend a top-level node. */
  prepend(node: Node): void {
    this.elements.unshift(node);
  }

  /** First Element matching a CXPath expression. */
  select(expr: string): Element | null {
    const results = this.selectAll(expr);
    return results.length > 0 ? results[0] : null;
  }

  /** All Elements matching a CXPath expression. */
  selectAll(expr: string): Element[] {
    const { cxpathParse, collectStep } = require('./cxpath');
    const cx = cxpathParse(expr);
    const vroot = new Element({ name: '#document', items: [...this.elements] });
    const result: Element[] = [];
    collectStep(vroot, cx, 0, result);
    return result;
  }

  /** Return new Document with element at path replaced by f(element). */
  transform(path: string, f: (el: Element) => Element): Document {
    const { cxpathParse: _unused, elemDetached, docReplaceAt, pathCopyElement } = require('./cxpath');
    const parts = path.split('/').filter((p: string) => p.length > 0);
    if (parts.length === 0) return this;
    for (let i = 0; i < this.elements.length; i++) {
      const node = this.elements[i];
      if (node instanceof Element && node.name === parts[0]) {
        if (parts.length === 1) {
          return docReplaceAt(this, i, f(elemDetached(node)));
        }
        const updated = pathCopyElement(node, parts.slice(1), f);
        if (updated !== null) {
          return docReplaceAt(this, i, updated);
        }
        return this;
      }
    }
    return this;
  }

  /** Return new Document with all matching elements replaced by f(element). */
  transformAll(expr: string, f: (el: Element) => Element): Document {
    const { cxpathParse, rebuildNode } = require('./cxpath');
    const cx = cxpathParse(expr);
    const newElements = this.elements.map((n: Node) => rebuildNode(n, cx, f));
    return new Document({ elements: newElements, prolog: this.prolog, doctype: this.doctype });
  }

  to_cx(): string {
    return _emitDoc(this);
  }

  to_xml(): string {
    return _toXml(this.to_cx());
  }

  to_json(): string {
    return _toJson(this.to_cx());
  }

  to_yaml(): string {
    return _toYaml(this.to_cx());
  }

  to_toml(): string {
    return _toToml(this.to_cx());
  }

  to_md(): string {
    return _toMd(this.to_cx());
  }
}

// ── Deserialization: AST JSON dict → native types ─────────────────────────────

function _nodeFromDict(d: any): Node {
  const t: string = d.type ?? '';
  if (t === 'Element') {
    return new Element({
      name: d.name,
      anchor: d.anchor ?? null,
      merge: d.merge ?? null,
      dataType: d.dataType ?? null,
      attrs: (d.attrs ?? []).map((a: any): Attr => ({
        name: a.name,
        value: a.value,
        dataType: a.dataType ?? null,
      })),
      items: (d.items ?? []).map(_nodeFromDict),
    });
  }
  if (t === 'Text') return new TextNode(d.value);
  if (t === 'Scalar') return new ScalarNode(d.dataType, d.value);
  if (t === 'Comment') return new CommentNode(d.value);
  if (t === 'RawText') return new RawTextNode(d.value);
  if (t === 'EntityRef') return new EntityRefNode(d.name);
  if (t === 'Alias') return new AliasNode(d.name);
  if (t === 'PI') return new PINode(d.target, d.data ?? null);
  if (t === 'XMLDecl') return new XMLDeclNode(d.version ?? '1.0', d.encoding ?? null, d.standalone ?? null);
  if (t === 'CXDirective') {
    return new CXDirectiveNode(
      (d.attrs ?? []).map((a: any): Attr => ({ name: a.name, value: a.value, dataType: null })),
    );
  }
  if (t === 'DoctypeDecl') return new DoctypeDeclNode(d.name, d.externalID ?? null, d.intSubset ?? []);
  if (t === 'BlockContent') return new BlockContentNode((d.items ?? []).map(_nodeFromDict));
  // unknown node — preserve as text
  return new TextNode(String(d));
}

function _docFromDict(d: any): Document {
  let doctype: DoctypeDeclNode | null = null;
  if (d.doctype) {
    const dt = d.doctype;
    doctype = new DoctypeDeclNode(dt.name, dt.externalID ?? null, dt.intSubset ?? []);
  }
  return new Document({
    prolog: (d.prolog ?? []).map(_nodeFromDict),
    doctype,
    elements: (d.elements ?? []).map(_nodeFromDict),
  });
}

// ── Public parse functions ────────────────────────────────────────────────────

/** Parse a CX string into a Document (uses binary protocol). */
export function parse(cxStr: string): Document {
  return _decodeAST(_toAstBin(cxStr));
}

/** Parse an XML string into a Document. */
export function parseXml(xmlStr: string): Document {
  return _docFromDict(JSON.parse(_xmlToAst(xmlStr)));
}

/** Parse a JSON string into a Document. */
export function parseJson(jsonStr: string): Document {
  return _docFromDict(JSON.parse(_jsonToAst(jsonStr)));
}

/** Parse a YAML string into a Document. */
export function parseYaml(yamlStr: string): Document {
  return _docFromDict(JSON.parse(_yamlToAst(yamlStr)));
}

/** Parse a TOML string into a Document. */
export function parseToml(tomlStr: string): Document {
  return _docFromDict(JSON.parse(_tomlToAst(tomlStr)));
}

/** Parse a Markdown string into a Document. */
export function parseMd(mdStr: string): Document {
  return _docFromDict(JSON.parse(_mdToAst(mdStr)));
}

// ── Data binding: loads / dumps ───────────────────────────────────────────────

/** Deserialize CX data string into native JS types (object/array/scalar). */
export function loads(cxStr: string): any {
  return JSON.parse(_toJson(cxStr));
}

/** Serialize native JS types (object/array/scalar) to a CX string. */
export function dumps(data: any): string {
  return _jsonToCx(JSON.stringify(data));
}

/** Deserialize an XML string into native JS types. */
export function loadsXml(xmlStr: string): any {
  return JSON.parse(_xmlToJson(xmlStr));
}

/** Deserialize a JSON string via the CX semantic bridge. */
export function loadsJson(jsonStr: string): any {
  return JSON.parse(_jsonToJson(jsonStr));
}

/** Deserialize a YAML string into native JS types. */
export function loadsYaml(yamlStr: string): any {
  return JSON.parse(_yamlToJson(yamlStr));
}

/** Deserialize a TOML string into native JS types. */
export function loadsToml(tomlStr: string): any {
  return JSON.parse(_tomlToJson(tomlStr));
}

/** Deserialize a Markdown string into native JS types. */
export function loadsMd(mdStr: string): any {
  return JSON.parse(_mdToJson(mdStr));
}

// ── CX emitter ────────────────────────────────────────────────────────────────

const _DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const _DATETIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;
const _HEX_RE = /^0[xX][0-9a-fA-F]+$/;

function _wouldAutotype(s: string): boolean {
  if (s.includes(' ')) return false;
  if (_HEX_RE.test(s)) return true;
  // integer check
  if (/^-?\d+$/.test(s)) return true;
  // float check
  if (s.includes('.') || s.toLowerCase().includes('e')) {
    if (!isNaN(Number(s)) && s.trim() !== '') return true;
  }
  if (s === 'true' || s === 'false' || s === 'null') return true;
  if (_DATETIME_RE.test(s)) return true;
  if (_DATE_RE.test(s)) return true;
  return false;
}

function _cxChooseQuote(s: string): string {
  if (!s.includes("'")) return `'${s}'`;
  if (!s.includes('"')) return `"${s}"`;
  if (!s.includes("'''")) return `'''${s}'''`;
  return `"${s}"`;  // best effort; embedded ''' stays as-is
}

function _cxQuoteText(s: string): string {
  const needs =
    s.startsWith(' ') || s.endsWith(' ') ||
    s.includes('  ') || s.includes('\n') || s.includes('\t') ||
    s.includes('[') || s.includes(']') || s.includes('&') ||
    s.startsWith(':') || s.startsWith("'") || s.startsWith('"') ||
    _wouldAutotype(s);
  return needs ? _cxChooseQuote(s) : s;
}

function _cxQuoteAttr(s: string): string {
  if (!s || s.includes(' ') || s.includes("'") || s.includes('"')) {
    return `'${s}'`;
  }
  return s;
}

function _emitScalar(s: ScalarNode): string {
  const v = s.value;
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') {
    if (Number.isInteger(v) && s.dataType !== 'float') return String(v);
    // float — ensure decimal point present
    const f = String(v);
    return (f.includes('.') || f.toLowerCase().includes('e')) ? f : f + '.0';
  }
  return String(v);
}

function _emitAttr(a: Attr): string {
  const dt = a.dataType;
  if (dt === 'int') return `${a.name}=${Math.trunc(Number(a.value))}`;
  if (dt === 'float') {
    const f = String(Number(a.value));
    const v = (f.includes('.') || f.toLowerCase().includes('e')) ? f : f + '.0';
    return `${a.name}=${v}`;
  }
  if (dt === 'bool') return `${a.name}=${a.value ? 'true' : 'false'}`;
  if (dt === 'null') return `${a.name}=null`;
  // string attr — quote if would autotype
  const s = String(a.value);
  const v = _wouldAutotype(s) ? _cxChooseQuote(s) : _cxQuoteAttr(s);
  return `${a.name}=${v}`;
}

function _emitInline(node: Node): string {
  if (node instanceof TextNode) {
    return node.value.trim() === '' ? '' : _cxQuoteText(node.value);
  }
  if (node instanceof ScalarNode) return _emitScalar(node);
  if (node instanceof EntityRefNode) return `&${node.name};`;
  if (node instanceof RawTextNode) return `[#${node.value}#]`;
  if (node instanceof Element) return _emitElement(node, 0).replace(/\n$/, '');
  if (node instanceof BlockContentNode) {
    const inner = node.items.map(n => {
      if (n instanceof TextNode) return n.value;
      if (n instanceof Element) return _emitElement(n, 0).replace(/\n$/, '');
      return '';
    }).join('');
    return `[|${inner}|]`;
  }
  return '';
}

function _emitElement(e: Element, depth: number): string {
  const ind = '  '.repeat(depth);
  const hasChildElems = e.items.some(i => i instanceof Element);
  const hasText = e.items.some(
    i => i instanceof TextNode || i instanceof ScalarNode ||
         i instanceof EntityRefNode || i instanceof RawTextNode,
  );
  const isMultiline = hasChildElems && !hasText;

  const metaParts: string[] = [];
  if (e.anchor) metaParts.push(`&${e.anchor}`);
  if (e.merge) metaParts.push(`*${e.merge}`);
  if (e.dataType) metaParts.push(`:${e.dataType}`);
  for (const a of e.attrs) metaParts.push(_emitAttr(a));
  const meta = metaParts.length > 0 ? (' ' + metaParts.join(' ')) : '';

  if (isMultiline) {
    let out = `${ind}[${e.name}${meta}\n`;
    for (const item of e.items) {
      out += _emitNode(item, depth + 1);
    }
    out += `${ind}]\n`;
    return out;
  }

  if (e.items.length === 0 && !meta) {
    return `${ind}[${e.name}]\n`;
  }

  const bodyParts = e.items.map(_emitInline).filter(p => p !== '');
  const body = bodyParts.join(' ');
  const sep = body ? ' ' : '';
  return `${ind}[${e.name}${meta}${sep}${body}]\n`;
}

function _emitNode(node: Node, depth: number): string {
  const ind = '  '.repeat(depth);
  if (node instanceof Element) return _emitElement(node, depth);
  if (node instanceof TextNode) return _cxQuoteText(node.value);
  if (node instanceof ScalarNode) return _emitScalar(node);
  if (node instanceof CommentNode) return `${ind}[-${node.value}]\n`;
  if (node instanceof RawTextNode) return `${ind}[#${node.value}#]\n`;
  if (node instanceof EntityRefNode) return `&${node.name};`;
  if (node instanceof AliasNode) return `${ind}[*${node.name}]\n`;
  if (node instanceof BlockContentNode) {
    const inner = node.items.map(i => _emitNode(i, 0)).join('');
    return `${ind}[|${inner}|]\n`;
  }
  if (node instanceof PINode) {
    const data = node.data ? ` ${node.data}` : '';
    return `${ind}[?${node.target}${data}]\n`;
  }
  if (node instanceof XMLDeclNode) {
    const parts = [`version=${node.version}`];
    if (node.encoding) parts.push(`encoding=${node.encoding}`);
    if (node.standalone) parts.push(`standalone=${node.standalone}`);
    return `[?xml ${parts.join(' ')}]\n`;
  }
  if (node instanceof CXDirectiveNode) {
    const attrStr = node.attrs.map(a => `${a.name}=${_cxQuoteAttr(String(a.value))}`).join(' ');
    return `[?cx ${attrStr}]\n`;
  }
  if (node instanceof DoctypeDeclNode) {
    let ext = '';
    if (node.externalID) {
      if ('public' in node.externalID) {
        const pub = node.externalID.public;
        const sys = node.externalID.system ?? '';
        ext = ` PUBLIC '${pub}' '${sys}'`;
      } else if ('system' in node.externalID) {
        ext = ` SYSTEM '${node.externalID.system}'`;
      }
    }
    return `[!DOCTYPE ${node.name}${ext}]\n`;
  }
  return '';
}

function _emitDoc(doc: Document): string {
  const parts: string[] = [];
  for (const node of doc.prolog) {
    parts.push(_emitNode(node, 0));
  }
  if (doc.doctype) {
    parts.push(_emitNode(doc.doctype, 0));
  }
  for (const node of doc.elements) {
    parts.push(_emitNode(node, 0));
  }
  return parts.join('').replace(/\n+$/, '');
}
