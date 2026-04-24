#!/usr/bin/env python3
"""
Immutability contract tests for the Python binding.

Python uses reference semantics: doc.at() returns the actual Element object,
so direct mutation (set_attr, append, etc.) affects the document. That is
expected Python behaviour.

These tests verify the transform/transform_all guarantee: calling transform
returns a NEW Document, and the original document's tree is left untouched at
the transformed path.
"""
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

# ── transform immutability ────────────────────────────────────────────────────

def test_transform_returns_different_document_object():
    doc = cxlib.parse(fx('api_config.cx'))
    updated = doc.transform('config/server', lambda el: el)
    assert updated is not doc

def test_transform_original_host_unchanged():
    doc = cxlib.parse(fx('api_config.cx'))
    def change_host(el):
        el.set_attr('host', 'prod.example.com')
        return el
    updated = doc.transform('config/server', change_host)
    assert updated.at('config/server').attr('host') == 'prod.example.com'
    assert doc.at('config/server').attr('host') == 'localhost', \
        'original document should still have localhost after transform'

def test_transform_chained_leaves_original_unchanged():
    doc = cxlib.parse(fx('api_config.cx'))
    def set_host1(el):
        el.set_attr('host', 'h1')
        return el
    def set_host2(el):
        el.set_attr('host', 'h2')
        return el
    result = doc.transform('config/server', set_host1).transform('config/database', set_host2)
    assert result.at('config/server').attr('host') == 'h1'
    assert result.at('config/database').attr('host') == 'h2'
    assert doc.at('config/server').attr('host') == 'localhost'
    assert doc.at('config/database').attr('host') == 'db.local'

def test_transform_missing_path_returns_equivalent_document():
    doc = cxlib.parse(fx('api_config.cx'))
    updated = doc.transform('config/no_such_element', lambda el: el)
    assert updated.at('config/server').attr('host') == 'localhost'

# ── transform_all immutability ────────────────────────────────────────────────

def test_transform_all_returns_different_document_object():
    doc = cxlib.parse(fx('api_config.cx'))
    updated = doc.transform_all('//server', lambda el: el)
    assert updated is not doc

def test_transform_all_original_unchanged():
    doc = cxlib.parse(fx('api_multi.cx'))
    def activate(el):
        el.set_attr('active', True)
        return el
    updated = doc.transform_all('//service', activate)
    for svc in updated.find_all('service'):
        assert svc.attr('active') is True
    for svc in doc.find_all('service'):
        assert svc.attr('active') is None, \
            'original document services should not have active attr'

def test_transform_all_deeply_nested_original_unchanged():
    doc = cxlib.parse(fx('api_article.cx'))
    def mark(el):
        el.set_attr('visited', True)
        return el
    doc.transform_all('//p', mark)
    for p in doc.find_all('p'):
        assert p.attr('visited') is None, \
            'original document p elements should be unaffected'

# ── two documents from same source are independent ────────────────────────────

def test_two_docs_from_same_string_are_independent():
    src = fx('api_config.cx')
    doc1 = cxlib.parse(src)
    doc2 = cxlib.parse(src)
    assert doc1.at('config/server').attr('host') == 'localhost'
    assert doc2.at('config/server').attr('host') == 'localhost'
    updated = doc1.transform('config/server', lambda el: (el.set_attr('host', 'mutated') or el))
    assert updated.at('config/server').attr('host') == 'mutated'
    assert doc1.at('config/server').attr('host') == 'localhost'
    assert doc2.at('config/server').attr('host') == 'localhost'

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
    print(f'python/test_immutability.py: {_passed} passed, {_failed} failed  [{status}]')
    sys.exit(0 if _failed == 0 else 1)
