module main

import os
import x.json2
import cxlib

// ── fixture loader ────────────────────────────────────────────────────────────

// @FILE resolves to this file's absolute path at compile time.
// Three levels up from lang/v/tests/ reaches the repo root.
const fixtures = os.join_path(os.dir(@FILE), '..', '..', '..', 'fixtures')

fn fx(name string) string {
	return os.read_file(os.join_path(fixtures, name)) or {
		panic('could not read fixture ${name}: ${err}')
	}
}

// ── parse / root / get ────────────────────────────────────────────────────────

fn test_parse_returns_document() {
	_ := cxlib.parse(fx('api_config.cx')) or { assert false, err.msg(); return }
}

fn test_root_returns_first_element() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	root := doc.root() or { assert false, 'expected root'; return }
	assert root.name == 'config'
}

fn test_root_none_on_empty_input() {
	doc := cxlib.parse('') or { panic(err) }
	assert doc.root() == none
}

fn test_get_top_level_by_name() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	config := doc.get('config') or { assert false, 'no config'; return }
	assert config.name == 'config'
	assert doc.get('missing') == none
}

fn test_parse_multiple_top_level_elements() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	services := doc.find_all('service')
	assert services.len == 3
}

fn test_get_multi_returns_first_match() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	svc := doc.get('service') or { assert false, 'no service'; return }
	name := svc.attr('name') or { assert false, 'no name'; return }
	assert name.str() == 'auth'
}

// ── attr ──────────────────────────────────────────────────────────────────────

fn test_attr_string() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	srv := doc.at('config/server') or { panic('no server') }
	assert (srv.attr('host') or { panic('') }).str() == 'localhost'
}

fn test_attr_int() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	srv := doc.at('config/server') or { panic('') }
	assert (srv.attr('port') or { panic('') }).str() == '8080'
}

fn test_attr_bool() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	srv := doc.at('config/server') or { panic('') }
	assert (srv.attr('debug') or { panic('') }).str() == 'false'
}

fn test_attr_missing_returns_none() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	srv := doc.at('config/server') or { panic('') }
	assert srv.attr('nonexistent') == none
}

// ── scalar ────────────────────────────────────────────────────────────────────

fn test_scalar_int() {
	doc := cxlib.parse(fx('api_scalars.cx')) or { panic(err) }
	el := doc.at('values/count') or { panic('') }
	val := el.scalar() or { assert false, 'no scalar'; return }
	assert val.str() == '42'
}

fn test_scalar_float() {
	doc := cxlib.parse(fx('api_scalars.cx')) or { panic(err) }
	el := doc.at('values/ratio') or { panic('') }
	val := el.scalar() or { assert false, 'no scalar'; return }
	assert val.str() == '1.5'
}

fn test_scalar_bool_true() {
	doc := cxlib.parse(fx('api_scalars.cx')) or { panic(err) }
	el := doc.at('values/enabled') or { panic('') }
	val := el.scalar() or { assert false, 'no scalar'; return }
	assert val.str() == 'true'
}

fn test_scalar_bool_false() {
	doc := cxlib.parse(fx('api_scalars.cx')) or { panic(err) }
	el := doc.at('values/disabled') or { panic('') }
	val := el.scalar() or { assert false, 'no scalar'; return }
	assert val.str() == 'false'
}

fn test_scalar_null() {
	doc := cxlib.parse(fx('api_scalars.cx')) or { panic(err) }
	el := doc.at('values/nothing') or { panic('') }
	val := el.scalar() or { assert false, 'no scalar'; return }
	assert val.str() == 'null'
}

fn test_scalar_none_on_element_with_children() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.root() or { panic('') }.scalar() == none
}

// ── text ──────────────────────────────────────────────────────────────────────

fn test_text_single_token() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	h1 := doc.at('article/body/h1') or { panic('') }
	assert h1.text() == 'Introduction'
}

fn test_text_quoted() {
	doc := cxlib.parse(fx('api_scalars.cx')) or { panic(err) }
	el := doc.at('values/label') or { panic('') }
	assert el.text() == 'hello world'
}

fn test_text_empty_on_element_with_children() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.root() or { panic('') }.text() == ''
}

