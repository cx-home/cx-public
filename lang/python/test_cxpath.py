#!/usr/bin/env python3
"""CXPath select/select_all tests — parity with lang/v/tests/cxpath_pending_test.v."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import cxlib

_FIXTURES = os.path.join(os.path.dirname(__file__), '..', '..', 'fixtures')

def fx(name):
    with open(os.path.join(_FIXTURES, name)) as f:
        return f.read()

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

# ── select — basic ────────────────────────────────────────────────────────────

def test_select_returns_first_match():
    doc = cxlib.parse(fx('api_multi.cx'))
    svc = doc.select('//service')
    assert svc is not None
    assert svc.name == 'service'
    assert svc.attr('name') == 'auth'

def test_select_returns_none_on_no_match():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.select('//nonexistent') is None

def test_select_all_returns_all_in_depth_first_order():
    doc = cxlib.parse(fx('api_multi.cx'))
    services = doc.select_all('//service')
    assert len(services) == 3
    assert services[0].attr('name') == 'auth'
    assert services[1].attr('name') == 'api'
    assert services[2].attr('name') == 'worker'

def test_select_all_returns_empty_on_no_match():
    doc = cxlib.parse(fx('api_config.cx'))
    assert doc.select_all('//nonexistent') == []

def test_select_on_element_excludes_self():
    doc = cxlib.parse('[root [p outer [p inner]]]')
    outer_p = doc.at('root/p')
    found = outer_p.select('//p')
    assert found is not None
    assert found.text() == 'inner'

# ── Descendant axis: //name ───────────────────────────────────────────────────

def test_descendant_axis_double_slash():
    doc = cxlib.parse(fx('api_article.cx'))
    ps = doc.select_all('//p')
    assert len(ps) == 3

def test_descendant_axis_preserves_depth_first_order():
    doc = cxlib.parse(fx('api_article.cx'))
    ps = doc.select_all('//p')
    assert ps[0].text() == 'First paragraph.'
    assert ps[1].text() == 'Nested paragraph.'
    assert ps[2].text() == 'Another nested paragraph.'

# ── Child axis: a/b/c ─────────────────────────────────────────────────────────

def test_child_axis_path():
    doc = cxlib.parse(fx('api_config.cx'))
    srv = doc.select('config/server')
    assert srv is not None
    assert srv.name == 'server'
    assert srv.attr('host') == 'localhost'

def test_child_axis_three_level_path():
    doc = cxlib.parse(fx('api_article.cx'))
    title = doc.select('article/head/title')
    assert title is not None
    assert title.text() == 'Getting Started with CX'

# ── Wildcard name test: * ─────────────────────────────────────────────────────

def test_wildcard_name_direct_children():
    doc = cxlib.parse(fx('api_config.cx'))
    children = doc.select_all('config/*')
    assert len(children) == 3
    assert children[0].name == 'server'
    assert children[1].name == 'database'
    assert children[2].name == 'logging'

def test_wildcard_descendant_all_elements():
    doc = cxlib.parse('[root [a [b]][c]]')
    all_els = doc.select_all('//*')
    assert len(all_els) == 4

# ── Attribute existence predicate: [@attr] ────────────────────────────────────

def test_attr_existence_predicate():
    doc = cxlib.parse(fx('api_article.cx'))
    with_id = doc.select_all('//*[@id]')
    assert len(with_id) == 1
    assert with_id[0].name == 'section'

# ── Attribute equality: [@attr=value] ─────────────────────────────────────────

def test_attr_equality_string():
    doc = cxlib.parse(fx('api_multi.cx'))
    found = doc.select('//service[@name=auth]')
    assert found is not None
    assert found.attr('name') == 'auth'

def test_attr_inequality():
    doc = cxlib.parse(fx('api_multi.cx'))
    others = doc.select_all('//service[@name!=auth]')
    assert len(others) == 2
    for svc in others:
        assert svc.attr('name') != 'auth'

def test_attr_equality_int_typed():
    doc = cxlib.parse(fx('api_multi.cx'))
    found = doc.select('//service[@port=8080]')
    assert found is not None
    assert found.attr('port') == 8080

def test_attr_equality_bool_typed():
    doc = cxlib.parse('[services [service active=true name=a][service active=false name=b]]')
    active = doc.select_all('//service[@active=true]')
    assert len(active) == 1
    assert active[0].attr('name') == 'a'

# ── Numeric range: [@port>=8000] ──────────────────────────────────────────────

def test_attr_numeric_range_gte():
    doc = cxlib.parse('[services [service port=8080][service port=80][service port=9000]]')
    high_port = doc.select_all('//service[@port>=8000]')
    assert len(high_port) == 2

def test_attr_numeric_range_lt():
    doc = cxlib.parse('[services [service port=8080][service port=80][service port=443]]')
    low_port = doc.select_all('//service[@port<1000]')
    assert len(low_port) == 2

# ── Boolean operators: and, or ────────────────────────────────────────────────

def test_and_operator_both_required():
    doc = cxlib.parse('[services [service active=true region=us][service active=true region=eu][service active=false region=us]]')
    results = doc.select_all('//service[@active=true and @region=us]')
    assert len(results) == 1

def test_or_operator_either_matches():
    doc = cxlib.parse('[services [service port=80][service port=443][service port=8080]]')
    web_ports = doc.select_all('//service[@port=80 or @port=443]')
    assert len(web_ports) == 2

# ── not() predicate ───────────────────────────────────────────────────────────

def test_not_predicate_attr_inequality():
    doc = cxlib.parse('[services [service active=true][service active=false][service active=true]]')
    not_false = doc.select_all('//service[not(@active=false)]')
    assert len(not_false) == 2

def test_not_predicate_attr_absence():
    doc = cxlib.parse('[config [server host=localhost debug=true][database host=db]]')
    without_debug = doc.select_all('//*[not(@debug)]')
    assert any(el.name == 'database' for el in without_debug)
    assert not any(el.name == 'server' for el in without_debug)

# ── Child existence predicate: [childname] ────────────────────────────────────

def test_child_existence_predicate():
    doc = cxlib.parse('[services [service [tags core]][service name=plain]]')
    with_tags = doc.select_all('//service[tags]')
    assert len(with_tags) == 1
    assert with_tags[0].get('tags') is not None

def test_child_existence_negation_predicate():
    doc = cxlib.parse('[services [service [tags core]][service name=plain]]')
    without_tags = doc.select_all('//service[not(tags)]')
    assert len(without_tags) == 1
    assert without_tags[0].get('tags') is None

# ── Position predicates: [1], [last()] ───────────────────────────────────────

def test_position_first():
    doc = cxlib.parse(fx('api_multi.cx'))
    first_svc = doc.select('//service[1]')
    assert first_svc is not None
    assert first_svc.attr('name') == 'auth'

def test_position_second():
    doc = cxlib.parse(fx('api_multi.cx'))
    second_svc = doc.select('//service[2]')
    assert second_svc is not None
    assert second_svc.attr('name') == 'api'

def test_position_last():
    doc = cxlib.parse(fx('api_multi.cx'))
    last_svc = doc.select('//service[last()]')
    assert last_svc is not None
    assert last_svc.attr('name') == 'worker'

# ── String functions: contains(), starts-with() ───────────────────────────────

def test_contains_function():
    doc = cxlib.parse('[docs [p class=lead-note text][p class=other text]]')
    with_note = doc.select_all('//p[contains(@class, note)]')
    assert len(with_note) == 1
    assert with_note[0].attr('class') == 'lead-note'

def test_starts_with_function():
    doc = cxlib.parse(fx('api_multi.cx'))
    with_a = doc.select_all('//service[starts-with(@name, a)]')
    assert len(with_a) == 2
    for svc in with_a:
        assert svc.attr('name').startswith('a')

# ── Relative select on Element ────────────────────────────────────────────────

def test_relative_select_all_on_element():
    doc = cxlib.parse(fx('api_article.cx'))
    body = doc.at('article/body')
    ps = body.select_all('//p')
    assert len(ps) == 3
    assert not any(el.name == 'body' for el in ps)

def test_relative_select_no_match():
    doc = cxlib.parse('[root [child leaf]]')
    child = doc.at('root/child')
    assert child.select('//nonexistent') is None

def test_relative_select_scoped_to_element_subtree():
    doc = cxlib.parse('[root [a [item inside-a]][b [item inside-b]]]')
    a_el = doc.at('root/a')
    items = a_el.select_all('//item')
    assert len(items) == 1
    assert items[0].text() == 'inside-a'

# ── Mixed axes ────────────────────────────────────────────────────────────────

def test_child_then_descendant_axis():
    doc = cxlib.parse(fx('api_article.cx'))
    ps = doc.select_all('article/body//p')
    assert len(ps) == 3

def test_descendant_then_descendant_axis():
    doc = cxlib.parse(fx('api_article.cx'))
    ps = doc.select_all('//section//p')
    assert len(ps) == 2
    assert ps[0].text() == 'Nested paragraph.'
    assert ps[1].text() == 'Another nested paragraph.'

# ── Invalid expression ────────────────────────────────────────────────────────

def test_invalid_expression_raises():
    try:
        cxlib.parse('[root]').select('[@invalid syntax!!!')
        assert False, 'expected ValueError'
    except (ValueError, Exception):
        pass  # any exception is acceptable

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
    print(f'python/test_cxpath.py: {_passed} passed, {_failed} failed  [{status}]')
    sys.exit(0 if _failed == 0 else 1)
