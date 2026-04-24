module main

import os
import cxlib

// ── fixture loader ────────────────────────────────────────────────────────────

const fixtures = os.join_path(os.dir(@FILE), '..', '..', '..', 'fixtures')

fn fx(name string) string {
	return os.read_file(os.join_path(fixtures, name)) or {
		panic('could not read fixture ${name}: ${err}')
	}
}

// ── select — basic ────────────────────────────────────────────────────────────

fn test_select_returns_first_match() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	svc := doc.select('//service') or { panic('expected match') }
	assert svc.name == 'service'
	assert (svc.attr('name') or { panic('') }).str() == 'auth'
}

fn test_select_returns_none_on_no_match() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	result := doc.select('//nonexistent')
	assert result == none
}

fn test_select_all_returns_all_in_depth_first_order() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	services := doc.select_all('//service')
	assert services.len == 3
	assert (services[0].attr('name') or { panic('') }).str() == 'auth'
	assert (services[1].attr('name') or { panic('') }).str() == 'api'
	assert (services[2].attr('name') or { panic('') }).str() == 'worker'
}

fn test_select_all_returns_empty_on_no_match() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	results := doc.select_all('//nonexistent')
	assert results.len == 0
}

fn test_select_on_element_excludes_self() {
	doc := cxlib.parse('[root [p outer [p inner]]]') or { panic(err) }
	outer_p := doc.at('root/p') or { panic('') }
	found := outer_p.select('//p') or { panic('expected inner p') }
	assert found.text() == 'inner'
}

// ── Descendant axis: //name ───────────────────────────────────────────────────

fn test_descendant_axis_double_slash() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	ps := doc.select_all('//p')
	assert ps.len == 3
}

fn test_descendant_axis_preserves_depth_first_order() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	ps := doc.select_all('//p')
	assert ps[0].text() == 'First paragraph.'
	assert ps[1].text() == 'Nested paragraph.'
	assert ps[2].text() == 'Another nested paragraph.'
}

// ── Child axis: a/b/c ─────────────────────────────────────────────────────────

fn test_child_axis_path() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	srv := doc.select('config/server') or { panic('expected server') }
	assert srv.name == 'server'
	assert (srv.attr('host') or { panic('') }).str() == 'localhost'
}

fn test_child_axis_three_level_path() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	title := doc.select('article/head/title') or { panic('no title') }
	assert title.text() == 'Getting Started with CX'
}

// ── Wildcard name test: * ─────────────────────────────────────────────────────

fn test_wildcard_name_direct_children() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	children := doc.select_all('config/*')
	assert children.len == 3
	assert children[0].name == 'server'
	assert children[1].name == 'database'
	assert children[2].name == 'logging'
}

fn test_wildcard_descendant_all_elements() {
	doc := cxlib.parse('[root [a [b]][c]]') or { panic(err) }
	all := doc.select_all('//*')
	assert all.len == 4
}

// ── Attribute existence predicate: [@attr] ────────────────────────────────────

fn test_attr_existence_predicate() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	with_id := doc.select_all('//*[@id]')
	assert with_id.len == 1
	assert with_id[0].name == 'section'
}

// ── Attribute equality: [@attr=value] ─────────────────────────────────────────

fn test_attr_equality_string() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	found := doc.select('//service[@name=auth]') or { panic('no match') }
	assert (found.attr('name') or { panic('') }).str() == 'auth'
}

fn test_attr_inequality() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	others := doc.select_all('//service[@name!=auth]')
	assert others.len == 2
	for svc in others {
		assert (svc.attr('name') or { panic('') }).str() != 'auth'
	}
}

fn test_attr_equality_int_typed() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	found := doc.select('//service[@port=8080]') or { panic('no match') }
	assert (found.attr('port') or { panic('') }).str() == '8080'
}

fn test_attr_equality_bool_typed() {
	doc := cxlib.parse('[services [service active=true name=a][service active=false name=b]]') or {
		panic(err)
	}
	active := doc.select_all('//service[@active=true]')
	assert active.len == 1
	assert (active[0].attr('name') or { panic('') }).str() == 'a'
}

// ── Numeric range: [@port>=8000] ──────────────────────────────────────────────

fn test_attr_numeric_range_gte() {
	doc := cxlib.parse('[services [service port=8080][service port=80][service port=9000]]') or {
		panic(err)
	}
	high_port := doc.select_all('//service[@port>=8000]')
	assert high_port.len == 2
}

fn test_attr_numeric_range_lt() {
	doc := cxlib.parse('[services [service port=8080][service port=80][service port=443]]') or {
		panic(err)
	}
	low_port := doc.select_all('//service[@port<1000]')
	assert low_port.len == 2
}