// ── children / get_all ────────────────────────────────────────────────────────

fn test_children_returns_only_elements() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	config := doc.root() or { panic('') }
	kids := config.children()
	assert kids.len == 3
	assert kids[0].name == 'server'
	assert kids[1].name == 'database'
	assert kids[2].name == 'logging'
}

fn test_get_all_direct_children() {
	doc := cxlib.parse('[root [item 1] [item 2] [other x] [item 3]]') or { panic(err) }
	items := (doc.root() or { panic('') }).get_all('item')
	assert items.len == 3
}

fn test_get_all_returns_empty_for_missing() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert (doc.root() or { panic('') }).get_all('missing').len == 0
}

// ── at ────────────────────────────────────────────────────────────────────────

fn test_at_single_segment() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert (doc.at('config') or { panic('') }).name == 'config'
}

fn test_at_two_segments() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert (doc.at('config/server') or { panic('') }).name == 'server'
	assert (doc.at('config/database') or { panic('') }).name == 'database'
}

fn test_at_three_segments() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	title := doc.at('article/head/title') or { assert false, 'no title'; return }
	assert title.text() == 'Getting Started with CX'
	h1 := doc.at('article/body/h1') or { assert false, 'no h1'; return }
	assert h1.text() == 'Introduction'
}

fn test_at_missing_segment_returns_none() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.at('config/missing') == none
}

fn test_at_missing_root_returns_none() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.at('missing') == none
}

fn test_at_deep_missing_returns_none() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.at('config/server/missing/deep') == none
}

fn test_element_at_relative_path() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	body := doc.at('article/body') or { panic('') }
	h2 := body.at('section/h2') or { assert false, 'no h2'; return }
	assert h2.text() == 'Details'
}

// ── find_all ──────────────────────────────────────────────────────────────────

fn test_find_all_top_level() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	assert doc.find_all('service').len == 3
}

fn test_find_all_deep() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	ps := doc.find_all('p')
	assert ps.len == 3
	assert ps[0].text() == 'First paragraph.'
	assert ps[1].text() == 'Nested paragraph.'
	assert ps[2].text() == 'Another nested paragraph.'
}

fn test_find_all_missing_returns_empty() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.find_all('missing').len == 0
}

fn test_find_all_on_element() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	body := doc.at('article/body') or { panic('') }
	assert body.find_all('p').len == 3
}

// ── find_first ────────────────────────────────────────────────────────────────

fn test_find_first_returns_first_match() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	p := doc.find_first('p') or { assert false, 'no p'; return }
	assert p.text() == 'First paragraph.'
}

fn test_find_first_missing_returns_none() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.find_first('missing') == none
}

fn test_find_first_depth_first_order() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	assert (doc.find_first('h1') or { panic('') }).text() == 'Introduction'
	assert (doc.find_first('h2') or { panic('') }).text() == 'Details'
}

fn test_find_first_on_element() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	section := doc.at('article/body/section') or { panic('') }
	p := section.find_first('p') or { assert false, 'no p'; return }
	assert p.text() == 'Nested paragraph.'
}

// ── mutation — Element ────────────────────────────────────────────────────────

fn test_append_adds_to_end() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	el.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	kids := el.children()
	assert kids.len == 2
	assert kids[1].name == 'b'
}

fn test_prepend_adds_to_front() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	el.prepend(cxlib.Node(cxlib.Element{ name: 'a' }))
	assert el.children()[0].name == 'a'
}

fn test_set_attr_new() {
	mut el := cxlib.Element{ name: 'server' }
	el.set_attr('host', cxlib.ScalarVal('localhost'))
	assert (el.attr('host') or { panic('') }).str() == 'localhost'
}

fn test_set_attr_int_emits_unquoted() {
	mut el := cxlib.Element{ name: 'server' }
	el.set_attr('port', cxlib.ScalarVal(i64(8080)))
	mut doc := cxlib.Document{}
	doc.append(cxlib.Node(el))
	cx_out := doc.to_cx()
	assert cx_out.contains('port=8080')
	assert !cx_out.contains("port='8080'")
}

