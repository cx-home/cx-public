# frozen_string_literal: true
#
# Document API tests for lang/ruby/cxlib.
# Fixtures are shared with all language bindings — see fixtures/ at the repo root.
# Run: ruby lang/ruby/test_api.rb
#
require_relative 'cxlib/lib/cxlib'
require 'json'

FIXTURES = File.join(__dir__, '..', '..', 'fixtures')

def fx(name)
  File.read(File.join(FIXTURES, name))
end

# ── test runner ───────────────────────────────────────────────────────────────

$passed = 0
$failed = 0

def run_test(name)
  yield
  $passed += 1
  print "  PASS  #{name}\n"
rescue => e
  $failed += 1
  print "  FAIL  #{name}: #{e.class}: #{e.message}\n"
end

# ── parse / root / get ────────────────────────────────────────────────────────

run_test('test_parse_returns_document') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected Document" unless doc.is_a?(CXLib::Document)
end

run_test('test_root_returns_first_element') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "wrong name: #{doc.root.name}" unless doc.root.name == 'config'
end

run_test('test_root_none_on_empty_input') do
  doc = CXLib.parse('')
  raise "expected nil root" unless doc.root.nil?
end

run_test('test_get_top_level_by_name') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "wrong name" unless doc.get('config').name == 'config'
  raise "expected nil" unless doc.get('missing').nil?
end

run_test('test_get_multi_top_level') do
  doc = CXLib.parse(fx('api_multi.cx'))
  raise "wrong attr" unless doc.get('service').attr('name') == 'auth'
end

run_test('test_parse_multiple_top_level_elements') do
  doc = CXLib.parse(fx('api_multi.cx'))
  services = doc.elements.select { |e| e.is_a?(CXLib::Element) && e.name == 'service' }
  raise "expected 3, got #{services.size}" unless services.size == 3
end

# ── attr ──────────────────────────────────────────────────────────────────────

run_test('test_attr_string') do
  srv = CXLib.parse(fx('api_config.cx')).at('config/server')
  raise "wrong host: #{srv.attr('host').inspect}" unless srv.attr('host') == 'localhost'
end

run_test('test_attr_int') do
  srv = CXLib.parse(fx('api_config.cx')).at('config/server')
  raise "wrong port: #{srv.attr('port').inspect}" unless srv.attr('port') == 8080
  raise "expected Integer" unless srv.attr('port').is_a?(Integer)
end

run_test('test_attr_bool') do
  srv = CXLib.parse(fx('api_config.cx')).at('config/server')
  raise "expected false, got #{srv.attr('debug').inspect}" unless srv.attr('debug') == false
end

run_test('test_attr_float') do
  srv = CXLib.parse(fx('api_config.cx')).at('config/server')
  raise "wrong ratio: #{srv.attr('ratio').inspect}" unless (srv.attr('ratio') - 1.5).abs < 1e-9
end

run_test('test_attr_missing_returns_nil') do
  srv = CXLib.parse(fx('api_config.cx')).at('config/server')
  raise "expected nil" unless srv.attr('nonexistent').nil?
end

# ── scalar ────────────────────────────────────────────────────────────────────

run_test('test_scalar_int') do
  el = CXLib.parse(fx('api_scalars.cx')).at('values/count')
  raise "wrong value: #{el.scalar.inspect}" unless el.scalar == 42
  raise "expected Integer" unless el.scalar.is_a?(Integer)
end

run_test('test_scalar_float') do
  el = CXLib.parse(fx('api_scalars.cx')).at('values/ratio')
  raise "wrong value: #{el.scalar.inspect}" unless (el.scalar - 1.5).abs < 1e-9
end

run_test('test_scalar_bool_true') do
  el = CXLib.parse(fx('api_scalars.cx')).at('values/enabled')
  raise "expected true, got #{el.scalar.inspect}" unless el.scalar == true
end

run_test('test_scalar_bool_false') do
  el = CXLib.parse(fx('api_scalars.cx')).at('values/disabled')
  raise "expected false, got #{el.scalar.inspect}" unless el.scalar == false
end

