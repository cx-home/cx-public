#!/usr/bin/env tsx
/**
 * Document API tests for TypeScript cxlib.
 *
 * Fixtures are shared with all language bindings — see fixtures/ at the repo root.
 * Run:  tsx typescript/api_test.ts
 */
import * as fs from 'fs';
import * as path from 'path';
import * as assert from 'assert';
import {
  parse, parseXml, parseJson, parseYaml,
  loads, dumps,
  loadsXml, loadsJson, loadsYaml, loadsToml, loadsMd,
  Document, Element, Attr,
  TextNode, ScalarNode,
} from './cxlib/src/ast';
import { stream } from './cxlib/src/index';
import type { StreamEvent } from './cxlib/src/binary';

// ── fixture loader ────────────────────────────────────────────────────────────

const FIXTURES = path.join(__dirname, '..', '..', 'fixtures');

function fx(name: string): string {
  return fs.readFileSync(path.join(FIXTURES, name), 'utf8');
}

// ── test runner ───────────────────────────────────────────────────────────────

let _passed = 0;
let _failed = 0;

function run(name: string, fn: () => void): void {
  try {
    fn();
    _passed++;
  } catch (e: any) {
    _failed++;
    if (e instanceof assert.AssertionError) {
      console.log(`  FAIL  ${name}: ${e.message}`);
    } else {
      console.log(`  ERROR ${name}: ${e?.constructor?.name ?? 'Error'}: ${e?.message ?? e}`);
    }
  }
}

// ── parse / root / get ────────────────────────────────────────────────────────

run('test_parse_returns_document', () => {
  const doc = parse(fx('api_config.cx'));
  assert.ok(doc instanceof Document);
});

run('test_root_returns_first_element', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.root()!.name, 'config');
});

run('test_root_none_on_empty_input', () => {
  const doc = parse('');
  assert.strictEqual(doc.root(), null);
});

run('test_get_top_level_by_name', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.get('config')!.name, 'config');
  assert.strictEqual(doc.get('missing'), null);
});

run('test_get_multi_top_level', () => {
  const doc = parse(fx('api_multi.cx'));
  assert.strictEqual(doc.get('service')!.attr('name'), 'auth');  // first match
});

run('test_parse_multiple_top_level_elements', () => {
  const doc = parse(fx('api_multi.cx'));
  const services = doc.elements.filter(
    (e): e is Element => e instanceof Element && e.name === 'service',
  );
  assert.strictEqual(services.length, 3);
});

// ── attr ──────────────────────────────────────────────────────────────────────

run('test_attr_string', () => {
  const srv = parse(fx('api_config.cx')).at('config/server')!;
  assert.strictEqual(srv.attr('host'), 'localhost');
});

run('test_attr_int', () => {
  const srv = parse(fx('api_config.cx')).at('config/server')!;
  assert.strictEqual(srv.attr('port'), 8080);
  assert.strictEqual(typeof srv.attr('port'), 'number');
});

run('test_attr_bool', () => {
  const srv = parse(fx('api_config.cx')).at('config/server')!;
  assert.strictEqual(srv.attr('debug'), false);
});

run('test_attr_float', () => {
  const srv = parse(fx('api_config.cx')).at('config/server')!;
  assert.ok(Math.abs(srv.attr('ratio') - 1.5) < 1e-9);
});

run('test_attr_missing_returns_null', () => {
  const srv = parse(fx('api_config.cx')).at('config/server')!;
  assert.strictEqual(srv.attr('nonexistent'), null);
});

// ── scalar ────────────────────────────────────────────────────────────────────

run('test_scalar_int', () => {
  const el = parse(fx('api_scalars.cx')).at('values/count')!;
  assert.strictEqual(el.scalar(), 42);
  assert.strictEqual(typeof el.scalar(), 'number');
});

run('test_scalar_float', () => {
  const el = parse(fx('api_scalars.cx')).at('values/ratio')!;
  assert.ok(Math.abs(el.scalar() - 1.5) < 1e-9);
});

run('test_scalar_bool_true', () => {
  const el = parse(fx('api_scalars.cx')).at('values/enabled')!;
  assert.strictEqual(el.scalar(), true);
});

