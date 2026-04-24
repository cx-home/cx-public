#!/usr/bin/env python3
"""Transform / transform_all tests — parity with lang/v/tests/transform_pending_test.v."""
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

# ── transform ─────────────────────────────────────────────────────────────────

def test_transform_returns_new_document():
    doc = cxlib.parse(fx('api_config.cx'))
    def set_newhost(el):
        el.set_attr('host', 'newhost')
        return el
    updated = doc.transform('config/server', set_newhost)
    assert updated.at('config/server').attr('host') == 'newhost'

def test_transform_applies_function_to_element_at_path():
    doc = cxlib.parse(fx('api_config.cx'))
    def set_transformed(el):
        el.set_attr('host', 'transformed')
        return el
    updated = doc.transform('config/server', set_transformed)
    srv = updated.at('config/server')
    assert srv.attr('host') == 'transformed'
    assert srv.attr('port') == 8080

def test_transform_original_document_unchanged():
    doc = cxlib.parse(fx('api_config.cx'))
    def set_changed(el):
        el.set_attr('host', 'changed')
        return el
    doc.transform('config/server', set_changed)
    assert doc.at('config/server').attr('host') == 'localhost'

def test_transform_missing_path_returns_original_unchanged():
    doc = cxlib.parse(fx('api_config.cx'))
    updated = doc.transform('config/nonexistent', lambda el: el)
    assert updated.at('config/server').attr('host') == 'localhost'
    assert updated.at('config/nonexistent') is None

def test_transform_chained_transforms():
    doc = cxlib.parse(fx('api_config.cx'))
    def set_host1(el):
        el.set_attr('host', 'host1')
        return el
    def set_host2(el):
        el.set_attr('host', 'host2')
        return el
    updated = doc.transform('config/server', set_host1).transform('config/database', set_host2)
    assert updated.at('config/server').attr('host') == 'host1'
    assert updated.at('config/database').attr('host') == 'host2'
    assert doc.at('config/server').attr('host') == 'localhost'

# ── transform_all ─────────────────────────────────────────────────────────────

def test_transform_all_applies_to_all_matching_elements():
    doc = cxlib.parse(fx('api_multi.cx'))
    def activate(el):
        el.set_attr('active', True)
        return el
    updated = doc.transform_all('//service', activate)
    services = updated.find_all('service')
    assert len(services) == 3
    for svc in services:
        assert svc.attr('active') is True

def test_transform_all_returns_new_document():
    doc = cxlib.parse(fx('api_multi.cx'))
    def set_version(el):
        el.set_attr('version', 2)
        return el
    updated = doc.transform_all('//service', set_version)
    for svc in updated.find_all('service'):
        assert svc.attr('version') == 2
    for svc in doc.find_all('service'):
        assert svc.attr('version') is None

def test_transform_all_no_matches_returns_original():
    doc = cxlib.parse(fx('api_config.cx'))
    updated = doc.transform_all('//nonexistent', lambda el: el)
    assert updated.at('config/server').attr('host') == 'localhost'
    assert updated.find_all('nonexistent') == []

def test_transform_all_applies_to_deeply_nested_matches():
    doc = cxlib.parse(fx('api_article.cx'))
    def mark_visited(el):
        el.set_attr('visited', True)
        return el
    updated = doc.transform_all('//p', mark_visited)
    updated_ps = updated.find_all('p')
    assert len(updated_ps) == 3, f'expected 3 p elements in updated doc, got {len(updated_ps)}'
    for p in updated_ps:
        assert p.attr('visited') is True
    for p in doc.find_all('p'):
        assert p.attr('visited') is None

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
    print(f'python/test_transform.py: {_passed} passed, {_failed} failed  [{status}]')
    sys.exit(0 if _failed == 0 else 1)