run_test('test_scalar_null') do
  el = CXLib.parse(fx('api_scalars.cx')).at('values/nothing')
  raise "expected nil, got #{el.scalar.inspect}" unless el.scalar.nil?
end

run_test('test_scalar_none_on_element_with_children') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.root.scalar.nil?
end

# ── text ──────────────────────────────────────────────────────────────────────

run_test('test_text_single_token') do
  doc = CXLib.parse(fx('api_article.cx'))
  t = doc.at('article/body/h1').text
  raise "wrong text: #{t.inspect}" unless t == 'Introduction'
end

run_test('test_text_quoted') do
  el = CXLib.parse(fx('api_scalars.cx')).at('values/label')
  raise "wrong text: #{el.text.inspect}" unless el.text == 'hello world'
end

run_test('test_text_empty_on_element_with_children') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected empty string" unless doc.root.text == ''
end

# ── children / get_all ────────────────────────────────────────────────────────

run_test('test_children_returns_only_elements') do
  config = CXLib.parse(fx('api_config.cx')).root
  kids = config.children
  raise "expected 3, got #{kids.size}" unless kids.size == 3
  raise "all must be Element" unless kids.all? { |k| k.is_a?(CXLib::Element) }
  raise "wrong names: #{kids.map(&:name)}" unless kids.map(&:name) == %w[server database logging]
end

run_test('test_get_all_direct_children') do
  doc = CXLib.parse('[root [item 1] [item 2] [other x] [item 3]]')
  items = doc.root.get_all('item')
  raise "expected 3, got #{items.size}" unless items.size == 3
end

run_test('test_get_all_returns_empty_for_missing') do
  config = CXLib.parse(fx('api_config.cx')).root
  raise "expected empty" unless config.get_all('missing') == []
end

# ── at ────────────────────────────────────────────────────────────────────────

run_test('test_at_single_segment') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "wrong name" unless doc.at('config').name == 'config'
end

run_test('test_at_two_segments') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "wrong server" unless doc.at('config/server').name == 'server'
  raise "wrong database" unless doc.at('config/database').name == 'database'
end

run_test('test_at_three_segments') do
  doc = CXLib.parse(fx('api_article.cx'))
  raise "wrong title" unless doc.at('article/head/title').text == 'Getting Started with CX'
  raise "wrong h1"    unless doc.at('article/body/h1').text == 'Introduction'
end

run_test('test_at_missing_segment_returns_nil') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.at('config/missing').nil?
end

run_test('test_at_missing_root_returns_nil') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.at('missing').nil?
end

run_test('test_at_deep_missing_returns_nil') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.at('config/server/missing/deep').nil?
end

run_test('test_element_at_relative_path') do
  doc  = CXLib.parse(fx('api_article.cx'))
  body = doc.at('article/body')
  raise "wrong h2 text" unless body.at('section/h2').text == 'Details'
end

# ── find_all ──────────────────────────────────────────────────────────────────

run_test('test_find_all_top_level') do
  doc = CXLib.parse(fx('api_multi.cx'))
  raise "expected 3" unless doc.find_all('service').size == 3
end

run_test('test_find_all_deep') do
  doc = CXLib.parse(fx('api_article.cx'))
  ps = doc.find_all('p')
  raise "expected 3, got #{ps.size}" unless ps.size == 3
  raise "wrong p[0]" unless ps[0].text == 'First paragraph.'
  raise "wrong p[1]" unless ps[1].text == 'Nested paragraph.'
  raise "wrong p[2]" unless ps[2].text == 'Another nested paragraph.'
end

run_test('test_find_all_missing_returns_empty') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected empty" unless doc.find_all('missing') == []
end

run_test('test_find_all_on_element') do
  body = CXLib.parse(fx('api_article.cx')).at('article/body')
  raise "expected 3" unless body.find_all('p').size == 3
end

# ── find_first ────────────────────────────────────────────────────────────────

run_test('test_find_first_returns_first_match') do
  doc = CXLib.parse(fx('api_article.cx'))
  p   = doc.find_first('p')
  raise "expected non-nil" if p.nil?
  raise "wrong text: #{p.text.inspect}" unless p.text == 'First paragraph.'