run('test_scalar_bool_false', () => {
  const el = parse(fx('api_scalars.cx')).at('values/disabled')!;
  assert.strictEqual(el.scalar(), false);
});

run('test_scalar_null', () => {
  const el = parse(fx('api_scalars.cx')).at('values/nothing')!;
  assert.strictEqual(el.scalar(), null);
});

run('test_scalar_none_on_element_with_children', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.root()!.scalar(), null);
});

// ── text ──────────────────────────────────────────────────────────────────────

run('test_text_single_token', () => {
  const doc = parse(fx('api_article.cx'));
  assert.strictEqual(doc.at('article/body/h1')!.text(), 'Introduction');
});

run('test_text_quoted', () => {
  const el = parse(fx('api_scalars.cx')).at('values/label')!;
  assert.strictEqual(el.text(), 'hello world');
});

run('test_text_empty_on_element_with_children', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.root()!.text(), '');
});

// ── children / getAll ─────────────────────────────────────────────────────────

run('test_children_returns_only_elements', () => {
  const config = parse(fx('api_config.cx')).root()!;
  const kids = config.children();
  assert.strictEqual(kids.length, 3);
  assert.ok(kids.every(k => k instanceof Element));
  assert.deepStrictEqual(kids.map(k => k.name), ['server', 'database', 'logging']);
});

run('test_get_all_direct_children', () => {
  const doc = parse('[root [item 1] [item 2] [other x] [item 3]]');
  const items = doc.root()!.getAll('item');
  assert.strictEqual(items.length, 3);
});

run('test_get_all_returns_empty_for_missing', () => {
  const config = parse(fx('api_config.cx')).root()!;
  assert.deepStrictEqual(config.getAll('missing'), []);
});

// ── at ────────────────────────────────────────────────────────────────────────

run('test_at_single_segment', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.at('config')!.name, 'config');
});

run('test_at_two_segments', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.at('config/server')!.name, 'server');
  assert.strictEqual(doc.at('config/database')!.name, 'database');
});

run('test_at_three_segments', () => {
  const doc = parse(fx('api_article.cx'));
  assert.strictEqual(doc.at('article/head/title')!.text(), 'Getting Started with CX');
  assert.strictEqual(doc.at('article/body/h1')!.text(), 'Introduction');
});

run('test_at_missing_segment_returns_null', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.at('config/missing'), null);
});

run('test_at_missing_root_returns_null', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.at('missing'), null);
});

run('test_at_deep_missing_returns_null', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.at('config/server/missing/deep'), null);
});

run('test_element_at_relative_path', () => {
  const doc = parse(fx('api_article.cx'));
  const body = doc.at('article/body')!;
  assert.strictEqual(body.at('section/h2')!.text(), 'Details');
});

// ── findAll ───────────────────────────────────────────────────────────────────

run('test_find_all_top_level', () => {
  const doc = parse(fx('api_multi.cx'));
  assert.strictEqual(doc.findAll('service').length, 3);
});

run('test_find_all_deep', () => {
  const doc = parse(fx('api_article.cx'));
  const ps = doc.findAll('p');
  assert.strictEqual(ps.length, 3);
  assert.strictEqual(ps[0].text(), 'First paragraph.');
  assert.strictEqual(ps[1].text(), 'Nested paragraph.');
  assert.strictEqual(ps[2].text(), 'Another nested paragraph.');
});

run('test_find_all_missing_returns_empty', () => {
  const doc = parse(fx('api_config.cx'));
  assert.deepStrictEqual(doc.findAll('missing'), []);
});

run('test_find_all_on_element', () => {
  const body = parse(fx('api_article.cx')).at('article/body')!;
  assert.strictEqual(body.findAll('p').length, 3);
});

// ── findFirst ─────────────────────────────────────────────────────────────────

run('test_find_first_returns_first_match', () => {
  const doc = parse(fx('api_article.cx'));
  const p = doc.findFirst('p');
  assert.ok(p !== null);
  assert.strictEqual(p!.text(), 'First paragraph.');
});

run('test_find_first_missing_returns_null', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.findFirst('missing'), null);
});

run('test_find_first_depth_first_order', () => {
  const doc = parse(fx('api_article.cx'));
  assert.strictEqual(doc.findFirst('h1')!.text(), 'Introduction');
  assert.strictEqual(doc.findFirst('h2')!.text(), 'Details');
});

