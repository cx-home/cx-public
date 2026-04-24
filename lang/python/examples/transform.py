#!/usr/bin/env python3
"""
CX transform examples — demonstrates the cxlib wrapper around libcx.

Run from the repo root:
    python python/examples/transform.py
"""
import sys, os, json
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import cxlib

EXAMPLES = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'examples')

def read(name):
    with open(os.path.join(EXAMPLES, name)) as f:
        return f.read()

def section(title):
    print(f'\n{"─" * 60}')
    print(f'  {title}')
    print(f'{"─" * 60}')

# ── article.cx: comments, mixed content, raw text, entity refs ───────────────

section('article.cx  (source)')
print(read('article.cx'))

section('article.cx  →  CX  (canonical round-trip)')
print(cxlib.to_cx(read('article.cx')))

section('article.cx  →  XML')
print(cxlib.to_xml(read('article.cx')))

section("article.cx  →  JSON  (mixed content uses '_' for text runs)")
print(cxlib.to_json(read('article.cx')))

section('article.cx  →  YAML')
print(cxlib.to_yaml(read('article.cx')))

# ── env.cx: anchors, merges, comments ────────────────────────────────────────

section('env.cx  (source)')
print(read('env.cx'))

section('env.cx  →  CX  (canonical round-trip)')
print(cxlib.to_cx(read('env.cx')))

section('env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)')
print(cxlib.to_xml(read('env.cx')))

section('env.cx  →  JSON')
print(cxlib.to_json(read('env.cx')))

section('env.cx  →  YAML')
print(cxlib.to_yaml(read('env.cx')))

section('env.cx  →  TOML')
print(cxlib.to_toml(read('env.cx')))

# ── config.cx: typed scalars, arrays ─────────────────────────────────────────

section('config.cx  →  JSON')
print(cxlib.to_json(read('config.cx')))

section('config.cx  →  YAML')
print(cxlib.to_yaml(read('config.cx')))

section('config.cx  →  TOML')
print(cxlib.to_toml(read('config.cx')))

# ── books.cx: repeated elements become arrays ─────────────────────────────────

section('books.cx  →  XML')
print(cxlib.to_xml(read('books.cx')))

section('books.cx  →  JSON  (repeated elements auto-collect into arrays)')
print(cxlib.to_json(read('books.cx')))

# ── cross-format round-trips ──────────────────────────────────────────────────

section('books.xml   →  CX')
print(cxlib.xml_to_cx(read('books.xml')))

section('books.json  →  CX')
print(cxlib.json_to_cx(read('books.json')))

section('config.yaml  →  CX')
print(cxlib.yaml_to_cx(read('config.yaml')))

section('config.toml  →  CX')
print(cxlib.toml_to_cx(read('config.toml')))

# ── vcore.cx: v3.3 features ───────────────────────────────────────────────────

section('vcore.cx  (source)')
print(read('vcore.cx'))

section('vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])')
print(cxlib.to_cx(read('vcore.cx')))

section('vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)')
print(cxlib.to_json(read('vcore.cx')))

section('vcore.cx  →  XML  (cx:type annotations; cx:block for block content)')
print(cxlib.to_xml(read('vcore.cx')))

# ── doc.cx: MD dialect document ───────────────────────────────────────────────

section('doc.cx  (source)')
print(read('doc.cx'))

section('doc.cx  →  Markdown')
print(cxlib.to_md(read('doc.cx')))

section('doc.cx  →  XML')
print(cxlib.to_xml(read('doc.cx')))

# ── doc.md: Markdown → CX ────────────────────────────────────────────────────

section('doc.md  (source)')
print(read('doc.md'))

section('doc.md  →  CX')
print(cxlib.md_to_cx(read('doc.md')))

# ── Document API: parse, navigate, mutate ────────────────────────────────────

section('config.cx  →  Document  (parse, navigate, query)')
doc = cxlib.parse(read('config.cx'))

server = doc.at('server')
print(f'server host: {server.attr("host")}')
print(f'server port: {server.scalar()}')

db = doc.get('database')
print(f'db name: {db.at("name").text()}')

all_hosts = doc.find_all('host')
print(f'all host elements: {[h.text() for h in all_hosts]}')

section('config.cx  →  Document  (mutate + round-trip)')
doc2 = cxlib.parse(read('config.cx'))
srv = doc2.at('server')
srv.set_attr('env', 'production')
srv.find_first('debug').remove(srv.find_first('debug').items[0])
srv.find_first('debug').append(cxlib.Text('true'))
print(doc2.to_cx())

# ── Data binding: loads / dumps ───────────────────────────────────────────────

section('config.cx  →  loads()  (native Python dict — data binding)')
data = cxlib.loads(read('config.cx'))
print(json.dumps(data, indent=2))

section('dumps()  →  CX  (Python dict → CX string)')
print(cxlib.dumps({'app': {'name': 'myapp', 'version': '1.0', 'port': 8080}}))

# ── chapter.cx: XML-style structured document ─────────────────────────────────

section('chapter.cx  (source)')
print(read('chapter.cx'))

section('chapter.cx  →  CX  (canonical)')
print(cxlib.to_cx(read('chapter.cx')))

section('chapter.cx  →  XML  (structured document with sections and table)')
print(cxlib.to_xml(read('chapter.cx')))

section('chapter.cx  →  JSON  (nested sections as nested objects)')
print(cxlib.to_json(read('chapter.cx')))

# ── post.cx: Markdown-style blog post ─────────────────────────────────────────

section('post.cx  (source)')
print(read('post.cx'))

section('post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)')
print(cxlib.to_md(read('post.cx')))

section('post.cx  →  CX  (canonical)')
print(cxlib.to_cx(read('post.cx')))

# ── AST inspection ────────────────────────────────────────────────────────────

section("article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)")
print(cxlib.ast_to_cx(cxlib.to_ast(read('article.cx'))))

section("article.cx  →  CX  (compact)")
print(cxlib.to_cx_compact(read('article.cx')))

# ── Document API: CXPath select / transform ───────────────────────────────────

section('Document API: CXPath select')
src = """\
[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]"""
doc = cxlib.parse(src)
first = doc.select('//service')
print(f'first service: {first.attr("name")}')
for svc in doc.select_all('//service[@active=true]'):
    print(f'active: {svc.attr("name")}')

section('Document API: transform (immutable update)')
updated = doc.transform('services/service', lambda el: (el.set_attr('name', 'renamed-auth') or el))
print(updated.to_cx())
print(f'original first service name still: {doc.select("//service").attr("name")}')

section('Document API: transform_all')
def activate(el):
    el.set_attr('active', True)
    return el
all_active = doc.transform_all('//service', activate)
active_count = len(all_active.select_all('//service[@active=true]'))
print(f'active services after transform_all: {active_count}')
