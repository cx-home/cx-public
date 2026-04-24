"""
Binary wire protocol decoder for cx_to_ast_bin and cx_to_events_bin.

Buffer returned by C:
  [u32 LE: payload_size][payload bytes]

All integers little-endian.
Strings:  u32(byte_len) + raw UTF-8 bytes  (no null terminator)
OptStr:   u8(0|1) + str if 1
Attr:     str:name  str:value  str:inferred_type
"""
from __future__ import annotations
import struct
import ctypes
from typing import Any, Optional
from . import cx as _cx
from .ast import (Attr, Document, Element, Text, Scalar, Comment, RawText,
                  EntityRef, Alias, PI, XMLDecl, CXDirective, BlockContent)
from .stream import StreamEvent, Attr as SAttr


# ── scalar coercion ───────────────────────────────────────────────────────────

def _coerce(type_str: str, value_str: str) -> Any:
    if type_str == 'int':
        return int(value_str)
    if type_str == 'float':
        return float(value_str)
    if type_str == 'bool':
        return value_str == 'true'
    if type_str == 'null':
        return None
    return value_str  # string / date / datetime / bytes


# ── buffer reader ─────────────────────────────────────────────────────────────

_UNP_I = struct.Struct('<I')
_UNP_H = struct.Struct('<H')


class _Buf:
    __slots__ = ('_d', '_p')

    def __init__(self, data: bytes):
        self._d = data
        self._p = 0

    def u8(self) -> int:
        p = self._p; self._p = p + 1; return self._d[p]

    def u16(self) -> int:
        p = self._p; self._p = p + 2; return _UNP_H.unpack_from(self._d, p)[0]

    def u32(self) -> int:
        p = self._p; self._p = p + 4; return _UNP_I.unpack_from(self._d, p)[0]

    def str_(self) -> str:
        p = self._p
        n = _UNP_I.unpack_from(self._d, p)[0]
        p += 4
        self._p = p + n
        return self._d[p:p + n].decode('utf-8')

    def optstr(self) -> Optional[str]:
        p = self._p
        flag = self._d[p]
        self._p = p + 1
        if not flag:
            return None
        p = self._p
        n = _UNP_I.unpack_from(self._d, p)[0]
        p += 4
        self._p = p + n
        return self._d[p:p + n].decode('utf-8')


# ── AST decoder — builds Document/Element/Node objects directly ───────────────

def _read_attr(b: _Buf):
    name = b.str_()
    value_str = b.str_()
    t = b.str_()
    # Pass data_type so the CX emitter formats int/float/bool/null correctly.
    dt = t if t != 'string' else None
    return Attr(name, _coerce(t, value_str), dt)


def _read_node(b: _Buf):
    tid = b.u8()
    if tid == 0x01:
        name   = b.str_()
        anchor = b.optstr()
        dt     = b.optstr()
        merge  = b.optstr()
        attrs  = [_read_attr(b) for _ in range(b.u16())]
        items  = [_read_node(b) for _ in range(b.u16())]
        return Element(name, anchor, merge, dt, attrs, items)
    if tid == 0x02:
        return Text(b.str_())
    if tid == 0x03:
        t = b.str_(); return Scalar(t, _coerce(t, b.str_()))
    if tid == 0x04:
        return Comment(b.str_())
    if tid == 0x05:
        return RawText(b.str_())
    if tid == 0x06:
        return EntityRef(b.str_())
    if tid == 0x07:
        return Alias(b.str_())
    if tid == 0x08:
        target = b.str_(); data = b.optstr()
        return PI(target, data)
    if tid == 0x09:
        version = b.str_(); encoding = b.optstr(); standalone = b.optstr()
        return XMLDecl(version, encoding, standalone)
    if tid == 0x0A:
        return CXDirective([_read_attr(b) for _ in range(b.u16())])
    if tid == 0x0C:
        return BlockContent([_read_node(b) for _ in range(b.u16())])
    # 0xFF = unknown/DTD skip — no payload
    return Text('')


def decode_ast(raw: bytes):
    b = _Buf(raw)
    _ver    = b.u8()
    prolog  = [_read_node(b) for _ in range(b.u16())]
    elements = [_read_node(b) for _ in range(b.u16())]
    return Document(prolog=prolog, elements=elements)


# ── Events decoder — builds StreamEvent objects directly ──────────────────────

_EVT = {
    0x01: 'StartDoc', 0x02: 'EndDoc', 0x03: 'StartElement',
    0x04: 'EndElement', 0x05: 'Text', 0x06: 'Scalar',
    0x07: 'Comment', 0x08: 'PI', 0x09: 'EntityRef',
    0x0A: 'RawText', 0x0B: 'Alias',
}


def decode_events(raw: bytes) -> list:
    b = _Buf(raw)
    n = b.u32()
    events = []
    for _ in range(n):
        tid = b.u8()
        t = _EVT.get(tid, 'Unknown')
        e = StreamEvent(type=t)
        if tid == 0x03:
            e.name   = b.str_()
            e.anchor = b.optstr()
            e.data_type = b.optstr()
            merge = b.optstr()
            n_attrs = b.u16()
            e.attrs = []
            for _ in range(n_attrs):
                name = b.str_()
                val_str = b.str_()
                typ = b.str_()
                e.attrs.append(SAttr(name, _coerce(typ, val_str), typ))
        elif tid == 0x04:
            e.name = b.str_()
        elif tid in (0x05, 0x07, 0x0A):
            e.value = b.str_()
        elif tid == 0x06:
            dt = b.str_(); e.data_type = dt; e.value = _coerce(dt, b.str_())
        elif tid == 0x08:
            e.target = b.str_(); e.data = b.optstr()
        elif tid in (0x09, 0x0B):
            e.value = b.str_()
        events.append(e)
    return events


# ── C ABI bridge ──────────────────────────────────────────────────────────────
# Binary functions have restype=c_void_p (set in cx.py), so they return an
# integer address rather than auto-converting to bytes like c_char_p would.

def _call_bin(fn, cx_str: str) -> bytes:
    err = ctypes.c_char_p(None)
    addr = fn(cx_str.encode(), ctypes.byref(err))  # int address or None
    if addr is None:
        raise RuntimeError(err.value.decode() if err.value else 'unknown error')
    size = struct.unpack_from('<I', ctypes.string_at(addr, 4))[0]
    payload = bytes(ctypes.string_at(addr + 4, size))
    _cx._lib.cx_free(ctypes.cast(addr, ctypes.c_char_p))
    return payload


def ast_bin(cx_str: str) -> bytes:
    return _call_bin(_cx._lib.cx_to_ast_bin, cx_str)


def events_bin(cx_str: str) -> bytes:
    return _call_bin(_cx._lib.cx_to_events_bin, cx_str)