run('test_find_first_on_element', () => {
  const section = parse(fx('api_article.cx')).at('article/body/section')!;
  const p = section.findFirst('p');
  assert.ok(p !== null);
  assert.strictEqual(p!.text(), 'Nested paragraph.');
});

// ── mutation — Element ────────────────────────────────────────────────────────

run('test_append_adds_to_end', () => {
  const doc = parse(fx('api_config.cx'));
  doc.root()!.append(new Element({ name: 'cache' }));
  const kids = doc.root()!.children();
  assert.strictEqual(kids[kids.length - 1].name, 'cache');
  assert.strictEqual(kids.length, 4);
});

run('test_prepend_adds_to_front', () => {
  const doc = parse(fx('api_config.cx'));
  doc.root()!.prepend(new Element({ name: 'meta' }));
  assert.strictEqual(doc.root()!.children()[0].name, 'meta');
});

run('test_insert_at_index', () => {
  const doc = parse('[root [a 1] [c 3]]');
  doc.root()!.insert(1, new Element({ name: 'b' }));
  assert.deepStrictEqual(doc.root()!.children().map(k => k.name), ['a', 'b', 'c']);
});

run('test_remove_by_identity', () => {
  const doc = parse(fx('api_config.cx'));
  const db = doc.at('config/database')!;
  doc.root()!.remove(db);
  assert.strictEqual(doc.at('config/database'), null);
  assert.ok(doc.at('config/server') !== null);
});

run('test_set_attr_new', () => {
  const doc = parse(fx('api_config.cx'));
  const srv = doc.at('config/server')!;
  srv.setAttr('env', 'production');
  assert.strictEqual(srv.attr('env'), 'production');
});

run('test_set_attr_update_value', () => {
  const doc = parse(fx('api_config.cx'));
  const srv = doc.at('config/server')!;
  srv.setAttr('port', 9090, 'int');
  assert.strictEqual(srv.attr('port'), 9090);
  assert.strictEqual(srv.attrs.length, 4);  // no duplicate; original count unchanged
});

run('test_set_attr_change_type', () => {
  const doc = parse(fx('api_config.cx'));
  const srv = doc.at('config/server')!;
  const originalCount = srv.attrs.length;
  srv.setAttr('debug', true, 'bool');
  assert.strictEqual(srv.attr('debug'), true);
  assert.strictEqual(srv.attrs.length, originalCount);
});

run('test_remove_attr', () => {
  const doc = parse(fx('api_config.cx'));
  const srv = doc.at('config/server')!;
  const originalCount = srv.attrs.length;
  srv.removeAttr('debug');
  assert.strictEqual(srv.attr('debug'), null);
  assert.strictEqual(srv.attrs.length, originalCount - 1);
});

run('test_remove_attr_nonexistent_is_noop', () => {
  const doc = parse(fx('api_config.cx'));
  const srv = doc.at('config/server')!;
  const originalCount = srv.attrs.length;
  srv.removeAttr('nonexistent');
  assert.strictEqual(srv.attrs.length, originalCount);
});

// ── mutation — Document ───────────────────────────────────────────────────────

run('test_doc_append_element', () => {
  const doc = parse(fx('api_config.cx'));
  doc.append(new Element({ name: 'cache', attrs: [{ name: 'host', value: 'redis' }] }));
  assert.strictEqual(doc.get('cache')!.attr('host'), 'redis');
});

run('test_doc_prepend_makes_new_root', () => {
  const doc = parse(fx('api_config.cx'));
  doc.prepend(new Element({ name: 'preamble' }));
  assert.strictEqual(doc.root()!.name, 'preamble');
  assert.ok(doc.get('config') !== null);  // original still present
});

// ── round-trips ───────────────────────────────────────────────────────────────

run('test_to_cx_round_trip', () => {
  const original = parse(fx('api_config.cx'));
  const reparsed = parse(original.to_cx());
  assert.strictEqual(reparsed.at('config/server')!.attr('host'), 'localhost');
  assert.strictEqual(reparsed.at('config/server')!.attr('port'), 8080);
  assert.strictEqual(reparsed.at('config/database')!.attr('name'), 'myapp');
});