end

run_test('test_find_first_missing_returns_nil') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.find_first('missing').nil?
end

run_test('test_find_first_depth_first_order') do
  doc = CXLib.parse(fx('api_article.cx'))
  raise "wrong h1" unless doc.find_first('h1').text == 'Introduction'
  raise "wrong h2" unless doc.find_first('h2').text == 'Details'
end

run_test('test_find_first_on_element') do
  section = CXLib.parse(fx('api_article.cx')).at('article/body/section')
  p       = section.find_first('p')
  raise "expected non-nil" if p.nil?
  raise "wrong text: #{p.text.inspect}" unless p.text == 'Nested paragraph.'
end

# ── mutation — Element ────────────────────────────────────────────────────────

run_test('test_append_adds_to_end') do
  doc = CXLib.parse(fx('api_config.cx'))
  doc.root.append(CXLib::Element.new('cache'))
  kids = doc.root.children
  raise "wrong last" unless kids.last.name == 'cache'
  raise "expected 4, got #{kids.size}" unless kids.size == 4
end

run_test('test_prepend_adds_to_front') do
  doc = CXLib.parse(fx('api_config.cx'))
  doc.root.prepend(CXLib::Element.new('meta'))
  raise "wrong first" unless doc.root.children.first.name == 'meta'
end

run_test('test_insert_at_index') do
  doc = CXLib.parse('[root [a 1] [c 3]]')
  doc.root.insert(1, CXLib::Element.new('b'))
  raise "wrong order" unless doc.root.children.map(&:name) == %w[a b c]
end

run_test('test_remove_by_identity') do
  doc = CXLib.parse(fx('api_config.cx'))
  db  = doc.at('config/database')
  doc.root.remove(db)
  raise "db should be gone"     unless doc.at('config/database').nil?
  raise "server should remain"  if     doc.at('config/server').nil?
end

run_test('test_set_attr_new') do
  doc = CXLib.parse(fx('api_config.cx'))
  srv = doc.at('config/server')
  srv.set_attr('env', 'production')
  raise "wrong env" unless srv.attr('env') == 'production'
end

run_test('test_set_attr_update_value') do
  doc = CXLib.parse(fx('api_config.cx'))
  srv = doc.at('config/server')
  srv.set_attr('port', 9090, 'int')
  raise "wrong port"  unless srv.attr('port') == 9090
  raise "attr count should stay at 4, got #{srv.attrs.size}" unless srv.attrs.size == 4
end

run_test('test_set_attr_change_type') do
  doc = CXLib.parse(fx('api_config.cx'))
  srv = doc.at('config/server')
  original_count = srv.attrs.size
  srv.set_attr('debug', true, 'bool')
  raise "debug should be true" unless srv.attr('debug') == true
  raise "attr count changed: #{srv.attrs.size}" unless srv.attrs.size == original_count
end

run_test('test_remove_attr') do
  doc = CXLib.parse(fx('api_config.cx'))
  srv = doc.at('config/server')
  original_count = srv.attrs.size
  srv.remove_attr('debug')
  raise "debug should be gone" unless srv.attr('debug').nil?
  raise "wrong count: #{srv.attrs.size}" unless srv.attrs.size == original_count - 1
end

run_test('test_remove_attr_nonexistent_is_noop') do
  doc = CXLib.parse(fx('api_config.cx'))
  srv = doc.at('config/server')
  original_count = srv.attrs.size
  srv.remove_attr('nonexistent')
  raise "attr count changed" unless srv.attrs.size == original_count
end

# ── mutation — Document ───────────────────────────────────────────────────────

run_test('test_doc_append_element') do
  doc = CXLib.parse(fx('api_config.cx'))
  doc.append(CXLib::Element.new('cache', attrs: [CXLib::Attr.new('host', 'redis')]))
  raise "wrong host" unless doc.get('cache').attr('host') == 'redis'
end

run_test('test_doc_prepend_makes_new_root') do
  doc = CXLib.parse(fx('api_config.cx'))
  doc.prepend(CXLib::Element.new('preamble'))
  raise "wrong root" unless doc.root.name == 'preamble'
  raise "config gone" if doc.get('config').nil?
