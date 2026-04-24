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

// transform returns a NEW Document — not the original document value.
fn test_transform_returns_new_document() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	updated := doc.transform('config/server', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('host', cxlib.ScalarVal('newhost'))
		return e
	})
	assert (updated.at('config/server') or { panic('no server in updated') }).attr('host') or {
		panic('no host')
	}.str() == 'newhost'
}

// transform applies the function to the element at the given path.
fn test_transform_applies_function_to_element_at_path() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	updated := doc.transform('config/server', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('host', cxlib.ScalarVal('transformed'))
		return e
	})
	srv := updated.at('config/server') or { panic('no server') }
	assert (srv.attr('host') or { panic('no host') }).str() == 'transformed'
	assert (srv.attr('port') or { panic('no port') }).str() == '8080'
}

// The ORIGINAL document is unchanged after transform.
fn test_transform_original_document_unchanged() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	_ = doc.transform('config/server', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('host', cxlib.ScalarVal('changed'))
		return e
	})
	assert (doc.at('config/server') or { panic('') }.attr('host') or { panic('') }).str() == 'localhost'
}

// When the path does not exist, transform returns the original document unchanged.
fn test_transform_missing_path_returns_original_unchanged() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	updated := doc.transform('config/nonexistent', fn (el cxlib.Element) cxlib.Element {
		return el
	})
	assert (updated.at('config/server') or { panic('') }.attr('host') or { panic('') }).str() == 'localhost'
	assert updated.at('config/nonexistent') == none
}

// transform can be chained.
fn test_transform_chained_transforms() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	updated := doc.transform('config/server', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('host', cxlib.ScalarVal('host1'))
		return e
	}).transform('config/database', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('host', cxlib.ScalarVal('host2'))
		return e
	})
	assert (updated.at('config/server') or { panic('') }.attr('host') or { panic('') }).str() == 'host1'
	assert (updated.at('config/database') or { panic('') }.attr('host') or { panic('') }).str() == 'host2'
	assert (doc.at('config/server') or { panic('') }.attr('host') or { panic('') }).str() == 'localhost'
}

// transform_all applies the function to ALL elements matching the CXPath expression.
fn test_transform_all_applies_to_all_matching_elements() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	updated := doc.transform_all('//service', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('active', cxlib.ScalarVal(true))
		return e
	})
	services := updated.find_all('service')
	assert services.len == 3
	for svc in services {
		assert (svc.attr('active') or { panic('no active') }).str() == 'true'
	}
}

// transform_all returns a NEW Document — not the original.
fn test_transform_all_returns_new_document() {
	doc := cxlib.parse(fx('api_multi.cx')) or { panic(err) }
	updated := doc.transform_all('//service', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('version', cxlib.ScalarVal(i64(2)))
		return e
	})
	for svc in updated.find_all('service') {
		assert (svc.attr('version') or { panic('no version') }).str() == '2'
	}
	for svc in doc.find_all('service') {
		assert svc.attr('version') == none
	}
}

// transform_all with an expression that matches nothing returns the original document unchanged.
fn test_transform_all_no_matches_returns_original() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }
	updated := doc.transform_all('//nonexistent', fn (el cxlib.Element) cxlib.Element {
		return el
	})
	assert (updated.at('config/server') or { panic('') }.attr('host') or { panic('') }).str() == 'localhost'
	assert updated.find_all('nonexistent').len == 0
}

// transform_all with deeply nested matches.
fn test_transform_all_applies_to_deeply_nested_matches() {
	doc := cxlib.parse(fx('api_article.cx')) or { panic(err) }
	updated := doc.transform_all('//p', fn (el cxlib.Element) cxlib.Element {
		mut e := el
		e.set_attr('visited', cxlib.ScalarVal(true))
		return e
	})
	updated_ps := updated.find_all('p')
	assert updated_ps.len == 3, 'expected 3 p elements in updated doc'
	for p in updated_ps {
		assert (p.attr('visited') or { panic('no visited attr on p') }).str() == 'true'
	}
	// Original document unchanged
	for p in doc.find_all('p') {
		assert p.attr('visited') == none
	}
}