run('test_to_cx_round_trip_after_mutation', () => {
  const doc = parse(fx('api_config.cx'));
  doc.at('config/server')!.setAttr('env', 'production');
  doc.at('config/server')!.append(new Element({
    name: 'timeout',
    items: [new ScalarNode('int', 30)],
  }));
  const reparsed = parse(doc.to_cx());
  assert.strictEqual(reparsed.at('config/server')!.attr('env'), 'production');
  assert.strictEqual(reparsed.at('config/server')!.findFirst('timeout')!.scalar(), 30);
});

run('test_to_cx_preserves_article_structure', () => {
  const original = parse(fx('api_article.cx'));
  const reparsed = parse(original.to_cx());
  assert.strictEqual(reparsed.at('article/head/title')!.text(), 'Getting Started with CX');
  assert.strictEqual(reparsed.findAll('p').length, 3);
});

// ── loads / dumps ─────────────────────────────────────────────────────────────

run('test_loads_returns_object', () => {
  const data = loads(fx('api_config.cx'));
  assert.strictEqual(typeof data, 'object');
  assert.strictEqual(data['config']['server']['host'], 'localhost');
  assert.strictEqual(data['config']['server']['port'], 8080);
});

run('test_loads_bool_types', () => {
  const data = loads(fx('api_config.cx'));
  assert.strictEqual(data['config']['server']['debug'], false);
});

run('test_loads_scalars', () => {
  const data = loads(fx('api_scalars.cx'));
  assert.strictEqual(data['values']['count'], 42);
  assert.strictEqual(data['values']['enabled'], true);
  assert.strictEqual(data['values']['disabled'], false);
  assert.strictEqual(data['values']['nothing'], null);
});

run('test_dumps_produces_parseable_cx', () => {
  const original = { app: { name: 'myapp', version: '1.0', port: 8080 } };
  const cxStr = dumps(original);
  const reparsed = parse(cxStr);
  assert.ok(reparsed.findFirst('app') !== null);
});

run('test_loads_dumps_data_preserved', () => {
  const original = { server: { host: 'localhost', port: 8080, debug: false } };
  const restored = loads(dumps(original));
  assert.strictEqual(restored['server']['port'], 8080);
  assert.strictEqual(restored['server']['host'], 'localhost');
  assert.strictEqual(restored['server']['debug'], false);
});

// ── loadsXml / loadsJson / loadsYaml / loadsToml / loadsMd ───────────────────

run('test_loads_xml', () => {
  const xmlData = loadsXml('<root><item>42</item></root>');
  assert.ok(xmlData);
});

run('test_loads_json', () => {
  const jsonData = loadsJson('{"server":{"host":"localhost"}}');
  assert.strictEqual(jsonData.server.host, 'localhost');
});

run('test_loads_yaml', () => {
  const yamlData = loadsYaml('server:\n  host: localhost\n');
  assert.ok(yamlData);
});

run('test_loads_toml', () => {
  const tomlData = loadsToml('[server]\nhost = "localhost"\n');
  assert.ok(tomlData);
});

run('test_loads_md', () => {
  const mdData = loadsMd('# hello\n\nworld\n');
  assert.ok(mdData);
});

// ── error / failure cases ─────────────────────────────────────────────────────

run('test_parse_error_unclosed_bracket', () => {
  let threw = false;
  try {
    parse(fx('errors/unclosed.cx'));
  } catch (_) {
    threw = true;
  }
  assert.ok(threw, 'expected parse error for unclosed bracket');
});

run('test_parse_error_empty_element_name', () => {
  let threw = false;
  try {
    parse(fx('errors/empty_name.cx'));
  } catch (_) {
    threw = true;
  }
  assert.ok(threw, 'expected parse error for empty element name');
});

run('test_parse_error_nested_unclosed', () => {
  let threw = false;
  try {
    parse(fx('errors/nested_unclosed.cx'));
  } catch (_) {
    threw = true;
  }
  assert.ok(threw, 'expected parse error for nested unclosed bracket');
});

run('test_at_missing_path_returns_null_not_error', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.at('config/server/missing/deep/path'), null);
});

run('test_find_all_on_empty_doc_returns_empty', () => {
  const doc = parse('');
  assert.deepStrictEqual(doc.findAll('anything'), []);
});

