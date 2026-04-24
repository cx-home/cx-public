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

// ── ordering invariants ────────────────────────────────────────────────────────

// StartDoc is ALWAYS the first event, for any non-empty document.
fn test_stream_start_doc_is_first() {
	events := cxlib.stream('[doc [child]]') or { panic(err) }
	assert events.len > 0, 'stream should produce at least one event'
	assert events[0].typ == .start_doc, 'first event must be start_doc, got ${events[0].typ}'
}

// EndDoc is ALWAYS the last event.
fn test_stream_end_doc_is_last() {
	events := cxlib.stream('[doc [child]]') or { panic(err) }
	last := events[events.len - 1]
	assert last.typ == .end_doc, 'last event must be end_doc, got ${last.typ}'
}

// StartDoc is first even for a deeply nested document.
fn test_stream_start_doc_is_first_nested() {
	events := cxlib.stream(fx('stream/stream_nested.cx')) or { panic(err) }
	assert events[0].typ == .start_doc, 'start_doc must be first event in nested doc'
}

// EndDoc is last even for a complex document with all event types.
fn test_stream_end_doc_is_last_complex() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	assert events[events.len - 1].typ == .end_doc, 'end_doc must be last event'
}

// The number of StartElement events equals the number of EndElement events.
fn test_stream_start_end_element_counts_equal() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	ends   := events.filter(it.typ == .end_element)
	assert starts.len == ends.len,
		'start_element count (${starts.len}) must equal end_element count (${ends.len})'
}

// StartElement and EndElement counts are equal for nested document.
fn test_stream_start_end_counts_equal_nested() {
	events := cxlib.stream(fx('stream/stream_nested.cx')) or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	ends   := events.filter(it.typ == .end_element)
	assert starts.len == ends.len,
		'start_element count must equal end_element count in nested doc'
}

// For every StartElement with name N there is exactly one corresponding EndElement with name N.
fn test_stream_element_names_are_balanced() {
	events := cxlib.stream('[root [a][b][a]]') or { panic(err) }
	mut start_names := events.filter(it.typ == .start_element).map(it.name)
	mut end_names   := events.filter(it.typ == .end_element).map(it.name)
	// Same multiset of names (order differs: starts are pre-order, ends are post-order)
	start_names.sort()
	end_names.sort()
	assert start_names == end_names,
		'start and end element names must form same multiset: starts=${start_names} ends=${end_names}'
}

// ── StartElement field values ──────────────────────────────────────────────────

// StartElement for an element with anchor has .anchor set correctly.
fn test_stream_anchor_on_start_element() {
	events := cxlib.stream('[server &srv host=localhost]') or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	assert starts.len == 1
	server_start := starts[0]
	assert server_start.name == 'server'
	anchor := server_start.anchor or { assert false, 'expected anchor to be set'; return }
	assert anchor == 'srv', 'anchor should be "srv" (without &), got "${anchor}"'
}

// StartElement for an element with :string[] data_type annotation has .data_type set.
fn test_stream_data_type_annotation_on_start_element() {
	events := cxlib.stream('[tags :string[] a b c]') or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	assert starts.len == 1
	tags_start := starts[0]
	assert tags_start.name == 'tags'
	dt := tags_start.data_type or { assert false, 'expected data_type to be set on tags'; return }
	assert dt == 'string[]', 'data_type should be "string[]", got "${dt}"'
}

// StartElement for an element with :int data_type annotation.
fn test_stream_int_data_type_on_start_element() {
	events := cxlib.stream('[count :int 42]') or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	assert starts.len == 1
	count_start := starts[0]
	dt := count_start.data_type or { assert false, 'expected data_type int on count'; return }
	assert dt == 'int', 'data_type should be "int", got "${dt}"'
}

// StartElement for an element with merge directive (*base) has .merge set.
fn test_stream_merge_directive_on_start_element() {
	events := cxlib.stream('[root [base host=localhost][server *base]]') or { panic(err) }
	server_starts := events.filter(it.typ == .start_element && it.name == 'server')
	assert server_starts.len == 1
	server_start := server_starts[0]
	merge := server_start.merge or { assert false, 'expected merge to be set on server'; return }
	assert merge == 'base', 'merge should be "base" (without *), got "${merge}"'
}

// StartElement without anchor has no anchor field.
fn test_stream_no_anchor_when_not_set() {
	events := cxlib.stream('[server host=localhost]') or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	assert starts.len == 1
	// anchor should be none (not set)
	assert starts[0].anchor == none, 'anchor should be none when not present'
}

// ── RawText event ─────────────────────────────────────────────────────────────