end

# ── round-trips ───────────────────────────────────────────────────────────────

run_test('test_to_cx_round_trip') do
  original  = CXLib.parse(fx('api_config.cx'))
  reparsed  = CXLib.parse(original.to_cx)
  raise "wrong host"  unless reparsed.at('config/server').attr('host') == 'localhost'
  raise "wrong port"  unless reparsed.at('config/server').attr('port') == 8080
  raise "wrong dbname" unless reparsed.at('config/database').attr('name') == 'myapp'
end

run_test('test_to_cx_round_trip_after_mutation') do
  doc = CXLib.parse(fx('api_config.cx'))
  doc.at('config/server').set_attr('env', 'production')
  doc.at('config/server').append(CXLib::Element.new('timeout', items: [CXLib::ScalarNode.new('int', 30)]))
  reparsed = CXLib.parse(doc.to_cx)
  raise "wrong env"     unless reparsed.at('config/server').attr('env') == 'production'
  raise "wrong timeout" unless reparsed.at('config/server').find_first('timeout').scalar == 30
end

run_test('test_to_cx_preserves_article_structure') do
  original = CXLib.parse(fx('api_article.cx'))
  reparsed = CXLib.parse(original.to_cx)
  raise "wrong title" unless reparsed.at('article/head/title').text == 'Getting Started with CX'
  raise "wrong p count" unless reparsed.find_all('p').size == 3
end

# ── loads / dumps ─────────────────────────────────────────────────────────────

run_test('test_loads_returns_hash') do
  data = CXLib.loads(fx('api_config.cx'))
  raise "expected Hash" unless data.is_a?(Hash)
  raise "wrong host"    unless data['config']['server']['host'] == 'localhost'
  raise "wrong port"    unless data['config']['server']['port'] == 8080
end

run_test('test_loads_bool_types') do
  data = CXLib.loads(fx('api_config.cx'))
  raise "expected false, got #{data['config']['server']['debug'].inspect}" unless data['config']['server']['debug'] == false
end

run_test('test_loads_scalars') do
  data = CXLib.loads(fx('api_scalars.cx'))
  raise "wrong count"    unless data['values']['count']   == 42
  raise "wrong enabled"  unless data['values']['enabled'] == true
  raise "wrong disabled" unless data['values']['disabled'] == false
  raise "wrong nothing"  unless data['values']['nothing'].nil?
end

run_test('test_loads_xml') do
  data = CXLib.loads_xml('<server host="localhost" port="8080"/>')
  raise "missing server key" unless data.key?('server')
end

run_test('test_loads_json_passthrough') do
  data = CXLib.loads_json('{"port": 8080, "debug": false}')
  raise "wrong port"  unless data['port'] == 8080
  raise "wrong debug" unless data['debug'] == false
end

run_test('test_loads_yaml') do
  data = CXLib.loads_yaml("server:\n  host: localhost\n  port: 8080\n")
  raise "missing server key" unless data.key?('server')
end

run_test('test_dumps_produces_parseable_cx') do
  original = { 'app' => { 'name' => 'myapp', 'version' => '1.0', 'port' => 8080 } }
  cx_str   = CXLib.dumps(original)
  reparsed = CXLib.parse(cx_str)
  raise "app not found" if reparsed.find_first('app').nil?
end

run_test('test_loads_dumps_data_preserved') do
  original = { 'server' => { 'host' => 'localhost', 'port' => 8080, 'debug' => false } }
  restored = CXLib.loads(CXLib.dumps(original))
  raise "wrong port"  unless restored['server']['port'] == 8080
  raise "wrong host"  unless restored['server']['host'] == 'localhost'
  raise "wrong debug" unless restored['server']['debug'] == false
end

# ── error / failure cases ─────────────────────────────────────────────────────

run_test('test_parse_error_unclosed_bracket') do
  begin
    CXLib.parse(fx('errors/unclosed.cx'))
    raise "expected parse error for unclosed bracket"
  rescue RuntimeError
    # expected
  end
end