run('test_find_first_on_empty_doc_returns_null', () => {
  const doc = parse('');
  assert.strictEqual(doc.findFirst('anything'), null);
});

run('test_scalar_null_when_element_has_child_elements', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.root()!.scalar(), null);
});

run('test_text_empty_when_no_text_children', () => {
  const doc = parse(fx('api_config.cx'));
  assert.strictEqual(doc.root()!.text(), '');
});

run('test_remove_attr_nonexistent_does_not_raise', () => {
  const doc = parse(fx('api_config.cx'));
  const srv = doc.at('config/server')!;
  srv.removeAttr('totally_missing');  // should not throw
});

run('test_parse_xml_invalid', () => {
  let threw = false;
  try {
    parseXml('<unclosed');
  } catch (_) {
    threw = true;
  }
  assert.ok(threw, 'expected parse error for invalid XML');
});

// ── parse other formats ───────────────────────────────────────────────────────

run('test_parse_xml', () => {
  const doc = parseXml('<root><child key="val"/></root>');
  assert.strictEqual(doc.root()!.name, 'root');
  const child = doc.findFirst('child');
  assert.ok(child !== null);
});

run('test_parse_json_to_document', () => {
  const doc = parseJson('{"server": {"port": 8080}}');
  assert.ok(doc.findFirst('server') !== null);
});

run('test_parse_yaml_to_document', () => {
  const doc = parseYaml('server:\n  port: 8080\n');
  assert.ok(doc.findFirst('server') !== null);
});

// ── stream ────────────────────────────────────────────────────────────────────

run('test_stream_returns_array', () => {
  const events = stream('[root hello]');
  assert.ok(Array.isArray(events));
  assert.ok(events.length > 0);
});

run('test_stream_startdoc_enddoc', () => {
  const events = stream('[root]');
  assert.strictEqual(events[0].type, 'StartDoc');
  assert.strictEqual(events[events.length - 1].type, 'EndDoc');
});

run('test_stream_start_end_element', () => {
  const events = stream('[root]');
  const types = events.map((e: StreamEvent) => e.type);
  assert.ok(types.includes('StartElement'));
  assert.ok(types.includes('EndElement'));
  const start = events.find((e: StreamEvent) => e.type === 'StartElement');
  assert.strictEqual(start!.name, 'root');
  const end = events.find((e: StreamEvent) => e.type === 'EndElement');
  assert.strictEqual(end!.name, 'root');
});

run('test_stream_element_with_attrs', () => {
  const events = stream('[server host=localhost port=8080 debug=false]');
  const start = events.find((e: StreamEvent) => e.type === 'StartElement' && e.name === 'server');
  assert.ok(start !== undefined);
  assert.ok(Array.isArray(start!.attrs));
  const host = start!.attrs!.find((a: Attr) => a.name === 'host');
  assert.strictEqual(host!.value, 'localhost');
  const port = start!.attrs!.find((a: Attr) => a.name === 'port');
  assert.strictEqual(port!.value, 8080);
  assert.strictEqual(typeof port!.value, 'number');
  const debug = start!.attrs!.find((a: Attr) => a.name === 'debug');
  assert.strictEqual(debug!.value, false);
});

run('test_stream_text_event', () => {
  const events = stream('[p hello]');
  const text = events.find((e: StreamEvent) => e.type === 'Text');
  assert.ok(text !== undefined);
  assert.strictEqual(text!.value, 'hello');
});

run('test_stream_nested_elements', () => {
  const events = stream('[root [child foo]]');
  const starts = events.filter((e: StreamEvent) => e.type === 'StartElement');
  assert.strictEqual(starts.length, 2);
  assert.strictEqual(starts[0].name, 'root');
  assert.strictEqual(starts[1].name, 'child');
});

run('test_stream_scalar_event', () => {
  const events = stream('[count 42]');
  const scalar = events.find((e: StreamEvent) => e.type === 'Scalar');
  assert.ok(scalar !== undefined);
  assert.strictEqual(scalar!.value, 42);
  assert.strictEqual(typeof scalar!.value, 'number');
});

run('test_stream_multiple_top_level', () => {
  const events = stream(fx('api_multi.cx'));
  const starts = events.filter((e: StreamEvent) => e.type === 'StartElement' && e.name === 'service');
  assert.strictEqual(starts.length, 3);
});

