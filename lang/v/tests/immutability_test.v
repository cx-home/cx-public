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

// ── immutability contract ─────────────────────────────────────────────────────
//
// Documents are immutable values (see spec/api.md §Immutability).
// Elements extracted via at(), find_first(), root(), etc. are VALUE COPIES.
// Mutating an extracted element does NOT modify the source document.
//
// The only way to produce an updated document is via Document.transform()
// (which is currently PENDING — see transform_pending_test.v).
//
// Build-mode mutation (set_attr, append, etc.) is safe on fresh elements
// during document construction, but has no effect on already-parsed documents.

// set_attr on an element extracted via at() does not change the source document.
fn test_set_attr_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// Extract server element — this is a VALUE COPY
	mut extracted := doc.at('config/server') or { panic('no server') }

	// Verify original value before mutation
	original_host := (doc.at('config/server') or { panic('') }).attr('host') or { panic('') }
	assert original_host.str() == 'localhost', 'pre-condition: host should be localhost'

	// Mutate the COPY
	extracted.set_attr('host', cxlib.ScalarVal('changed'))

	// The extracted copy reflects the change
	assert (extracted.attr('host') or { panic('') }).str() == 'changed'

	// But the SOURCE DOCUMENT is unchanged — re-reading from doc gives original value
	re_read := doc.at('config/server') or { panic('server gone from doc') }
	assert (re_read.attr('host') or { panic('') }).str() == 'localhost',
		'source document should be unchanged after mutating extracted element'
}

// append on an element extracted via find_first() does not change the source document.
fn test_append_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// Verify original child count
	original_count := (doc.at('config/server') or { panic('') }).children().len
	// server element has no child elements in api_config.cx
	assert original_count == 0, 'pre-condition: server has no children'

	// Extract server element as a VALUE COPY and mutate it
	mut extracted := doc.find_first('server') or { panic('no server') }
	extracted.append(cxlib.Node(cxlib.Element{ name: 'new_child' }))

	// The copy now has a child
	assert extracted.children().len == 1

	// The source document is unchanged
	re_read := doc.at('config/server') or { panic('server gone from doc') }
	assert re_read.children().len == 0,
		'source document server should still have 0 children after mutating extracted copy'
}

// remove_child on an element extracted via at() does not change the source document.
fn test_remove_child_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// Verify original config has 3 children
	assert (doc.at('config') or { panic('') }).children().len == 3,
		'pre-condition: config has 3 children'

	// Extract config and mutate the COPY
	mut config := doc.at('config') or { panic('no config') }
	config.remove_child('server')

	// Copy reflects the removal
	assert config.children().len == 2

	// Source document is unchanged
	re_read := doc.at('config') or { panic('config gone from doc') }
	assert re_read.children().len == 3,
		'source document config should still have 3 children'
}

// Extracting root, mutating it, then re-reading root from doc — doc is unchanged.
fn test_root_mutation_does_not_affect_doc() {
	mut doc := cxlib.Document{}
	mut el := cxlib.Element{ name: 'config' }
	el.set_attr('version', cxlib.ScalarVal(i64(1)))
	doc.append(cxlib.Node(el))

	// Extract root as VALUE COPY
	mut extracted_root := doc.root() or { panic('no root') }

	// Verify original attr
	assert (extracted_root.attr('version') or { panic('') }).str() == '1'

	// Mutate the copy
	extracted_root.set_attr('version', cxlib.ScalarVal(i64(99)))
	assert (extracted_root.attr('version') or { panic('') }).str() == '99'

	// Source document root still has original value
	doc_root := doc.root() or { panic('root gone from doc') }
	assert (doc_root.attr('version') or { panic('') }).str() == '1',
		'source document root should still have version=1'
}