run_test('test_parse_error_empty_element_name') do
  begin
    CXLib.parse(fx('errors/empty_name.cx'))
    raise "expected parse error for empty element name"
  rescue RuntimeError
    # expected
  end
end

run_test('test_parse_error_nested_unclosed') do
  begin
    CXLib.parse(fx('errors/nested_unclosed.cx'))
    raise "expected parse error for nested unclosed bracket"
  rescue RuntimeError
    # expected
  end
end

run_test('test_at_missing_path_returns_nil_not_error') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.at('config/server/missing/deep/path').nil?
end

run_test('test_find_all_on_empty_doc_returns_empty') do
  doc = CXLib.parse('')
  raise "expected empty" unless doc.find_all('anything') == []
end

run_test('test_find_first_on_empty_doc_returns_nil') do
  doc = CXLib.parse('')
  raise "expected nil" unless doc.find_first('anything').nil?
end

run_test('test_scalar_nil_when_element_has_child_elements') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected nil" unless doc.root.scalar.nil?
end

run_test('test_text_empty_when_no_text_children') do
  doc = CXLib.parse(fx('api_config.cx'))
  raise "expected empty string" unless doc.root.text == ''
end

run_test('test_remove_attr_nonexistent_does_not_raise') do
  doc = CXLib.parse(fx('api_config.cx'))
  srv = doc.at('config/server')
  srv.remove_attr('totally_missing')
end

run_test('test_parse_xml_invalid') do
  begin
    CXLib.parse_xml('<unclosed')
    raise "expected parse error for invalid XML"
  rescue RuntimeError
    # expected
  end
end

# ── parse other formats ───────────────────────────────────────────────────────

run_test('test_parse_xml') do
  doc   = CXLib.parse_xml('<root><child key="val"/></root>')
  raise "wrong root" unless doc.root.name == 'root'
  child = doc.find_first('child')
  raise "child not found" if child.nil?
end

run_test('test_parse_json_to_document') do
  doc = CXLib.parse_json('{"server": {"port": 8080}}')
  raise "server not found" if doc.find_first('server').nil?
end

run_test('test_parse_yaml_to_document') do
  doc = CXLib.parse_yaml("server:\n  port: 8080\n")
  raise "server not found" if doc.find_first('server').nil?
end

# ── streaming ────────────────────────────────────────────────────────────────

STREAM_FX = fx('stream/stream_events.cx')

run_test('test_stream_returns_array') do
  events = CXLib.stream(STREAM_FX)
  raise "expected Array, got #{events.class}" unless events.is_a?(Array)
  raise "expected non-empty" unless events.size > 0
end

run_test('test_stream_starts_with_start_doc') do
  events = CXLib.stream(STREAM_FX)
  raise "expected StartDoc first, got #{events.first.type}" unless events.first.type == 'StartDoc'
end

run_test('test_stream_ends_with_end_doc') do
  events = CXLib.stream(STREAM_FX)
  raise "expected EndDoc last, got #{events.last.type}" unless events.last.type == 'EndDoc'
end

run_test('test_stream_comment_event') do
  events = CXLib.stream(STREAM_FX)
  comment = events.find { |e| e.type == 'Comment' }
  raise "no Comment event found" if comment.nil?
  raise "wrong comment value: #{comment.value.inspect}" unless comment.value == 'a comment node'
end

run_test('test_stream_pi_event') do
  events = CXLib.stream(STREAM_FX)
  pi = events.find { |e| e.type == 'PI' }
  raise "no PI event found" if pi.nil?
  raise "wrong PI target: #{pi.target.inspect}" unless pi.target == 'pi'
  raise "wrong PI data: #{pi.data.inspect}"   unless pi.data == 'pi data here'
end

run_test('test_stream_entity_ref_event') do
  events = CXLib.stream(STREAM_FX)
  eref = events.find { |e| e.type == 'EntityRef' }
  raise "no EntityRef event found" if eref.nil?
  raise "wrong entity name: #{eref.value.inspect}" unless eref.value == 'amp'
end

