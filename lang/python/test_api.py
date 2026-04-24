#!/usr/bin/env python3
"""
Document API tests for lang/python/cxlib.

Fixtures are shared with all language bindings — see fixtures/ at the repo root.
Run:  python lang/python/test_api.py
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

# ── parse / root / get ────────────────────────────────────────────────────────

def test_parse_returns_document():
    doc = cxlib.parse(fx('api_config.cx'))
    assert isinstance(doc, cxlib.Document)

def test_root_returns_first_element():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.root().name == 'config'

def test_root_none_on_empty_input():
    doc = cxlib.parse('')
    assert doc.root() is None

def test_get_top_level_by_name():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.get('config').name == 'config'
    assert doc.get('missing') is None

def test_get_multi_top_level():
    doc = cxlib.parse(fx('api_multi.cx'))
    assert doc.get('service').attr('name') == 'auth'   # first match

def test_parse_multiple_top_level_elements():
    doc = cxlib.parse(fx('api_multi.cx'))
    services = [e for e in doc.elements if isinstance(e, cxlib.Element) and e.name == 'service']
    assert len(services) == 3

# ── attr ──────────────────────────────────────────────────────────────────────

def test_attr_string():
    srv = cxlib.parse(fx('api_config.cx')).at('config/server')
    assert srv.attr('host') == 'localhost'

def test_attr_int():
    srv = cxlib.parse(fx('api_config.cx')).at('config/server')
    assert srv.attr('port') == 8080
    assert isinstance(srv.attr('port'), int)

def test_attr_bool():
    srv = cxlib.parse(fx('api_config.cx')).at('config/server')
    assert srv.attr('debug') is False

def test_attr_float():
    srv = cxlib.parse(fx('api_config.cx')).at('config/server')
    assert abs(srv.attr('ratio') - 1.5) < 1e-9

def test_attr_missing_returns_none():
    srv = cxlib.parse(fx('api_config.cx')).at('config/server')
    assert srv.attr('nonexistent') is None

# ── scalar ────────────────────────────────────────────────────────────────────

def test_scalar_int():
    el = cxlib.parse(fx('api_scalars.cx')).at('values/count')
    assert el.scalar() == 42
    assert isinstance(el.scalar(), int)

def test_scalar_float():
    el = cxlib.parse(fx('api_scalars.cx')).at('values/ratio')
    assert abs(el.scalar() - 1.5) < 1e-9

def test_scalar_bool_true():
    el = cxlib.parse(fx('api_scalars.cx')).at('values/enabled')
    assert el.scalar() is True

def test_scalar_bool_false():
    el = cxlib.parse(fx('api_scalars.cx')).at('values/disabled')
    assert el.scalar() is False

def test_scalar_null():
    el = cxlib.parse(fx('api_scalars.cx')).at('values/nothing')
    assert el.scalar() is None

def test_scalar_none_on_element_with_children():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.root().scalar() is None   # config has children, not a scalar

# ── text ──────────────────────────────────────────────────────────────────────

def test_text_single_token():
    doc = cxlib.parse(fx('api_article.cx'))
    assert doc.at('article/body/h1').text() == 'Introduction'

def test_text_quoted():
    el = cxlib.parse(fx('api_scalars.cx')).at('values/label')
    assert el.text() == 'hello world'

def test_text_empty_on_element_with_children():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.root().text() == ''

# ── children / get_all ────────────────────────────────────────────────────────

def test_children_returns_only_elements():
    config = cxlib.parse(fx('api_config.cx')).root()
    kids = config.children()
    assert len(kids) == 3
    assert all(isinstance(k, cxlib.Element) for k in kids)
    assert [k.name for k in kids] == ['server', 'database', 'logging']

def test_get_all_direct_children():
    doc = cxlib.parse('[root [item 1] [item 2] [other x] [item 3]]')
    items = doc.root().get_all('item')
    assert len(items) == 3

def test_get_all_returns_empty_for_missing():
    config = cxlib.parse(fx('api_config.cx')).root()
    assert config.get_all('missing') == []

# ── at ────────────────────────────────────────────────────────────────────────

def test_at_single_segment():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.at('config').name == 'config'

def test_at_two_segments():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.at('config/server').name == 'server'
    assert doc.at('config/database').name == 'database'

def test_at_three_segments():
    doc = cxlib.parse(fx('api_article.cx'))
    assert doc.at('article/head/title').text() == 'Getting Started with CX'
    assert doc.at('article/body/h1').text() == 'Introduction'

def test_at_missing_segment_returns_none():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.at('config/missing') is None

def test_at_missing_root_returns_none():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.at('missing') is None

def test_at_deep_missing_returns_none():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.at('config/server/missing/deep') is None

def test_element_at_relative_path():
    doc = cxlib.parse(fx('api_article.cx'))
    body = doc.at('article/body')
    assert body.at('section/h2').text() == 'Details'

# ── find_all ──────────────────────────────────────────────────────────────────

def test_find_all_top_level():
    doc = cxlib.parse(fx('api_multi.cx'))
    assert len(doc.find_all('service')) == 3

def test_find_all_deep():
    doc = cxlib.parse(fx('api_article.cx'))
    ps = doc.find_all('p')
    assert len(ps) == 3
    assert ps[0].text() == 'First paragraph.'
    assert ps[1].text() == 'Nested paragraph.'
    assert ps[2].text() == 'Another nested paragraph.'

def test_find_all_missing_returns_empty():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.find_all('missing') == []

def test_find_all_on_element():
    body = cxlib.parse(fx('api_article.cx')).at('article/body')
    assert len(body.find_all('p')) == 3

# ── find_first ────────────────────────────────────────────────────────────────

def test_find_first_returns_first_match():
    doc = cxlib.parse(fx('api_article.cx'))
    p = doc.find_first('p')
    assert p is not None
    assert p.text() == 'First paragraph.'

def test_find_first_missing_returns_none():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.find_first('missing') is None

def test_find_first_depth_first_order():
    doc = cxlib.parse(fx('api_article.cx'))
    # h1 appears before h2 in depth-first traversal
    assert doc.find_first('h1').text() == 'Introduction'
    assert doc.find_first('h2').text() == 'Details'

def test_find_first_on_element():
    section = cxlib.parse(fx('api_article.cx')).at('article/body/section')
    p = section.find_first('p')
    assert p is not None
    assert p.text() == 'Nested paragraph.'

# ── mutation — Element ────────────────────────────────────────────────────────

def test_append_adds_to_end():
    doc = cxlib.parse(fx('api_config.cx'))
    doc.root().append(cxlib.Element(name='cache'))
    kids = doc.root().children()
    assert kids[-1].name == 'cache'
    assert len(kids) == 4

def test_prepend_adds_to_front():
    doc = cxlib.parse(fx('api_config.cx'))
    doc.root().prepend(cxlib.Element(name='meta'))
    assert doc.root().children()[0].name == 'meta'

def test_insert_at_index():
    doc = cxlib.parse('[root [a 1] [c 3]]')
    doc.root().insert(1, cxlib.Element(name='b'))
    assert [k.name for k in doc.root().children()] == ['a', 'b', 'c']

def test_insert_at_zero_is_prepend():
    doc = cxlib.parse('[root [a][c]]')
    doc.root().insert(0, cxlib.Element(name='b'))
    kids = doc.root().children()
    assert kids[0].name == 'b'
    assert kids[1].name == 'a'
    assert kids[2].name == 'c'

def test_remove_by_identity():
    doc = cxlib.parse(fx('api_config.cx'))
    db = doc.at('config/database')
    doc.root().remove(db)
    assert doc.at('config/database') is None
    assert doc.at('config/server') is not None

def test_remove_child_by_name():
    doc = cxlib.parse(fx('api_config.cx'))
    config = doc.at('config')
    config.remove_child('server')
    kids = config.children()
    assert len(kids) == 2
    assert not any(k.name == 'server' for k in kids)
    assert any(k.name == 'database' for k in kids)
    assert any(k.name == 'logging' for k in kids)

def test_remove_child_nonexistent_is_noop():
    doc = cxlib.parse(fx('api_config.cx'))
    config = doc.at('config')
    before_count = len(config.children())
    config.remove_child('nonexistent')
    assert len(config.children()) == before_count

def test_remove_at_removes_by_index():
    doc = cxlib.parse(fx('api_config.cx'))
    config = doc.at('config')
    assert len(config.children()) == 3
    first_name = config.children()[0].name
    config.remove_at(0)
    kids_after = config.children()
    assert len(kids_after) == 2
    assert not any(k.name == first_name for k in kids_after)

def test_remove_at_out_of_bounds_is_noop():
    doc = cxlib.parse(fx('api_config.cx'))
    config = doc.at('config')
    config.remove_at(100)
    assert len(config.children()) == 3

def test_set_attr_new():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.at('config/server')
    srv.set_attr('env', 'production')
    assert srv.attr('env') == 'production'

def test_set_attr_update_value():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.at('config/server')
    srv.set_attr('port', 9090, 'int')
    assert srv.attr('port') == 9090
    assert len(srv.attrs) == 4   # no duplicate; original count unchanged

def test_set_attr_change_type():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.at('config/server')
    original_count = len(srv.attrs)
    srv.set_attr('debug', True, 'bool')
    assert srv.attr('debug') is True
    assert len(srv.attrs) == original_count

def test_remove_attr():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.at('config/server')
    original_count = len(srv.attrs)
    srv.remove_attr('debug')
    assert srv.attr('debug') is None
    assert len(srv.attrs) == original_count - 1

def test_remove_attr_nonexistent_is_noop():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.at('config/server')
    original_count = len(srv.attrs)
    srv.remove_attr('nonexistent')
    assert len(srv.attrs) == original_count

# ── mutation — Document ───────────────────────────────────────────────────────

def test_doc_append_element():
    doc = cxlib.parse(fx('api_config.cx'))
    doc.append(cxlib.Element(name='cache', attrs=[cxlib.Attr('host', 'redis')]))
    assert doc.get('cache').attr('host') == 'redis'

def test_doc_prepend_makes_new_root():
    doc = cxlib.parse(fx('api_config.cx'))
    doc.prepend(cxlib.Element(name='preamble'))
    assert doc.root().name == 'preamble'
    assert doc.get('config') is not None   # original still present

# ── round-trips ───────────────────────────────────────────────────────────────

def test_to_cx_round_trip():
    original = cxlib.parse(fx('api_config.cx'))
    reparsed = cxlib.parse(original.to_cx())
    assert reparsed.at('config/server').attr('host') == 'localhost'
    assert reparsed.at('config/server').attr('port') == 8080
    assert reparsed.at('config/database').attr('name') == 'myapp'

def test_to_cx_round_trip_after_mutation():
    doc = cxlib.parse(fx('api_config.cx'))
    doc.at('config/server').set_attr('env', 'production')
    doc.at('config/server').append(cxlib.Element(
        name='timeout', items=[cxlib.Scalar('int', 30)]))
    reparsed = cxlib.parse(doc.to_cx())
    assert reparsed.at('config/server').attr('env') == 'production'
    assert reparsed.at('config/server').find_first('timeout').scalar() == 30

def test_to_cx_preserves_article_structure():
    original = cxlib.parse(fx('api_article.cx'))
    reparsed = cxlib.parse(original.to_cx())
    assert reparsed.at('article/head/title').text() == 'Getting Started with CX'
    assert len(reparsed.find_all('p')) == 3

# ── loads / dumps ─────────────────────────────────────────────────────────────

def test_loads_returns_dict():
    data = cxlib.loads(fx('api_config.cx'))
    assert isinstance(data, dict)
    assert data['config']['server']['host'] == 'localhost'
    assert data['config']['server']['port'] == 8080

def test_loads_bool_types():
    data = cxlib.loads(fx('api_config.cx'))
    assert data['config']['server']['debug'] is False

def test_loads_scalars():
    data = cxlib.loads(fx('api_scalars.cx'))
    assert data['values']['count'] == 42
    assert data['values']['enabled'] is True
    assert data['values']['disabled'] is False
    assert data['values']['nothing'] is None

def test_loads_xml():
    data = cxlib.loads_xml('<server host="localhost" port="8080"/>')
    assert 'server' in data

def test_loads_json_passthrough():
    data = cxlib.loads_json('{"port": 8080, "debug": false}')
    assert data['port'] == 8080
    assert data['debug'] is False

def test_loads_yaml():
    data = cxlib.loads_yaml('server:\n  host: localhost\n  port: 8080\n')
    assert 'server' in data

def test_dumps_produces_parseable_cx():
    original = {'app': {'name': 'myapp', 'version': '1.0', 'port': 8080}}
    cx_str = cxlib.dumps(original)
    reparsed = cxlib.parse(cx_str)
    assert reparsed.find_first('app') is not None

def test_loads_dumps_data_preserved():
    original = {'server': {'host': 'localhost', 'port': 8080, 'debug': False}}
    restored = cxlib.loads(cxlib.dumps(original))
    assert restored['server']['port'] == 8080
    assert restored['server']['host'] == 'localhost'
    assert restored['server']['debug'] is False

# ── error / failure cases ─────────────────────────────────────────────────────

def test_parse_error_unclosed_bracket():
    try:
        cxlib.parse(fx('errors/unclosed.cx'))
        assert False, 'expected parse error for unclosed bracket'
    except Exception:
        pass

def test_parse_error_empty_element_name():
    try:
        cxlib.parse(fx('errors/empty_name.cx'))
        assert False, 'expected parse error for empty element name'
    except Exception:
        pass

def test_parse_error_nested_unclosed():
    try:
        cxlib.parse(fx('errors/nested_unclosed.cx'))
        assert False, 'expected parse error for nested unclosed bracket'
    except Exception:
        pass

def test_at_missing_path_returns_none_not_error():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.at('config/server/missing/deep/path') is None  # no exception

def test_find_all_on_empty_doc_returns_empty():
    doc = cxlib.parse('')
    assert doc.find_all('anything') == []

def test_find_first_on_empty_doc_returns_none():
    doc = cxlib.parse('')
    assert doc.find_first('anything') is None

def test_scalar_none_when_element_has_child_elements():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.root().scalar() is None

def test_text_empty_when_no_text_children():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.root().text() == ''

def test_remove_attr_nonexistent_does_not_raise():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.at('config/server')
    srv.remove_attr('totally_missing')   # should not raise

def test_parse_xml_invalid():
    try:
        cxlib.parse_xml('<unclosed')
        assert False, 'expected parse error for invalid XML'
    except Exception:
        pass

# ── parse other formats ───────────────────────────────────────────────────────

def test_parse_xml():
    doc = cxlib.parse_xml('<root><child key="val"/></root>')
    assert doc.root().name == 'root'
    child = doc.find_first('child')
    assert child is not None

def test_parse_json_to_document():
    doc = cxlib.parse_json('{"server": {"port": 8080}}')
    assert doc.find_first('server') is not None

def test_parse_yaml_to_document():
    doc = cxlib.parse_yaml('server:\n  port: 8080\n')
    assert doc.find_first('server') is not None

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
    print(f'python/test_api.py: {_passed} passed, {_failed} failed  [{status}]')
    sys.exit(0 if _failed == 0 else 1)