fn test_set_attr_update_value() {
	mut el := cxlib.Element{ name: 'server' }
	el.set_attr('port', cxlib.ScalarVal(i64(8080)))
	el.set_attr('port', cxlib.ScalarVal(i64(9090)))
	assert el.attrs.len == 1
	assert (el.attr('port') or { panic('') }).str() == '9090'
}

fn test_remove_attr() {
	mut el := cxlib.Element{ name: 'server' }
	el.set_attr('host', cxlib.ScalarVal('localhost'))
	el.set_attr('port', cxlib.ScalarVal(i64(8080)))
	el.remove_attr('port')
	assert el.attr('port') == none
	assert el.attr('host') != none
}

fn test_remove_attr_nonexistent_is_noop() {
	mut el := cxlib.Element{ name: 'server' }
	el.set_attr('host', cxlib.ScalarVal('localhost'))
	el.remove_attr('nonexistent')
	assert el.attrs.len == 1
}

fn test_remove_child_by_name() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	el.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	el.remove_child('a')
	assert el.children().len == 1
	assert el.children()[0].name == 'b'
}

fn test_remove_child_nonexistent_is_noop() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	el.remove_child('missing')
	assert el.children().len == 1
}

// ── mutation — Document ───────────────────────────────────────────────────────

fn test_doc_append_element() {
	mut doc := cxlib.Document{}
	doc.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	doc.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	assert doc.get('a') != none
	assert doc.get('b') != none
}

fn test_doc_prepend_makes_new_root() {
	mut doc := cxlib.Document{}
	doc.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	doc.prepend(cxlib.Node(cxlib.Element{ name: 'a' }))
	assert (doc.root() or { panic('') }).name == 'a'
}

// ── round-trips ───────────────────────────────────────────────────────────────

fn test_to_cx_round_trip() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	reparsed := cxlib.parse(doc.to_cx()) or { panic(err) }
	srv := reparsed.at('config/server') or { panic('') }
	assert (srv.attr('host') or { panic('') }).str() == 'localhost'
	assert (srv.attr('port') or { panic('') }).str() == '8080'
}

fn test_to_cx_built_document() {
	mut el := cxlib.Element{ name: 'server' }
	el.set_attr('host', cxlib.ScalarVal('localhost'))
	el.set_attr('port', cxlib.ScalarVal(i64(8080)))
	el.append(cxlib.Node(cxlib.Element{
		name:  'timeout'
		items: [cxlib.Node(cxlib.ScalarNode{ data_type: .int_type, value: cxlib.ScalarVal(i64(30)) })]
	}))
	mut doc := cxlib.Document{}
	doc.append(cxlib.Node(el))
	reparsed := cxlib.parse(doc.to_cx()) or { panic(err) }
	srv := reparsed.root() or { panic('') }
	assert srv.name == 'server'
	assert (srv.attr('host') or { panic('') }).str() == 'localhost'
	to := srv.find_first('timeout') or { panic('') }
	assert (to.scalar() or { panic('') }).str() == '30'
}

fn test_to_cx_preserves_article_structure() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	reparsed := cxlib.parse(doc.to_cx()) or { panic(err) }
	title := reparsed.at('article/head/title') or { panic('') }
	assert title.text() == 'Getting Started with CX'
	assert reparsed.find_all('p').len == 3
}

// ── error / failure cases ─────────────────────────────────────────────────────

fn test_parse_error_unclosed_bracket() {
	_ := cxlib.parse(fx('errors/unclosed.cx')) or {
		return   // error expected — test passes
	}
	assert false, 'expected parse error for unclosed bracket'
}

fn test_parse_error_empty_element_name() {
	_ := cxlib.parse(fx('errors/empty_name.cx')) or {
		return   // error expected — test passes
	}
	assert false, 'expected parse error for empty element name'
}

fn test_parse_error_nested_unclosed() {
	_ := cxlib.parse(fx('errors/nested_unclosed.cx')) or {
		return   // error expected — test passes
	}
	assert false, 'expected parse error for nested unclosed bracket'
}

fn test_at_deep_missing_returns_none_not_error() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert doc.at('config/server/missing/deep/path') == none
}

