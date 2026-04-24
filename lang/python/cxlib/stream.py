"""CX streaming event API."""
from __future__ import annotations
import json
from dataclasses import dataclass, field
from typing import Any, Iterator, Optional
from . import cx as _cx


@dataclass
class Attr:
    name: str
    value: Any
    data_type: Optional[str] = None


@dataclass
class StreamEvent:
    type: str
    # StartElement fields
    name: Optional[str] = None
    attrs: list = field(default_factory=list)
    data_type: Optional[str] = None
    anchor: Optional[str] = None
    merge: Optional[str] = None
    # Scalar / Text / Comment / RawText / EntityRef / Alias fields
    value: Any = None
    # PI fields
    target: Optional[str] = None
    data: Optional[str] = None

    @classmethod
    def from_dict(cls, d: dict) -> 'StreamEvent':
        t = d.get('type', '')
        e = cls(type=t)
        if t == 'StartElement':
            e.name = d.get('name')
            e.attrs = [Attr(a['name'], a['value'], a.get('dataType')) for a in d.get('attrs', [])]
            e.data_type = d.get('dataType')
            e.anchor = d.get('anchor')
            e.merge = d.get('merge')
        elif t == 'EndElement':
            e.name = d.get('name')
        elif t in ('Text', 'Comment', 'RawText', 'Alias', 'EntityRef'):
            e.value = d.get('value') or d.get('name')
        elif t == 'Scalar':
            e.data_type = d.get('dataType')
            e.value = d.get('value')
        elif t == 'PI':
            e.target = d.get('target')
            e.data = d.get('data')
        return e

    def is_start_element(self, name: Optional[str] = None) -> bool:
        return self.type == 'StartElement' and (name is None or self.name == name)

    def is_end_element(self, name: Optional[str] = None) -> bool:
        return self.type == 'EndElement' and (name is None or self.name == name)


class Stream:
    """Iterator over CX streaming events.

    Usage:
        with cx.Stream('[config host=localhost]') as s:
            for event in s:
                if event.is_start_element():
                    print(event.name, event.attrs)
    """

    def __init__(self, cx_str: str):
        from .binary import events_bin, decode_events
        self._events: list = decode_events(events_bin(cx_str))
        self._pos = 0

    def __iter__(self) -> Iterator[StreamEvent]:
        return self

    def __next__(self) -> StreamEvent:
        if self._pos >= len(self._events):
            raise StopIteration
        e = self._events[self._pos]
        self._pos += 1
        return e

    def next(self) -> Optional[StreamEvent]:
        """Return next event or None when exhausted."""
        try:
            return self.__next__()
        except StopIteration:
            return None

    def collect(self) -> list:
        """Return all remaining events."""
        remaining = self._events[self._pos:]
        self._pos = len(self._events)
        return remaining

    def __enter__(self): return self
    def __exit__(self, *_): pass


def stream(cx_str: str) -> Stream:
    """Create a Stream from a CX string."""
    return Stream(cx_str)