// RawText event has correct .value content.
// stream_events.cx has [raw-block [#inline raw text#]]
fn test_stream_raw_text_value() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	raw_events := events.filter(it.typ == .raw_text)
	assert raw_events.len > 0, 'expected at least one raw_text event'
	raw_event := raw_events[0]
	assert raw_event.value.contains('inline raw text'),
		'raw_text event should contain "inline raw text", got "${raw_event.value}"'
}

// RawText event value matches the content inside [# ... #].
fn test_stream_raw_text_exact_content() {
	events := cxlib.stream('[item [#hello raw world#]]') or { panic(err) }
	raw_events := events.filter(it.typ == .raw_text)
	assert raw_events.len == 1, 'expected exactly one raw_text event, got ${raw_events.len}'
	assert raw_events[0].value.contains('hello raw world'),
		'raw_text value should be "hello raw world", got "${raw_events[0].value}"'
}

// ── BlockContent transparency ──────────────────────────────────────────────────

// BlockContent nodes are transparent — no event with typ block_content is emitted.
// Their children appear directly inline (per spec §2 invariant 6).
fn test_stream_block_content_transparent_no_event() {
	// [el [#raw#]] — block content node; children appear directly
	events := cxlib.stream('[el [#raw content#]]') or { panic(err) }
	// There must be no block_content event type — the children appear inline
	// The EventType enum does not have block_content — verify raw_text appears directly
	raw_events := events.filter(it.typ == .raw_text)
	assert raw_events.len == 1, 'raw_text from block content should appear as direct event'
	assert raw_events[0].value.contains('raw content')
}

// BlockContent children appear between the parent StartElement and EndElement.
fn test_stream_block_content_children_in_correct_position() {
	events := cxlib.stream('[parent [#raw data#]]') or { panic(err) }
	parent_start_idx := events.index(events.filter(it.typ == .start_element && it.name == 'parent')[0])
	parent_end_idx   := events.index(events.filter(it.typ == .end_element && it.name == 'parent')[0])
	raw_events := events.filter(it.typ == .raw_text)
	assert raw_events.len == 1
	raw_idx := events.index(raw_events[0])
	assert raw_idx > parent_start_idx, 'raw_text must appear after parent start_element'
	assert raw_idx < parent_end_idx, 'raw_text must appear before parent end_element'
}

// ── Empty document ────────────────────────────────────────────────────────────

// An empty CX input produces exactly [StartDoc, EndDoc] — nothing else.
fn test_stream_empty_document_produces_only_boundary_events() {
	events := cxlib.stream('') or { panic(err) }
	assert events.len == 2, 'empty document should produce exactly 2 events, got ${events.len}'
	assert events[0].typ == .start_doc
	assert events[1].typ == .end_doc
}

// Whitespace-only input also produces only [StartDoc, EndDoc].
fn test_stream_whitespace_only_gives_boundary_events() {
	events := cxlib.stream('   \n\t  ') or { panic(err) }
	assert events.len == 2, 'whitespace-only should produce exactly 2 events'
	assert events[0].typ == .start_doc
	assert events[1].typ == .end_doc
}

// ── Reusability ───────────────────────────────────────────────────────────────

// The stream function can be called twice on the same input and produces same results.
// (Per spec §3.1: "the returned sequence MAY be consumed more than once".)
fn test_stream_call_twice_produces_same_result() {
	cx_src := '[doc [a][b][c]]'
	events1 := cxlib.stream(cx_src) or { panic(err) }
	events2 := cxlib.stream(cx_src) or { panic(err) }
	assert events1.len == events2.len,
		'stream called twice should produce same event count: ${events1.len} vs ${events2.len}'
	for i in 0 .. events1.len {
		assert events1[i].typ == events2[i].typ,
			'event ${i} type differs: ${events1[i].typ} vs ${events2[i].typ}'
	}
}

// ── Alias event ───────────────────────────────────────────────────────────────

// Alias event .value is the anchor name WITHOUT the leading *.
fn test_stream_alias_value_without_star() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	aliases := events.filter(it.typ == .alias_)
	assert aliases.len == 1, 'expected 1 alias event, got ${aliases.len}'
	alias_event := aliases[0]
	assert alias_event.value == 'srv',
		'alias value should be "srv" (no * prefix), got "${alias_event.value}"'
	// Double check: does not start with *
	assert !alias_event.value.starts_with('*'),
		'alias value must not include the * prefix'
}

// Alias event in a simpler document.
fn test_stream_alias_value_simple() {
	events := cxlib.stream('[root [server &base][*base]]') or { panic(err) }
	aliases := events.filter(it.typ == .alias_)
	assert aliases.len == 1
	assert aliases[0].value == 'base', 'alias value should be "base", got "${aliases[0].value}"'
}

// ── EntityRef event ───────────────────────────────────────────────────────────