// Two documents parsed from the same CX string are independent values.
// Mutating an element extracted from doc1 does not affect doc2.
fn test_two_docs_from_same_string_are_independent() {
	cx_source := fx('api_config.cx')
	doc1 := cxlib.parse(cx_source) or { panic(err) }
	doc2 := cxlib.parse(cx_source) or { panic(err) }

	// Verify both start with the same value
	host1 := (doc1.at('config/server') or { panic('') }).attr('host') or { panic('') }
	host2 := (doc2.at('config/server') or { panic('') }).attr('host') or { panic('') }
	assert host1.str() == 'localhost'
	assert host2.str() == 'localhost'

	// Mutate a copy from doc1
	mut extracted := doc1.at('config/server') or { panic('') }
	extracted.set_attr('host', cxlib.ScalarVal('mutated'))

	// doc1 is unchanged (extracted was a copy)
	assert ((doc1.at('config/server') or { panic('') }).attr('host') or { panic('') }).str() == 'localhost'

	// doc2 is unchanged (independent document)
	assert ((doc2.at('config/server') or { panic('') }).attr('host') or { panic('') }).str() == 'localhost',
		'doc2 should be unaffected by mutation of element from doc1'
}

// remove_at on an extracted element does not affect the source document.
fn test_remove_at_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// config has 3 children (server, database, logging)
	assert (doc.at('config') or { panic('') }).children().len == 3

	// Extract and mutate a copy
	mut extracted_config := doc.at('config') or { panic('') }
	extracted_config.remove_at(0)
	assert extracted_config.children().len == 2, 'extracted copy should have 2 children after remove_at'

	// Source document is unchanged
	re_read := doc.at('config') or { panic('config gone') }
	assert re_read.children().len == 3,
		'source document should still have 3 children after remove_at on extracted copy'
}

// prepend on an extracted element does not affect the source document.
fn test_prepend_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// server has 0 children initially
	assert (doc.at('config/server') or { panic('') }).children().len == 0

	// Extract and mutate
	mut extracted := doc.at('config/server') or { panic('') }
	extracted.prepend(cxlib.Node(cxlib.Element{ name: 'prepended' }))
	assert extracted.children().len == 1

	// Source unchanged
	re_read := doc.at('config/server') or { panic('server gone') }
	assert re_read.children().len == 0,
		'source server should still have 0 children after prepend on extracted copy'
}

// set_attr on element extracted via find_all does not affect source document.
fn test_set_attr_on_find_all_result_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// find_all returns VALUE COPIES
	mut results := doc.find_all('server')
	assert results.len == 1

	// Mutate the copy
	results[0].set_attr('host', cxlib.ScalarVal('mutated_host'))
	assert (results[0].attr('host') or { panic('') }).str() == 'mutated_host'

	// Source document is unchanged
	re_read := doc.at('config/server') or { panic('') }
	assert (re_read.attr('host') or { panic('') }).str() == 'localhost',
		'source document should not be affected by mutation of find_all result'
}

// remove_attr on extracted element does not affect source document.
fn test_remove_attr_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse(fx('api_config.cx')) or { panic(err) }

	// Verify port exists
	assert (doc.at('config/server') or { panic('') }).attr('port') != none

	// Extract and remove attr from copy
	mut extracted := doc.at('config/server') or { panic('') }
	extracted.remove_attr('port')
	assert extracted.attr('port') == none

	// Source still has port
	re_read := doc.at('config/server') or { panic('server gone') }
	assert re_read.attr('port') != none,
		'source document server should still have port attr'
}

// insert on extracted element does not affect source document.
fn test_insert_on_extracted_does_not_affect_doc() {
	doc := cxlib.parse('[root [a][c]]') or { panic(err) }

	// root has 2 children initially
	assert (doc.root() or { panic('') }).children().len == 2

	// Extract and insert into copy
	mut extracted := doc.root() or { panic('') }
	extracted.insert(1, cxlib.Node(cxlib.Element{ name: 'b' }))
	assert extracted.children().len == 3

	// Source is unchanged
	re_read := doc.root() or { panic('root gone') }
	assert re_read.children().len == 2,
		'source document should still have 2 children after insert on extracted copy'
}
