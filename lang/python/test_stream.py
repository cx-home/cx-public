#!/usr/bin/env python3
"""
Streaming API tests for lang/python/cxlib.

Fixtures are shared with all language bindings — see fixtures/ at the repo root.
Run:  python lang/python/test_stream.py
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import cxlib

# ── fixture loader ────────────────────────────────────────────────────────────

_FIXTURES = os.path.join(os.path.dirname(__file__), '..', '..', 'fixtures')

def fx(name):
    with open(os.path.join(_FIXTURES, name)) as f:
        return f.read()

# ── test runner ───────────────────────────────────────────────────────────────

_passed = 0
_failed = 0

def _run(fn):
    global _passed, _failed
    try:
        fn()
        _passed += 1
    except AssertionError as e:
        _failed += 1
        print(f'  FAIL  {fn.__name__}: {e}')
    except Exception as e:
        _failed += 1
        print(f'  ERROR {fn.__name__}: {type(e).__name__}: {e}')

# ── streaming tests ───────────────────────────────────────────────────────────

def test_stream_basic():
    s = cxlib.stream('[config]')
    events = list(s)
    types = [e.type for e in events]
    assert types == ['StartDoc', 'StartElement', 'EndElement', 'EndDoc'], types
    assert events[1].name == 'config'
    assert events[2].name == 'config'

def test_stream_attrs():
    s = cxlib.stream('[server host=localhost port=8080]')
    events = list(s)
    start = next(e for e in events if e.type == 'StartElement')
    assert start.name == 'server'
    assert len(start.attrs) == 2
    host_attr = start.attrs[0]
    assert host_attr.name == 'host'
    assert host_attr.value == 'localhost'
    port_attr = start.attrs[1]
    assert port_attr.name == 'port'
    assert port_attr.value == 8080
    assert port_attr.data_type == 'int'

def test_stream_text():
    s = cxlib.stream('[p Hello world]')
    events = list(s)
    types = [e.type for e in events]
    assert 'Text' in types, types
    text_event = next(e for e in events if e.type == 'Text')
    assert text_event.value == 'Hello world'

def test_stream_scalar():
    s = cxlib.stream('[count :int 42]')
    events = list(s)
    scalar = next(e for e in events if e.type == 'Scalar')
    assert scalar.data_type == 'int'
    assert scalar.value == 42

def test_stream_nested():
    s = cxlib.stream('[outer [inner]]')
    events = list(s)
    types = [e.type for e in events]
    # outer start before inner start, inner end before outer end
    outer_start = next(i for i, e in enumerate(events) if e.type == 'StartElement' and e.name == 'outer')
    inner_start = next(i for i, e in enumerate(events) if e.type == 'StartElement' and e.name == 'inner')
    inner_end = next(i for i, e in enumerate(events) if e.type == 'EndElement' and e.name == 'inner')
    outer_end = next(i for i, e in enumerate(events) if e.type == 'EndElement' and e.name == 'outer')
    assert outer_start < inner_start < inner_end < outer_end

def test_stream_collect():
    s = cxlib.stream('[config]')
    # consume StartDoc manually
    first = s.next()
    assert first.type == 'StartDoc'
    # collect remaining
    remaining = s.collect()
    assert len(remaining) == 3
    assert remaining[0].type == 'StartElement'
    assert remaining[-1].type == 'EndDoc'
    # collect again → empty
    assert s.collect() == []

def test_stream_next_method():
    s = cxlib.stream('[a]')
    events = []
    while True:
        e = s.next()
        if e is None:
            break
        events.append(e)
    assert len(events) == 4  # StartDoc, StartElement, EndElement, EndDoc
    assert s.next() is None  # returns None repeatedly after exhaustion

def test_stream_context_manager():
    result = []
    with cxlib.stream('[config host=localhost]') as s:
        for event in s:
            result.append(event.type)
    assert 'StartDoc' in result
    assert 'EndDoc' in result
    assert 'StartElement' in result

def test_stream_comment():
    # CX comment syntax: [-text]
    s = cxlib.stream('[root [-a comment][child]]')
    events = list(s)
    types = [e.type for e in events]
    assert 'Comment' in types, types
    comment = next(e for e in events if e.type == 'Comment')
    assert comment.value == 'a comment'

def test_stream_pi():
    # CX PI syntax: [?target data]
    s = cxlib.stream('[root [?php return 42]]')
    events = list(s)
    types = [e.type for e in events]
    assert 'PI' in types, types
    pi = next(e for e in events if e.type == 'PI')
    assert pi.target == 'php'
    assert pi.data == 'return 42'

def test_stream_entity_ref():
    s = cxlib.stream('[root &amp;]')
    events = list(s)
    types = [e.type for e in events]
    assert 'EntityRef' in types, types
    er = next(e for e in events if e.type == 'EntityRef')
    assert er.value == 'amp'

def test_stream_multiple_top_level():
    s = cxlib.stream(fx('api_multi.cx'))
    events = list(s)
    service_starts = [e for e in events if e.type == 'StartElement' and e.name == 'service']
    assert len(service_starts) == 3, len(service_starts)

def test_stream_deep_nesting():
    s = cxlib.stream(fx('api_article.cx'))
    events = list(s)
    assert len(events) == 32, len(events)
    assert events[0].type == 'StartDoc'
    assert events[-1].type == 'EndDoc'

def test_stream_is_start_element():
    s = cxlib.stream('[config host=localhost]')
    events = list(s)
    config_start = next((e for e in events if e.is_start_element('config')), None)
    assert config_start is not None
    assert config_start.attrs[0].value == 'localhost'
    # is_start_element with wrong name returns False
    assert not any(e.is_start_element('other') for e in events)
    # is_start_element with no name matches any start element
    assert any(e.is_start_element() for e in events)

def test_stream_is_end_element():
    s = cxlib.stream('[config]')
    events = list(s)
    end = next((e for e in events if e.is_end_element('config')), None)
    assert end is not None
    # is_end_element with no name matches any end element
    assert any(e.is_end_element() for e in events)
    # is_end_element with wrong name returns False
    assert not any(e.is_end_element('other') for e in events)

def test_stream_event_types():
    s = cxlib.stream(fx('api_article.cx'))
    types = {e.type for e in s}
    # api_article.cx has these types
    assert 'StartDoc' in types
    assert 'EndDoc' in types
    assert 'StartElement' in types
    assert 'EndElement' in types
    assert 'Text' in types
    assert 'Scalar' in types  # from [tags :string[] tutorial beginner]

def test_stream_parse_error():
    try:
        cxlib.stream(fx('errors/unclosed.cx'))
        assert False, 'expected RuntimeError for unclosed bracket'
    except RuntimeError:
        pass

# ── fixture-based streaming tests (stream/stream_events.cx) ──────────────────

def test_stream_events_all_types():
    types = {e.type for e in cxlib.stream(fx('stream/stream_events.cx'))}
    for want in ['StartDoc', 'EndDoc', 'StartElement', 'EndElement', 'Text',
                 'Scalar', 'Comment', 'PI', 'EntityRef', 'RawText', 'Alias']:
        assert want in types, f'missing event type: {want}'

def test_stream_events_comment():
    events = list(cxlib.stream(fx('stream/stream_events.cx')))
    comments = [e for e in events if e.type == 'Comment']
    assert len(comments) == 1
    assert comments[0].value == 'a comment node'

def test_stream_events_pi():
    events = list(cxlib.stream(fx('stream/stream_events.cx')))
    pis = [e for e in events if e.type == 'PI']
    assert len(pis) == 1
    assert pis[0].target == 'pi'
    assert pis[0].data == 'pi data here'

def test_stream_events_scalars():
    events = list(cxlib.stream(fx('stream/stream_events.cx')))
    scalars = [e for e in events if e.type == 'Scalar']
    assert len(scalars) == 2
    assert scalars[0].data_type == 'int'
    assert scalars[0].value == 42
    assert scalars[1].data_type == 'bool'
    assert scalars[1].value == True

def test_stream_events_alias():
    events = list(cxlib.stream(fx('stream/stream_events.cx')))
    aliases = [e for e in events if e.type == 'Alias']
    assert len(aliases) == 1
    assert aliases[0].value == 'srv'

def test_stream_nested_depth():
    events = list(cxlib.stream(fx('stream/stream_nested.cx')))
    starts = [e for e in events if e.type == 'StartElement']
    names = [e.name for e in starts]
    assert 'level1' in names
    assert 'level6' in names
    assert len(starts) == 8, f'expected 8 start elements, got {len(starts)}: {names}'

# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    module = sys.modules[__name__]
    fns = sorted(
        [v for k, v in vars(module).items() if k.startswith('test_') and callable(v)],
        key=lambda f: f.__code__.co_firstlineno,
    )
    for fn in fns:
        _run(fn)
    total = _passed + _failed
    status = 'OK' if _failed == 0 else 'FAILED'
    print(f'python/test_stream.py: {_passed} passed, {_failed} failed  [{status}]')
    sys.exit(0 if _failed == 0 else 1)