// ── removeChild / removeAt ────────────────────────────────────────────────────

run('test_remove_child_removes_all_matching', () => {
  const doc = parse('[root [item a] [item b] [other x] [item c]]');
  doc.root()!.removeChild('item');
  assert.deepStrictEqual(doc.root()!.children().map(k => k.name), ['other']);
});

run('test_remove_child_nonexistent_is_noop', () => {
  const doc = parse(fx('api_config.cx'));
  const before = doc.root()!.children().length;
  doc.root()!.removeChild('missing');
  assert.strictEqual(doc.root()!.children().length, before);
});

run('test_remove_at_removes_by_index', () => {
  const doc = parse('[root [a 1] [b 2] [c 3]]');
  doc.root()!.removeAt(1);
  assert.deepStrictEqual(doc.root()!.children().map(k => k.name), ['a', 'c']);
});

run('test_remove_at_out_of_bounds_is_noop', () => {
  const doc = parse('[root [a 1] [b 2]]');
  const before = doc.root()!.children().length;
  doc.root()!.removeAt(99);
  assert.strictEqual(doc.root()!.children().length, before);
  doc.root()!.removeAt(-1);
  assert.strictEqual(doc.root()!.children().length, before);
});

// ── selectAll / select ────────────────────────────────────────────────────────

run('test_select_all_descendant_axis', () => {
  const doc = parse(fx('api_multi.cx'));
  const results = doc.selectAll('//service');
  assert.strictEqual(results.length, 3);
});

run('test_select_all_attr_predicate', () => {
  const doc = parse('[services [service name=auth active=true] [service name=api active=false] [service name=web active=true]]');
  const results = doc.selectAll('//service[@active=true]');
  assert.strictEqual(results.length, 2);
  assert.deepStrictEqual(results.map(r => r.attr('name')), ['auth', 'web']);
});

run('test_select_returns_first', () => {
  const doc = parse(fx('api_multi.cx'));
  const first = doc.select('//service');
  assert.ok(first !== null);
  assert.strictEqual(first!.attr('name'), 'auth');
});

run('test_select_all_child_path', () => {
  const doc = parse(fx('api_config.cx'));
  const results = doc.selectAll('config/server');
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].attr('host'), 'localhost');
});

run('test_select_all_wildcard', () => {
  const doc = parse(fx('api_config.cx'));
  const results = doc.selectAll('config/*');
  assert.strictEqual(results.length, 3);
});

run('test_select_all_numeric_comparison', () => {
  const doc = parse('[root [service name=auth port=80] [service name=api port=8080] [service name=worker port=9000]]');
  const results = doc.selectAll('//service[@port>=8000]');
  assert.strictEqual(results.length, 2);
  assert.deepStrictEqual(results.map(r => r.attr('name')), ['api', 'worker']);
});

run('test_select_all_position', () => {
  const doc = parse(fx('api_multi.cx'));
  const second = doc.select('//service[2]');
  assert.ok(second !== null);
  assert.strictEqual(second!.attr('name'), 'api');
});

run('test_select_all_last_position', () => {
  const doc = parse(fx('api_multi.cx'));
  const last = doc.select('//service[last()]');
  assert.ok(last !== null);
  assert.strictEqual(last!.attr('name'), 'worker');
});

run('test_select_all_contains', () => {
  const doc = parse('[root [service name=auth] [service name=api] [service name=web]]');
  const results = doc.selectAll("//service[contains(@name, 'a')]");
  // 'auth', 'api' contain 'a'
  assert.ok(results.length >= 2);
  assert.ok(results.every(r => (r.attr('name') as string).includes('a')));
});

run('test_select_all_starts_with', () => {
  const doc = parse('[root [service name=auth] [service name=api] [service name=web]]');
  const results = doc.selectAll("//service[starts-with(@name, 'a')]");
  assert.strictEqual(results.length, 2);
  assert.ok(results.every(r => (r.attr('name') as string).startsWith('a')));
});

run('test_select_all_bool_and', () => {
  const doc = parse('[root [service name=auth active=true port=8080] [service name=api active=false port=9000] [service name=web active=true port=80]]');
  const results = doc.selectAll('//service[@active=true and @port=8080]');
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].attr('name'), 'auth');
});

