/**
 * Binary wire protocol decoder for cx_to_ast_bin and cx_to_events_bin.
 *
 * Buffer layout: [u32 LE: payload_size][payload bytes]
 * All integers little-endian.
 * String:  u32(byte_len) + raw UTF-8 bytes (no null terminator)
 * OptStr:  u8(0=absent, 1=present) + str if present
 * Attr:    str:name + str:value_str + str:inferred_type
 */

import {
  Attr,
  Document,
  Element,
  TextNode,
  ScalarNode,
  CommentNode,
  RawTextNode,
  EntityRefNode,
  AliasNode,
  PINode,
  XMLDeclNode,
  CXDirectiveNode,
  BlockContentNode,
  Node,
} from './ast';

// ── StreamEvent type ──────────────────────────────────────────────────────────

export interface StreamEvent {
  type: string;
  name?: string;
  anchor?: string | null;
  dataType?: string | null;
  merge?: string | null;
  attrs?: Attr[];
  value?: any;
  target?: string;
  data?: string | null;
}

// ── scalar coercion ───────────────────────────────────────────────────────────

function coerce(typeStr: string, valueStr: string): any {
  if (typeStr === 'int') return parseInt(valueStr, 10);
  if (typeStr === 'float') return parseFloat(valueStr);
  if (typeStr === 'bool') return valueStr === 'true';
  if (typeStr === 'null') return null;
  return valueStr;  // string / date / datetime / bytes
}

// ── buffer reader ─────────────────────────────────────────────────────────────

class BufReader {
  private pos: number = 0;

  constructor(private readonly buf: Buffer) {}

  u8(): number {
    return this.buf.readUInt8(this.pos++);
  }

  u16(): number {
    const v = this.buf.readUInt16LE(this.pos);
    this.pos += 2;
    return v;
  }

  u32(): number {
    const v = this.buf.readUInt32LE(this.pos);
    this.pos += 4;
    return v;
  }

  str(): string {
    const len = this.buf.readUInt32LE(this.pos);
    this.pos += 4;
    const s = this.buf.toString('utf8', this.pos, this.pos + len);
    this.pos += len;
    return s;
  }

  optstr(): string | null {
    const flag = this.buf.readUInt8(this.pos++);
    if (!flag) return null;
    const len = this.buf.readUInt32LE(this.pos);
    this.pos += 4;
    const s = this.buf.toString('utf8', this.pos, this.pos + len);
    this.pos += len;
    return s;
  }
}

// ── AST decoder ───────────────────────────────────────────────────────────────

function readAttr(b: BufReader): Attr {
  const name = b.str();
  const valueStr = b.str();
  const typeStr = b.str();
  const dt = typeStr !== 'string' ? typeStr : null;
  return { name, value: coerce(typeStr, valueStr), dataType: dt };
}

function readNode(b: BufReader): Node {
  const tid = b.u8();

  if (tid === 0x01) {
    const name = b.str();
    const anchor = b.optstr();
    const dataType = b.optstr();
    const merge = b.optstr();
    const attrCount = b.u16();
    const attrs: Attr[] = [];
    for (let i = 0; i < attrCount; i++) attrs.push(readAttr(b));
    const childCount = b.u16();
    const items: Node[] = [];
    for (let i = 0; i < childCount; i++) items.push(readNode(b));
    return new Element({ name, anchor, dataType, merge, attrs, items });
  }
  if (tid === 0x02) return new TextNode(b.str());
  if (tid === 0x03) {
    const dt = b.str();
    return new ScalarNode(dt, coerce(dt, b.str()));
  }
  if (tid === 0x04) return new CommentNode(b.str());
  if (tid === 0x05) return new RawTextNode(b.str());
  if (tid === 0x06) return new EntityRefNode(b.str());
  if (tid === 0x07) return new AliasNode(b.str());
  if (tid === 0x08) {
    const target = b.str();
    const data = b.optstr();
    return new PINode(target, data);
  }
  if (tid === 0x09) {
    const version = b.str();
    const encoding = b.optstr();
    const standalone = b.optstr();
    return new XMLDeclNode(version, encoding, standalone);
  }
  if (tid === 0x0A) {
    const count = b.u16();
    const attrs: Attr[] = [];
    for (let i = 0; i < count; i++) attrs.push(readAttr(b));
    return new CXDirectiveNode(attrs);
  }
  if (tid === 0x0C) {
    const count = b.u16();
    const items: Node[] = [];
    for (let i = 0; i < count; i++) items.push(readNode(b));
    return new BlockContentNode(items);
  }
  // 0xFF = skip / unknown (no payload)
  return new TextNode('');
}

export function decodeAST(data: Buffer): Document {
  const b = new BufReader(data);
  b.u8(); // version byte
  const prologCount = b.u16();
  const prolog: Node[] = [];
  for (let i = 0; i < prologCount; i++) prolog.push(readNode(b));
  const elemCount = b.u16();
  const elements: Node[] = [];
  for (let i = 0; i < elemCount; i++) elements.push(readNode(b));
  return new Document({ prolog, elements });
}

// ── Events decoder ────────────────────────────────────────────────────────────

const EVT_NAMES: Record<number, string> = {
  0x01: 'StartDoc',
  0x02: 'EndDoc',
  0x03: 'StartElement',
  0x04: 'EndElement',
  0x05: 'Text',
  0x06: 'Scalar',
  0x07: 'Comment',
  0x08: 'PI',
  0x09: 'EntityRef',
  0x0A: 'RawText',
  0x0B: 'Alias',
};

export function decodeEvents(data: Buffer): StreamEvent[] {
  const b = new BufReader(data);
  const n = b.u32();
  const events: StreamEvent[] = [];

  for (let i = 0; i < n; i++) {
    const tid = b.u8();
    const type = EVT_NAMES[tid] ?? 'Unknown';
    const e: StreamEvent = { type };

    if (tid === 0x03) {
      // StartElement
      e.name = b.str();
      e.anchor = b.optstr();
      e.dataType = b.optstr();
      e.merge = b.optstr();
      const nAttrs = b.u16();
      const attrs: Attr[] = [];
      for (let j = 0; j < nAttrs; j++) {
        const aName = b.str();
        const aValStr = b.str();
        const aType = b.str();
        const dt = aType !== 'string' ? aType : null;
        attrs.push({ name: aName, value: coerce(aType, aValStr), dataType: dt });
      }
      e.attrs = attrs;
    } else if (tid === 0x04) {
      // EndElement
      e.name = b.str();
    } else if (tid === 0x05 || tid === 0x07 || tid === 0x0A) {
      // Text / Comment / RawText
      e.value = b.str();
    } else if (tid === 0x06) {
      // Scalar
      const dt = b.str();
      e.dataType = dt;
      e.value = coerce(dt, b.str());
    } else if (tid === 0x08) {
      // PI
      e.target = b.str();
      e.data = b.optstr();
    } else if (tid === 0x09 || tid === 0x0B) {
      // EntityRef / Alias
      e.value = b.str();
    }
    // 0x01 StartDoc, 0x02 EndDoc: no payload

    events.push(e);
  }

  return events;
}