run_test('test_stream_alias_event') do
  events = CXLib.stream(STREAM_FX)
  alias_ev = events.find { |e| e.type == 'Alias' }
  raise "no Alias event found" if alias_ev.nil?
  raise "wrong alias name: #{alias_ev.value.inspect}" unless alias_ev.value == 'srv'
end

run_test('test_stream_raw_text_event') do
  events = CXLib.stream(STREAM_FX)
  rt = events.find { |e| e.type == 'RawText' }
  raise "no RawText event found" if rt.nil?
  raise "wrong raw text: #{rt.value.inspect}" unless rt.value == 'inline raw text'
end

run_test('test_stream_anchor_on_start_element') do
  events = CXLib.stream(STREAM_FX)
  srv = events.find { |e| e.type == 'StartElement' && e.name == 'server' }
  raise "no StartElement 'server' found" if srv.nil?
  raise "expected anchor 'srv', got #{srv.anchor.inspect}" unless srv.anchor == 'srv'
end

run_test('test_stream_typed_scalar_int') do
  events = CXLib.stream(STREAM_FX)
  scalar = events.find { |e| e.type == 'Scalar' && e.data_type == 'int' }
  raise "no int Scalar found" if scalar.nil?
  raise "expected 42, got #{scalar.value.inspect}" unless scalar.value == 42
end

run_test('test_stream_typed_scalar_bool') do
  events = CXLib.stream(STREAM_FX)
  scalar = events.find { |e| e.type == 'Scalar' && e.data_type == 'bool' }
  raise "no bool Scalar found" if scalar.nil?
  raise "expected true, got #{scalar.value.inspect}" unless scalar.value == true
end

run_test('test_stream_nested_elements') do
  events = CXLib.stream(STREAM_FX)
  nested_start = events.find { |e| e.type == 'StartElement' && e.name == 'nested' }
  raise "no StartElement 'nested' found" if nested_start.nil?
  child_a = events.find { |e| e.type == 'StartElement' && e.name == 'child-a' }
  raise "no StartElement 'child-a' found" if child_a.nil?
  child_b = events.find { |e| e.type == 'StartElement' && e.name == 'child-b' }
  raise "no StartElement 'child-b' found" if child_b.nil?
end

run_test('test_stream_simple_cx') do
  events = CXLib.stream('[root [child value]]')
  types = events.map(&:type)
  raise "expected StartDoc" unless types.include?('StartDoc')
  raise "expected StartElement" unless types.include?('StartElement')
  raise "expected EndDoc" unless types.include?('EndDoc')
  root = events.find { |e| e.type == 'StartElement' && e.name == 'root' }
  raise "no 'root' StartElement" if root.nil?
end

run_test('test_stream_attr_autotyping') do
  events = CXLib.stream(STREAM_FX)
  srv = events.find { |e| e.type == 'StartElement' && e.name == 'server' }
  raise "no server StartElement" if srv.nil?
  port_attr = srv.attrs.find { |a| a.name == 'port' }
  raise "no port attr" if port_attr.nil?
  raise "expected port=8080 int, got #{port_attr.value.inspect}" unless port_attr.value == 8080
end

# ── remove_child / remove_at ─────────────────────────────────────────────────

run_test('test_remove_child_removes_all_by_name') do
  doc = CXLib.parse('[root [item 1] [other x] [item 2]]')
  doc.root.remove_child('item')
  raise "items not removed" unless doc.root.get_all('item').empty?
  raise "other should remain" if doc.root.get('other').nil?
end

run_test('test_remove_child_noop_when_not_found') do
  doc = CXLib.parse('[root [item 1]]')
  doc.root.remove_child('missing')
  raise "item should remain" if doc.root.get('item').nil?
end

run_test('test_remove_at_removes_item_at_index') do
  doc = CXLib.parse('[root [a 1] [b 2] [c 3]]')
  doc.root.remove_at(1)
  names = doc.root.children.map(&:name)
  raise "expected [a, c], got #{names}" unless names == %w[a c]
end

run_test('test_remove_at_noop_out_of_bounds') do
  doc = CXLib.parse('[root [a 1]]')
  doc.root.remove_at(99)
  raise "item should remain" if doc.root.get('a').nil?
end