run('test_select_on_element_searches_subtree', () => {
  const doc = parse(fx('api_multi.cx'));
  // selectAll on a single top-level service element — it has no children named service
  // so this tests that Element.select* searches the subtree of that element
  const doc2 = parse('[root [group [service name=inner]] [service name=outer]]');
  const group = doc2.root()!.get('group')!;
  const results = group.selectAll('//service');
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].attr('name'), 'inner');
});

run('test_select_invalid_expr_throws', () => {
  const doc = parse(fx('api_config.cx'));
  let threw = false;
  try {
    doc.selectAll('');
  } catch (_) {
    threw = true;
  }
  assert.ok(threw, 'expected error for empty expression');
});

// ── transform ─────────────────────────────────────────────────────────────────

run('test_transform_returns_new_document', () => {
  const doc = parse(fx('api_config.cx'));
  const updated = doc.transform('config/server', el => {
    el.setAttr('host', 'prod.example.com');
    return el;
  });
  assert.ok(updated !== doc);
  assert.ok(updated instanceof Document);
});

run('test_transform_applies_function', () => {
  const doc = parse(fx('api_config.cx'));
  const updated = doc.transform('config/server', el => {
    el.setAttr('host', 'prod.example.com');
    return el;
  });
  assert.strictEqual(updated.at('config/server')!.attr('host'), 'prod.example.com');
});

run('test_transform_original_unchanged', () => {
  const doc = parse(fx('api_config.cx'));
  doc.transform('config/server', el => {
    el.setAttr('host', 'prod.example.com');
    return el;
  });
  assert.strictEqual(doc.at('config/server')!.attr('host'), 'localhost');
});

run('test_transform_missing_path_returns_original', () => {
  const doc = parse(fx('api_config.cx'));
  const result = doc.transform('config/missing', el => {
    el.setAttr('host', 'x');
    return el;
  });
  assert.ok(result === doc);
});

run('test_transform_chained', () => {
  const doc = parse(fx('api_config.cx'));
  const result = doc
    .transform('config/server', el => { el.setAttr('host', 'web.example.com'); return el; })
    .transform('config/database', el => { el.setAttr('host', 'db.example.com'); return el; });
  assert.strictEqual(result.at('config/server')!.attr('host'), 'web.example.com');
  assert.strictEqual(result.at('config/database')!.attr('host'), 'db.example.com');
  assert.strictEqual(doc.at('config/server')!.attr('host'), 'localhost');
});

// ── transformAll ──────────────────────────────────────────────────────────────

run('test_transform_all_applies_to_all_matching', () => {
  const doc = parse('[services [service name=auth port=8080] [service name=api port=9000]]');
  const updated = doc.transformAll('//service', el => {
    el.setAttr('active', true);
    return el;
  });
  const services = updated.findAll('service');
  assert.ok(services.every(s => s.attr('active') === true));
});

run('test_transform_all_returns_new_document', () => {
  const doc = parse(fx('api_config.cx'));
  const updated = doc.transformAll('//server', el => el);
  assert.ok(updated !== doc);
  assert.ok(updated instanceof Document);
});

run('test_transform_all_no_match_returns_equivalent', () => {
  const doc = parse(fx('api_config.cx'));
  const updated = doc.transformAll('//nonexistent', el => {
    el.setAttr('touched', true);
    return el;
  });
  // No match — structure should be equivalent
  assert.strictEqual(updated.at('config/server')!.attr('host'), 'localhost');
});

run('test_transform_all_deeply_nested', () => {
  const doc = parse(fx('api_article.cx'));
  const updated = doc.transformAll('//p', el => {
    el.setAttr('processed', true);
    return el;
  });
  const ps = updated.findAll('p');
  assert.strictEqual(ps.length, 3);
  assert.ok(ps.every(p => p.attr('processed') === true));
  // Original should be unchanged
  assert.ok(doc.findAll('p').every(p => p.attr('processed') === null));
});

// ── main ──────────────────────────────────────────────────────────────────────

const total = _passed + _failed;
const status = _failed === 0 ? 'OK' : 'FAILED';
console.log(`typescript/api_test.ts: ${_passed} passed, ${_failed} failed  [${status}]`);
process.exit(_failed === 0 ? 0 : 1);