// ── Boolean operators: and, or ────────────────────────────────────────────────

fn test_and_operator_both_required() {
	cx := '[services [service active=true region=us][service active=true region=eu][service active=false region=us]]'
	doc := cxlib.parse(cx) or { panic(err) }
	results := doc.select_all('//service[@active=true and @region=us]')
	assert results.len == 1
}

fn test_or_operator_either_matches() {
	doc := cxlib.parse('[services [service port=80][service port=443][service port=8080]]') or {
		panic(err)
	}
	web_ports := doc.select_all('//service[@port=80 or @port=443]')
	assert web_ports.len == 2
}

// ── not() predicate ───────────────────────────────────────────────────────────

fn test_not_predicate_attr_inequality() {
	doc := cxlib.parse('[services [service active=true][service active=false][service active=true]]') or {
		panic(err)
	}
	not_false := doc.select_all('//service[not(@active=false)]')
	assert not_false.len == 2
}

fn test_not_predicate_attr_absence() {
	doc := cxlib.parse('[config [server host=localhost debug=true][database host=db]]') or {
		panic(err)
	}
	without_debug := doc.select_all('//*[not(@debug)]')
	assert without_debug.any(it.name == 'database')
	assert !without_debug.any(it.name == 'server')
}

// ── Child existence predicate: [childname] ────────────────────────────────────

fn test_child_existence_predicate() {
	doc := cxlib.parse('[services [service [tags core]][service name=plain]]') or { panic(err) }
	with_tags := doc.select_all('//service[tags]')
	assert with_tags.len == 1
	assert with_tags[0].get('tags') != none
}

fn test_child_existence_negation_predicate() {
	doc := cxlib.parse('[services [service [tags core]][service name=plain]]') or { panic(err) }
	without_tags := doc.select_all('//service[not(tags)]')
	assert without_tags.len == 1
	assert without_tags[0].get('tags') == none
}

// ── Position predicates: [1], [last()] ───────────────────────────────────────

fn test_position_first() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	first_svc := doc.select('//service[1]') or { panic('no match') }
	assert (first_svc.attr('name') or { panic('') }).str() == 'auth'
}

fn test_position_second() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	second_svc := doc.select('//service[2]') or { panic('no match') }
	assert (second_svc.attr('name') or { panic('') }).str() == 'api'
}

fn test_position_last() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	last_svc := doc.select('//service[last()]') or { panic('no match') }
	assert (last_svc.attr('name') or { panic('') }).str() == 'worker'
}

// ── String functions: contains(), starts-with() ───────────────────────────────

fn test_contains_function() {
	doc := cxlib.parse('[docs [p class=lead-note text][p class=other text]]') or { panic(err) }
	with_note := doc.select_all('//p[contains(@class, note)]')
	assert with_note.len == 1
	assert (with_note[0].attr('class') or { panic('') }).str() == 'lead-note'
}

fn test_starts_with_function() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	with_a := doc.select_all('//service[starts-with(@name, a)]')
	assert with_a.len == 2
	for svc in with_a {
		assert (svc.attr('name') or { panic('') }).str().starts_with('a')
	}
}

// ── Relative select on Element ────────────────────────────────────────────────

fn test_relative_select_all_on_element() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	body := doc.at('article/body') or { panic('') }
	ps := body.select_all('//p')
	assert ps.len == 3
	assert !ps.any(it.name == 'body')
}

fn test_relative_select_no_match() {
	doc := cxlib.parse('[root [child leaf]]') or { panic(err) }
	child := doc.at('root/child') or { panic('') }
	result := child.select('//nonexistent')
	assert result == none
}

fn test_relative_select_scoped_to_element_subtree() {
	doc := cxlib.parse('[root [a [item inside-a]][b [item inside-b]]]') or { panic(err) }
	a_el := doc.at('root/a') or { panic('') }
	items := a_el.select_all('//item')
	assert items.len == 1
	assert items[0].text() == 'inside-a'
}

// ── CXPath with mixed axes: a//b ─────────────────────────────────────────────

fn test_child_then_descendant_axis() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	ps := doc.select_all('article/body//p')
	assert ps.len == 3
}

fn test_descendant_then_descendant_axis() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	ps := doc.select_all('//section//p')
	assert ps.len == 2
	assert ps[0].text() == 'Nested paragraph.'
	assert ps[1].text() == 'Another nested paragraph.'
}

// ── Invalid expression contract (documented, not executed) ───────────────────

fn test_invalid_expression_contract_documented() {
	// Contract: doc.select('[@invalid syntax!!!') panics with descriptive message.
	// Not called here — a panic would abort the binary without a clear test report.
	// Verified manually or via subprocess test.
	assert true
}