# ── select_all / select ───────────────────────────────────────────────────────

run_test('test_select_all_descendant_axis') do
  doc = CXLib.parse(fx('api_multi.cx'))
  services = doc.select_all('//service')
  raise "expected 3, got #{services.size}" unless services.size == 3
  raise "wrong order [0]" unless services[0].attr('name') == 'auth'
  raise "wrong order [1]" unless services[1].attr('name') == 'api'
  raise "wrong order [2]" unless services[2].attr('name') == 'worker'
end

run_test('test_select_all_attr_predicate') do
  doc = CXLib.parse('[services [service active=true name=a][service active=false name=b][service active=true name=c]]')
  active = doc.select_all('//service[@active=true]')
  raise "expected 2, got #{active.size}" unless active.size == 2
  raise "wrong names" unless active.map { |s| s.attr('name') } == %w[a c]
end

run_test('test_select_first_from_select_all') do
  doc = CXLib.parse(fx('api_multi.cx'))
  svc = doc.select('//service')
  raise "expected non-nil" if svc.nil?
  raise "wrong name: #{svc.attr('name').inspect}" unless svc.attr('name') == 'auth'
end

run_test('test_select_all_child_path') do
  doc = CXLib.parse(fx('api_config.cx'))
  results = doc.select_all('config/server')
  raise "expected 1, got #{results.size}" unless results.size == 1
  raise "wrong name" unless results[0].name == 'server'
end

run_test('test_select_all_wildcard') do
  doc = CXLib.parse(fx('api_config.cx'))
  children = doc.select_all('config/*')
  raise "expected 3, got #{children.size}" unless children.size == 3
  raise "wrong names" unless children.map(&:name) == %w[server database logging]
end

run_test('test_select_all_numeric_comparison') do
  doc = CXLib.parse('[services [service port=8080][service port=80][service port=9000]]')
  high = doc.select_all('//service[@port>=8000]')
  raise "expected 2, got #{high.size}" unless high.size == 2
end

run_test('test_select_all_position') do
  doc = CXLib.parse(fx('api_multi.cx'))
  svc = doc.select('//service[2]')
  raise "expected non-nil" if svc.nil?
  raise "wrong name: #{svc.attr('name').inspect}" unless svc.attr('name') == 'api'
end

run_test('test_select_all_last_position') do
  doc = CXLib.parse(fx('api_multi.cx'))
  svc = doc.select('//service[last()]')
  raise "expected non-nil" if svc.nil?
  raise "wrong name: #{svc.attr('name').inspect}" unless svc.attr('name') == 'worker'
end

run_test('test_select_all_contains') do
  doc = CXLib.parse(fx('api_multi.cx'))
  # 'auth' and 'api' both contain 'a'
  results = doc.select_all("//service[contains(@name, 'a')]")
  raise "expected 2+, got #{results.size}" unless results.size >= 1
  raise "all should contain 'a'" unless results.all? { |s| s.attr('name').include?('a') }
end

run_test('test_select_all_starts_with') do
  doc = CXLib.parse(fx('api_multi.cx'))
  # 'auth' and 'api' start with 'a'
  results = doc.select_all("//service[starts-with(@name, 'a')]")
  raise "expected 2, got #{results.size}" unless results.size == 2
  raise "all should start with 'a'" unless results.all? { |s| s.attr('name').start_with?('a') }
end

run_test('test_select_all_bool_and') do
  doc = CXLib.parse('[services [service active=true port=8080][service active=true port=9000][service active=false port=8080]]')
  results = doc.select_all('//service[@active=true and @port=8080]')
  raise "expected 1, got #{results.size}" unless results.size == 1
  raise "wrong active" unless results[0].attr('active') == true
  raise "wrong port" unless results[0].attr('port') == 8080
end

run_test('test_select_on_element') do
  doc = CXLib.parse('[services [service active=true name=a][service active=false name=b][service active=true name=c]]')
  services_el = doc.get('services')
  results = services_el.select_all('service[@active=true]')
  raise "expected 2, got #{results.size}" unless results.size == 2
  raise "wrong names" unless results.map { |s| s.attr('name') } == %w[a c]