fn test_find_all_on_empty_doc_returns_empty() {
	doc := cxlib.parse('') or { panic(err) }
	assert doc.find_all('anything').len == 0
}

fn test_find_first_on_empty_doc_returns_none() {
	doc := cxlib.parse('') or { panic(err) }
	assert doc.find_first('anything') == none
}

fn test_scalar_none_when_has_children() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert (doc.root() or { panic('') }).scalar() == none
}

fn test_text_empty_when_no_text_children() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	assert (doc.root() or { panic('') }).text() == ''
}

// ── parse format variants ─────────────────────────────────────────────────────

fn test_parse_xml() {
	doc := cxlib.parse_xml('<root><item id="1">hello</item></root>') or { assert false, err.msg(); return }
	root := doc.root() or { assert false, 'no root'; return }
	assert root.name == 'root'
	item := root.get('item') or { assert false, 'no item'; return }
	assert (item.attr('id') or { panic('') }).str() == '1'
}

fn test_parse_json_format() {
	doc := cxlib.parse_json('{"server":{"host":"localhost","port":8080}}') or { assert false, err.msg(); return }
	root := doc.root() or { assert false, 'no root'; return }
	assert root.name == 'server'
}

fn test_parse_yaml() {
	doc := cxlib.parse_yaml('server:\n  host: localhost\n  port: 8080\n') or { assert false, err.msg(); return }
	root := doc.root() or { assert false, 'no root'; return }
	assert root.name == 'server'
}

fn test_parse_toml() {
	doc := cxlib.parse_toml('[server]\nhost = "localhost"\nport = 8080\n') or { assert false, err.msg(); return }
	root := doc.root() or { assert false, 'no root'; return }
	assert root.name == 'server'
}

fn test_parse_md() {
	doc := cxlib.parse_md('# hello\n\nworld\n') or { assert false, err.msg(); return }
	assert doc.elements.len > 0
}

// ── loads / dumps ─────────────────────────────────────────────────────────────

fn test_loads_returns_data() {
	data := cxlib.loads('[server host=localhost port=8080]') or { assert false, err.msg(); return }
	obj := data.as_map()
	assert 'server' in obj
}

fn test_dumps_round_trip() {
	original := '[server host=localhost]'
	data := cxlib.loads(original) or { panic(err) }
	cx_out := cxlib.dumps(data) or { panic(err) }
	doc := cxlib.parse(cx_out) or { panic(err) }
	srv := doc.root() or { assert false, 'no root'; return }
	assert srv.name == 'server'
}

fn test_dumps_from_json_any() {
	mut obj := map[string]json2.Any{}
	obj['greeting'] = json2.Any(string('hello'))
	cx_out := cxlib.dumps(json2.Any(obj)) or { panic(err) }
	doc := cxlib.parse(cx_out) or { panic(err) }
	assert doc.root() or { panic('') }.name == 'greeting'
}

// ── insert / remove_at ────────────────────────────────────────────────────────

fn test_insert_at_index() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	el.append(cxlib.Node(cxlib.Element{ name: 'c' }))
	el.insert(1, cxlib.Node(cxlib.Element{ name: 'b' }))
	kids := el.children()
	assert kids.len == 3
	assert kids[0].name == 'a'
	assert kids[1].name == 'b'
	assert kids[2].name == 'c'
}

fn test_insert_at_zero_is_prepend() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	el.insert(0, cxlib.Node(cxlib.Element{ name: 'a' }))
	assert el.children()[0].name == 'a'
}

fn test_remove_at_removes_by_index() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	el.append(cxlib.Node(cxlib.Element{ name: 'b' }))
	el.append(cxlib.Node(cxlib.Element{ name: 'c' }))
	el.remove_at(1)
	kids := el.children()
	assert kids.len == 2
	assert kids[0].name == 'a'
	assert kids[1].name == 'c'
}

fn test_remove_at_out_of_bounds_is_noop() {
	mut el := cxlib.Element{ name: 'root' }
	el.append(cxlib.Node(cxlib.Element{ name: 'a' }))
	el.remove_at(99)
	assert el.children().len == 1
}