// EntityRef event .value in stream_events.cx fixture is "amp".
fn test_stream_entity_ref_value_in_fixture() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	ers := events.filter(it.typ == .entity_ref)
	assert ers.len > 0, 'expected at least one entity_ref event from stream_events.cx'
	assert ers[0].value == 'amp',
		'entity_ref value should be "amp" (without & and ;), got "${ers[0].value}"'
}

// EntityRef event does not include & prefix or ; suffix.
fn test_stream_entity_ref_has_no_delimiters() {
	events := cxlib.stream('[root &amp;]') or { panic(err) }
	ers := events.filter(it.typ == .entity_ref)
	assert ers.len == 1
	v := ers[0].value
	assert !v.starts_with('&'), 'entity_ref value must not include & prefix'
	assert !v.ends_with(';'), 'entity_ref value must not include ; suffix'
	assert v == 'amp', 'entity_ref value should be "amp", got "${v}"'
}

// ── Attribute ordering on StartElement ────────────────────────────────────────

// Attributes on StartElement appear in document order (left to right).
fn test_stream_attrs_in_document_order() {
	events := cxlib.stream('[server host=localhost port=8080 debug=false]') or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	assert starts.len == 1
	attrs := starts[0].attrs
	assert attrs.len == 3, 'expected 3 attrs, got ${attrs.len}'
	assert attrs[0].name == 'host', 'first attr should be host'
	assert attrs[1].name == 'port', 'second attr should be port'
	assert attrs[2].name == 'debug', 'third attr should be debug'
}

// StartElement with no attrs has an empty attrs slice.
fn test_stream_start_element_empty_attrs() {
	events := cxlib.stream('[config]') or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	assert starts.len == 1
	assert starts[0].attrs.len == 0, 'element with no attrs should have empty attrs'
}

// ── Nested children appear between parent events ──────────────────────────────

// All child events appear between parent StartElement and EndElement.
fn test_stream_children_between_parent_events() {
	events := cxlib.stream('[outer [inner-a][inner-b]]') or { panic(err) }
	outer_start_idx := events.index(events.filter(it.is_start_element('outer'))[0])
	outer_end_idx   := events.index(events.filter(it.is_end_element('outer'))[0])
	inner_a_start_idx := events.index(events.filter(it.is_start_element('inner-a'))[0])
	inner_b_start_idx := events.filter(it.is_start_element('inner-b'))
	assert inner_a_start_idx > outer_start_idx, 'inner-a start must be after outer start'
	assert inner_a_start_idx < outer_end_idx, 'inner-a start must be before outer end'
	if inner_b_start_idx.len > 0 {
		idx := events.index(inner_b_start_idx[0])
		assert idx > outer_start_idx
		assert idx < outer_end_idx
	}
}

// ── PI event ──────────────────────────────────────────────────────────────────

// PI event with no data has .data == none.
fn test_stream_pi_no_data() {
	events := cxlib.stream('[root [?target]]') or { panic(err) }
	pis := events.filter(it.typ == .pi)
	assert pis.len == 1
	assert pis[0].target == 'target'
	// data should be none when not present
	assert pis[0].data == none, 'PI with no data should have data == none'
}

// PI event with data has .target and .data set correctly.
fn test_stream_pi_with_data() {
	events := cxlib.stream('[root [?php echo 42]]') or { panic(err) }
	pis := events.filter(it.typ == .pi)
	assert pis.len == 1
	assert pis[0].target == 'php', 'PI target should be "php", got "${pis[0].target}"'
	pi_data := pis[0].data or { assert false, 'PI should have data'; return }
	assert pi_data == 'echo 42', 'PI data should be "echo 42", got "${pi_data}"'
}

// ── Text event ────────────────────────────────────────────────────────────────

// Text event value for quoted text preserves the string content.
fn test_stream_text_quoted_value() {
	events := cxlib.stream("[p 'hello world']") or { panic(err) }
	texts := events.filter(it.typ == .text)
	assert texts.len == 1
	assert texts[0].value == 'hello world', 'quoted text value should be "hello world"'
}

// Scalar event has both .data_type and .value set.
fn test_stream_scalar_has_data_type_and_value() {
	events := cxlib.stream('[count :int 42]') or { panic(err) }
	scalars := events.filter(it.typ == .scalar)
	assert scalars.len == 1
	dt := scalars[0].data_type or { assert false, 'scalar should have data_type'; return }
	assert dt == 'int', 'scalar data_type should be "int", got "${dt}"'
	assert scalars[0].value == '42', 'scalar value should be "42", got "${scalars[0].value}"'
}

// Scalar event for bool type.
fn test_stream_scalar_bool_type() {
	events := cxlib.stream('[flag :bool true]') or { panic(err) }
	scalars := events.filter(it.typ == .scalar)
	assert scalars.len == 1
	dt := scalars[0].data_type or { assert false, 'scalar should have data_type'; return }
	assert dt == 'bool'
	assert scalars[0].value == 'true'
}
