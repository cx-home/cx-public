import os
import cxlib

const examples = os.join_path(@VMODROOT, '..', '..', 'examples')

fn read(name string) string {
	return os.read_file(os.join_path(examples, name)) or { panic(err) }
}

fn section(title string) {
	println('\n' + '─'.repeat(60))
	println('  ${title}')
	println('─'.repeat(60))
}

fn main() {
	println('libcx ${cxlib.version()}')

	// ── article.cx: comments, mixed content, raw text, entity refs ──────────

	section('article.cx  (source)')
	println(read('article.cx'))

	section('article.cx  →  CX  (canonical round-trip)')
	println(cxlib.to_cx(read('article.cx')) or { panic(err) })

	section('article.cx  →  XML')
	println(cxlib.to_xml(read('article.cx')) or { panic(err) })

	section("article.cx  →  JSON  (mixed content uses '_' for text runs)")
	println(cxlib.to_json(read('article.cx')) or { panic(err) })

	section('article.cx  →  YAML')
	println(cxlib.to_yaml(read('article.cx')) or { panic(err) })

	// ── env.cx: anchors, merges, comments ───────────────────────────────────

	section('env.cx  (source)')
	println(read('env.cx'))

	section('env.cx  →  CX  (canonical round-trip)')
	println(cxlib.to_cx(read('env.cx')) or { panic(err) })

	section('env.cx  →  XML  (anchor/merge as cx:anchor / cx:merge attrs)')
	println(cxlib.to_xml(read('env.cx')) or { panic(err) })

	section('env.cx  →  JSON')
	println(cxlib.to_json(read('env.cx')) or { panic(err) })

	section('env.cx  →  YAML')
	println(cxlib.to_yaml(read('env.cx')) or { panic(err) })

	section('env.cx  →  TOML')
	println(cxlib.to_toml(read('env.cx')) or { panic(err) })

	// ── config.cx: typed scalars, arrays ────────────────────────────────────

	section('config.cx  →  JSON')
	println(cxlib.to_json(read('config.cx')) or { panic(err) })

	section('config.cx  →  YAML')
	println(cxlib.to_yaml(read('config.cx')) or { panic(err) })

	section('config.cx  →  TOML')
	println(cxlib.to_toml(read('config.cx')) or { panic(err) })

	// ── books.cx: repeated elements become arrays ────────────────────────────

	section('books.cx  →  XML')
	println(cxlib.to_xml(read('books.cx')) or { panic(err) })

	section("books.cx  →  JSON  (repeated elements auto-collect into arrays)")
	println(cxlib.to_json(read('books.cx')) or { panic(err) })

	// ── cross-format round-trips ─────────────────────────────────────────────

	section('books.xml   →  CX')
	println(cxlib.xml_to_cx(read('books.xml')) or { panic(err) })

	section('books.json  →  CX')
	println(cxlib.json_to_cx(read('books.json')) or { panic(err) })

	section('config.yaml  →  CX')
	println(cxlib.yaml_to_cx(read('config.yaml')) or { panic(err) })

	section('config.toml  →  CX')
	println(cxlib.toml_to_cx(read('config.toml')) or { panic(err) })

	// ── vcore.cx: v3.3 features ─────────────────────────────────────────────

	section('vcore.cx  (source)')
	println(read('vcore.cx'))

	section('vcore.cx  →  CX  (short aliases expand; auto-array gains explicit :type[])')
	println(cxlib.to_cx(read('vcore.cx')) or { panic(err) })

	section('vcore.cx  →  JSON  (auto-array, :[], triple-quoted, block content)')
	println(cxlib.to_json(read('vcore.cx')) or { panic(err) })

	section('vcore.cx  →  XML  (cx:type annotations; cx:block for block content)')
	println(cxlib.to_xml(read('vcore.cx')) or { panic(err) })

	// ── doc.cx: MD dialect document ─────────────────────────────────────────────
	section('doc.cx  (source)')
	println(read('doc.cx'))

	section('doc.cx  →  Markdown')
	println(cxlib.to_md(read('doc.cx')) or { panic(err) })

	section('doc.cx  →  XML')
	println(cxlib.to_xml(read('doc.cx')) or { panic(err) })

	// ── doc.md: Markdown → CX ───────────────────────────────────────────────────
	section('doc.md  (source)')
	println(read('doc.md'))

	section('doc.md  →  CX')
	println(cxlib.md_to_cx(read('doc.md')) or { panic(err) })

	// ── Document API: parse, navigate, query ─────────────────────────────────────
	section('config.cx  →  Document  (parse, navigate, query)')
	doc := cxlib.parse(read('config.cx')) or { panic(err) }

	server := doc.at('server') or { panic('no server') }
	server_host := server.find_first('host') or { panic('no host') }
	server_port := server.find_first('port') or { panic('no port') }
	println('server host: ${server_host.text()}')
	println('server port: ${server_port.scalar() or { cxlib.ScalarVal(i64(0)) }}')

	all_hosts := doc.find_all('host')
	println('all host elements: ${all_hosts.map(it.text())}')

	db := doc.get('database') or { panic('no database') }
	db_name := db.find_first('name') or { panic('no db name') }
	println('db name: ${db_name.text()}')

	// ── Document API: build and mutate programmatically ───────────────────────────
	// Note: V uses value semantics — mutate elements before inserting into the tree.
	section('Document  (build programmatically + mutate)')
	mut srv := cxlib.Element{ name: 'server' }
	srv.set_attr('host', cxlib.ScalarVal('localhost'))
	srv.set_attr('port', cxlib.ScalarVal(i64(8080)))
	srv.append(cxlib.Node(cxlib.Element{
		name:  'timeout'
		items: [cxlib.Node(cxlib.ScalarNode{
			data_type: .int_type
			value:     cxlib.ScalarVal(i64(30))
		})]
	}))
	srv.remove_attr('port')
	srv.set_attr('port', cxlib.ScalarVal(i64(9090)))
	mut new_doc := cxlib.Document{}
	new_doc.append(cxlib.Node(srv))
	println(new_doc.to_cx())

	// ── chapter.cx: XML-style structured document ─────────────────────────────

	section('chapter.cx  (source)')
	println(read('chapter.cx'))

	section('chapter.cx  →  CX  (canonical)')
	println(cxlib.to_cx(read('chapter.cx')) or { panic(err) })

	section('chapter.cx  →  XML  (structured document with sections and table)')
	println(cxlib.to_xml(read('chapter.cx')) or { panic(err) })

	section('chapter.cx  →  JSON  (nested sections as nested objects)')
	println(cxlib.to_json(read('chapter.cx')) or { panic(err) })

	// ── post.cx: Markdown-style blog post ─────────────────────────────────────

	section('post.cx  (source)')
	println(read('post.cx'))

	section('post.cx  →  Markdown  (CX markdown dialect → rendered Markdown)')
	println(cxlib.to_md(read('post.cx')) or { panic(err) })

	section('post.cx  →  CX  (canonical)')
	println(cxlib.to_cx(read('post.cx')) or { panic(err) })

	// ── AST inspection ────────────────────────────────────────────────────────
	section('article.cx  →  AST  →  CX  (round-trip: AST JSON back to canonical CX)')
	println(cxlib.ast_to_cx(cxlib.to_ast(read('article.cx')) or { panic(err) }) or { panic(err) })

	section('article.cx  →  CX  (compact)')
	println(cxlib.to_cx_compact(read('article.cx')) or { panic(err) })

	// ── Document API: CXPath select / transform ──────────────────────────────────

	section('Document API: CXPath select')
	cx_src := "[services\n  [service name=auth  port=8080 active=true]\n  [service name=api   port=9000 active=false]\n  [service name=web   port=80   active=true]\n]"
	doc2 := cxlib.parse(cx_src) or { panic(err) }
	first_svc := doc2.select('//service') or { panic(err) }
	name_attr := first_svc.attr('name') or { panic(err) }
	println('first service: ${name_attr.str()}')
	active_svcs := doc2.select_all('//service[@active=true]') or { panic(err) }
	for svc in active_svcs {
		n := svc.attr('name') or { continue }
		println('active: ${n.str()}')
	}

	section('Document API: transform (immutable update)')
	updated2 := doc2.transform('services/service', fn (mut el cxlib.Element) cxlib.Element {
		el.set_attr('name', cxlib.ScalarVal('renamed-auth'))
		return el
	}) or { panic(err) }
	println(updated2.to_cx())

	section('Document API: transform_all')
	all_active2 := doc2.transform_all('//service', fn (mut el cxlib.Element) cxlib.Element {
		el.set_attr('active', cxlib.ScalarVal(true))
		return el
	}) or { panic(err) }
	active_svcs2 := all_active2.select_all('//service[@active=true]') or { panic(err) }
	println('active services after transform_all: ${active_svcs2.len}')
}
