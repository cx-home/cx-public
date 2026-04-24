#!/usr/bin/env ruby
# frozen_string_literal: true
#
# CX transform examples — demonstrates the Ruby cxlib wrapper around libcx.
#
# Run from the repo root:
#   /opt/homebrew/opt/ruby/bin/ruby ruby/cxlib/examples/transform.rb
#
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'cxlib'

EXAMPLES = File.expand_path('../../../../../examples', __FILE__)

def read(name)
  File.read(File.join(EXAMPLES, name))
end

def section(title)
  puts
  puts '#{'─' * 60}'
  puts "  #{title}"
  puts '#{'─' * 60}'
end

# ── article.cx: comments, mixed content, raw text, entity refs ───────────────

section 'article.cx  (source)'
puts read('article.cx')

section 'article.cx  →  CX  (canonical round-trip)'
puts CXLib.to_cx(read('article.cx'))

section 'article.cx  →  XML'
puts CXLib.to_xml(read('article.cx'))

section "article.cx  →  JSON  (mixed content uses '_' for text runs)"
puts CXLib.to_json(read('article.cx'))

section 'article.cx  →  YAML'
puts CXLib.to_yaml(read('article.cx'))

# ── env.cx: anchors, merges, comments ────────────────────────────────────────

section 'env.cx  (source)'
puts read('env.cx')

section 'env.cx  →  CX  (canonical round-trip)'
puts CXLib.to_cx(read('env.cx'))

section 'env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)'
puts CXLib.to_xml(read('env.cx'))

section 'env.cx  →  JSON'
puts CXLib.to_json(read('env.cx'))

section 'env.cx  →  YAML'
puts CXLib.to_yaml(read('env.cx'))

section 'env.cx  →  TOML'
puts CXLib.to_toml(read('env.cx'))

# ── config.cx: typed scalars, arrays ─────────────────────────────────────────

section 'config.cx  →  JSON'
puts CXLib.to_json(read('config.cx'))

section 'config.cx  →  YAML'
puts CXLib.to_yaml(read('config.cx'))

section 'config.cx  →  TOML'
puts CXLib.to_toml(read('config.cx'))

# ── books.cx: repeated elements become arrays ─────────────────────────────────

section 'books.cx  →  XML'
puts CXLib.to_xml(read('books.cx'))

section 'books.cx  →  JSON  (repeated elements auto-collect into arrays)'
puts CXLib.to_json(read('books.cx'))

# ── cross-format round-trips ──────────────────────────────────────────────────

section 'books.xml   →  CX'
puts CXLib.xml_to_cx(read('books.xml'))

section 'books.json  →  CX'
puts CXLib.json_to_cx(read('books.json'))

section 'config.yaml  →  CX'
puts CXLib.yaml_to_cx(read('config.yaml'))

section 'config.toml  →  CX'
puts CXLib.toml_to_cx(read('config.toml'))

# ── vcore.cx: v3.3 features ───────────────────────────────────────────────────

section 'vcore.cx  (source)'
puts read('vcore.cx')

section 'vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])'
puts CXLib.to_cx(read('vcore.cx'))

section 'vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)'
puts CXLib.to_json(read('vcore.cx'))

section 'vcore.cx  →  XML  (cx:type annotations; cx:block for block content)'
puts CXLib.to_xml(read('vcore.cx'))

# ── doc.cx: MD dialect document ───────────────────────────────────────────────

section 'doc.cx  (source)'
puts read('doc.cx')

section 'doc.cx  →  Markdown'
puts CXLib.to_md(read('doc.cx'))

section 'doc.cx  →  XML'
puts CXLib.to_xml(read('doc.cx'))

# ── doc.md: Markdown → CX ────────────────────────────────────────────────────

section 'doc.md  (source)'
puts read('doc.md')

section 'doc.md  →  CX'
puts CXLib.md_to_cx(read('doc.md'))

# ── AST inspection ────────────────────────────────────────────────────────────

# ── chapter.cx: XML-style structured document ─────────────────────────────────

section 'chapter.cx  (source)'
puts read('chapter.cx')

section 'chapter.cx  →  CX  (canonical)'
puts CXLib.to_cx(read('chapter.cx'))

section 'chapter.cx  →  XML  (structured document with sections and table)'
puts CXLib.to_xml(read('chapter.cx'))

section 'chapter.cx  →  JSON  (nested sections as nested objects)'
puts CXLib.to_json(read('chapter.cx'))

# ── post.cx: Markdown-style blog post ─────────────────────────────────────────

section 'post.cx  (source)'
puts read('post.cx')

section 'post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)'
puts CXLib.to_md(read('post.cx'))

section 'post.cx  →  CX  (canonical)'
puts CXLib.to_cx(read('post.cx'))

section 'article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)'
puts CXLib.ast_to_cx(CXLib.to_ast(read('article.cx')))

section 'article.cx  →  CX  (compact)'
puts CXLib.to_cx_compact(read('article.cx'))

# ── Document API ──────────────────────────────────────────────────────────────

section 'Document API: CXPath select'
src = "[services\n  [service name=auth  port=8080 active=true]\n  [service name=api   port=9000 active=false]\n  [service name=web   port=80   active=true]\n]"
doc = CXLib.parse(src)
first = doc.select('//service')
puts "first service: #{first.attr('name')}"
doc.select_all('//service[@active=true]').each { |svc| puts "active: #{svc.attr('name')}" }

section 'Document API: transform (immutable update)'
updated = doc.transform('services/service') { |el| el.set_attr('name', 'renamed-auth'); el }
puts updated.to_cx

section 'Document API: transform_all'
all_active = doc.transform_all('//service') { |el| el.set_attr('active', true); el }
puts "active services after transform_all: #{all_active.select_all('//service[@active=true]').length}"