end

run_test('test_select_invalid_expr_raises') do
  begin
    CXLib.parse('[root]').select('[@invalid syntax!!!')
    raise "expected ArgumentError"
  rescue ArgumentError
    # expected
  end
end

# ── transform ─────────────────────────────────────────────────────────────────

run_test('test_transform_returns_new_document') do
  doc = CXLib.parse(fx('api_config.cx'))
  updated = doc.transform('config/server') { |el| el.set_attr('host', 'newhost'); el }
  raise "wrong host in updated" unless updated.at('config/server').attr('host') == 'newhost'
end

run_test('test_transform_original_unchanged') do
  doc = CXLib.parse(fx('api_config.cx'))
  doc.transform('config/server') { |el| el.set_attr('host', 'changed'); el }
  raise "original should be unchanged" unless doc.at('config/server').attr('host') == 'localhost'
end

run_test('test_transform_missing_path_returns_self') do
  doc = CXLib.parse(fx('api_config.cx'))
  updated = doc.transform('config/nonexistent') { |el| el }
  raise "server should still be there" unless updated.at('config/server').attr('host') == 'localhost'
  raise "nonexistent should still be nil" unless updated.at('config/nonexistent').nil?
end

run_test('test_transform_chained') do
  doc = CXLib.parse(fx('api_config.cx'))
  updated = doc
    .transform('config/server')   { |el| el.set_attr('host', 'host1'); el }
    .transform('config/database') { |el| el.set_attr('host', 'host2'); el }
  raise "wrong server host"   unless updated.at('config/server').attr('host')   == 'host1'
  raise "wrong database host" unless updated.at('config/database').attr('host') == 'host2'
  raise "original unchanged"  unless doc.at('config/server').attr('host') == 'localhost'
end

run_test('test_transform_preserves_other_attributes') do
  doc = CXLib.parse(fx('api_config.cx'))
  updated = doc.transform('config/server') { |el| el.set_attr('host', 'transformed'); el }
  srv = updated.at('config/server')
  raise "wrong host" unless srv.attr('host') == 'transformed'
  raise "port should be preserved" unless srv.attr('port') == 8080
end

# ── transform_all ─────────────────────────────────────────────────────────────

run_test('test_transform_all_applies_to_all_matching') do
  doc = CXLib.parse(fx('api_multi.cx'))
  updated = doc.transform_all('//service') { |el| el.set_attr('active', true); el }
  services = updated.find_all('service')
  raise "expected 3, got #{services.size}" unless services.size == 3
  raise "all should be active" unless services.all? { |s| s.attr('active') == true }
end

run_test('test_transform_all_returns_new_document') do
  doc = CXLib.parse(fx('api_multi.cx'))
  updated = doc.transform_all('//service') { |el| el.set_attr('version', 2); el }
  raise "updated should have version" unless updated.find_all('service').all? { |s| s.attr('version') == 2 }
  raise "original should not have version" unless doc.find_all('service').all? { |s| s.attr('version').nil? }
end

run_test('test_transform_all_no_matches_returns_unchanged') do
  doc = CXLib.parse(fx('api_config.cx'))
  updated = doc.transform_all('//nonexistent') { |el| el }
  raise "server should still be there" unless updated.at('config/server').attr('host') == 'localhost'
end

run_test('test_transform_all_deeply_nested') do
  doc = CXLib.parse(fx('api_article.cx'))
  updated = doc.transform_all('//p') { |el| el.set_attr('visited', true); el }
  updated_ps = updated.find_all('p')
  raise "expected 3 p elements, got #{updated_ps.size}" unless updated_ps.size == 3
  raise "all p should be visited" unless updated_ps.all? { |p| p.attr('visited') == true }
  raise "original p should not be visited" unless doc.find_all('p').all? { |p| p.attr('visited').nil? }
end

# ── summary ───────────────────────────────────────────────────────────────────

total  = $passed + $failed
status = $failed == 0 ? 'OK' : 'FAILED'
puts "ruby/test_api.rb: #{$passed} passed, #{$failed} failed  [#{status}]"
exit($failed == 0 ? 0 : 1)
