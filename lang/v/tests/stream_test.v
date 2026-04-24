module main

import os
import cxlib

const fixtures = os.join_path(os.dir(@FILE), '..', '..', '..', 'fixtures')

fn fx(name string) string {
	return os.read_file(os.join_path(fixtures, name)) or {
		panic('could not read fixture ${name}: ${err}')
	}
}

// ── basic ─────────────────────────────────────────────────────────────────────

fn test_stream_basic() {
	events := cxlib.stream('[config]') or { assert false, err.msg(); return }
	types := events.map(it.typ)
	assert types == [.start_doc, .start_element, .end_element, .end_doc]
	assert events[1].name == 'config'
	assert events[2].name == 'config'
}

fn test_stream_attrs() {
	events := cxlib.stream('[server host=localhost port=8080]') or { panic(err) }
	start := events.filter(it.typ == .start_element)[0]
	assert start.name == 'server'
	assert start.attrs.len == 2
	assert start.attrs[0].name == 'host'
	assert start.attrs[0].value.str() == 'localhost'
	assert start.attrs[1].name == 'port'
	assert start.attrs[1].value.str() == '8080'
	assert (start.attrs[1].data_type or { cxlib.ScalarType.string_type }) == cxlib.ScalarType.int_type
}

fn test_stream_text() {
	events := cxlib.stream('[p Hello world]') or { panic(err) }
	texts := events.filter(it.typ == .text)
	assert texts.len == 1
	assert texts[0].value == 'Hello world'
}

fn test_stream_scalar() {
	events := cxlib.stream('[count :int 42]') or { panic(err) }
	scalars := events.filter(it.typ == .scalar)
	assert scalars.len == 1
	assert scalars[0].data_type or { '' } == 'int'
	assert scalars[0].value == '42'
}

fn test_stream_nested() {
	events := cxlib.stream('[outer [inner]]') or { panic(err) }
	outer_start := events.filter(it.typ == .start_element && it.name == 'outer')[0]
	inner_start := events.filter(it.typ == .start_element && it.name == 'inner')[0]
	inner_end   := events.filter(it.typ == .end_element && it.name == 'inner')[0]
	outer_end   := events.filter(it.typ == .end_element && it.name == 'outer')[0]
	os_idx := events.index(outer_start)
	is_idx := events.index(inner_start)
	ie_idx := events.index(inner_end)
	oe_idx := events.index(outer_end)
	assert os_idx < is_idx
	assert is_idx < ie_idx
	assert ie_idx < oe_idx
}

fn test_stream_comment() {
	events := cxlib.stream('[root [-a comment][child]]') or { panic(err) }
	comments := events.filter(it.typ == .comment)
	assert comments.len == 1
	assert comments[0].value == 'a comment'
}

fn test_stream_pi() {
	events := cxlib.stream('[root [?php return 42]]') or { panic(err) }
	pis := events.filter(it.typ == .pi)
	assert pis.len == 1
	assert pis[0].target == 'php'
	assert (pis[0].data or { '' }) == 'return 42'
}

fn test_stream_entity_ref() {
	events := cxlib.stream('[root &amp;]') or { panic(err) }
	ers := events.filter(it.typ == .entity_ref)
	assert ers.len == 1
	assert ers[0].value == 'amp'
}

fn test_stream_is_start_element() {
	events := cxlib.stream('[config host=localhost]') or { panic(err) }
	assert events.any(it.is_start_element('config'))
	assert !events.any(it.is_start_element('other'))
	assert events.any(it.is_start_element())
}

fn test_stream_is_end_element() {
	events := cxlib.stream('[config]') or { panic(err) }
	assert events.any(it.is_end_element('config'))
	assert !events.any(it.is_end_element('other'))
	assert events.any(it.is_end_element())
}

fn test_stream_parse_error() {
	_ := cxlib.stream(fx('errors/unclosed.cx')) or { return }
	assert false, 'expected error for unclosed bracket'
}

fn test_stream_multiple_top_level() {
	events := cxlib.stream(fx('api_multi.cx')) or { panic(err) }
	starts := events.filter(it.typ == .start_element && it.name == 'service')
	assert starts.len == 3
}

// ── fixture: stream_events.cx ─────────────────────────────────────────────────

fn test_stream_events_all_types() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	types := events.map(it.typ)
	for want in [cxlib.EventType.start_doc, .end_doc, .start_element, .end_element,
		.text, .scalar, .comment, .pi, .entity_ref, .raw_text, .alias_]
	{
		assert want in types, 'missing event type: ${want}'
	}
}

fn test_stream_events_comment() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	comments := events.filter(it.typ == .comment)
	assert comments.len == 1
	assert comments[0].value == 'a comment node'
}

fn test_stream_events_pi() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	pis := events.filter(it.typ == .pi)
	assert pis.len == 1
	assert pis[0].target == 'pi'
	assert (pis[0].data or { '' }) == 'pi data here'
}

fn test_stream_events_scalars() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	scalars := events.filter(it.typ == .scalar)
	assert scalars.len == 2
	assert (scalars[0].data_type or { '' }) == 'int'
	assert scalars[0].value == '42'
	assert (scalars[1].data_type or { '' }) == 'bool'
	assert scalars[1].value == 'true'
}

fn test_stream_events_alias() {
	events := cxlib.stream(fx('stream/stream_events.cx')) or { panic(err) }
	aliases := events.filter(it.typ == .alias_)
	assert aliases.len == 1
	assert aliases[0].value == 'srv'
}

fn test_stream_nested_depth() {
	events := cxlib.stream(fx('stream/stream_nested.cx')) or { panic(err) }
	starts := events.filter(it.typ == .start_element)
	names := starts.map(it.name)
	assert 'level1' in names
	assert 'level6' in names
	assert starts.len == 8, 'expected 8 start elements, got ${starts.len}: ${names}'
}
