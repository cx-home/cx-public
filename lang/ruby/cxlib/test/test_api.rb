# frozen_string_literal: true
#
# Document API tests for ruby/cxlib — includes binary decoder and stream tests.
# Fixtures are shared with all language bindings — see fixtures/ at the repo root.
# Run from ruby/cxlib/:  ruby test/test_api.rb
#
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cxlib'
require 'json'

FIXTURES = File.expand_path('../../../../fixtures', __dir__)

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

# ── stream / binary events decoder ────────────────────────────────────────────

run_test('test_stream_returns_array_of_events') do
  events = CXLib.stream('[config host=localhost]')
  raise "expected Array" unless events.is_a?(Array)
  raise "expected at least one event" unless events.size >= 1
end

run_test('test_stream_starts_with_start_doc_and_end_doc') do
  events = CXLib.stream('[config host=localhost]')
  raise "first event should be StartDoc, got #{events.first.type}" unless events.first.type == 'StartDoc'
  raise "last event should be EndDoc, got #{events.last.type}" unless events.last.type == 'EndDoc'
end

run_test('test_stream_start_element_has_name') do
  events = CXLib.stream('[config host=localhost port=8080]')
  start  = events.find { |e| e.type == 'StartElement' }
  raise "no StartElement found" if start.nil?
  raise "wrong name: #{start.name.inspect}" unless start.name == 'config'
end

run_test('test_stream_start_element_has_typed_attrs') do
  events = CXLib.stream('[server host=localhost port=8080 debug=false]')
  start  = events.find { |e| e.start_element?('server') }
  raise "no StartElement(server) found" if start.nil?
  host_attr  = start.attrs.find { |a| a.name == 'host' }
  port_attr  = start.attrs.find { |a| a.name == 'port' }
  debug_attr = start.attrs.find { |a| a.name == 'debug' }
  raise "host missing"              if host_attr.nil?
  raise "wrong host: #{host_attr.value.inspect}" unless host_attr.value == 'localhost'
  raise "port missing"              if port_attr.nil?
  raise "wrong port type"           unless port_attr.value.is_a?(Integer)
  raise "wrong port: #{port_attr.value}" unless port_attr.value == 8080
  raise "debug missing"             if debug_attr.nil?
  raise "wrong debug: #{debug_attr.value.inspect}" unless debug_attr.value == false
end

run_test('test_stream_end_element_has_name') do
  events = CXLib.stream('[config host=localhost]')
  stop   = events.find { |e| e.type == 'EndElement' }
  raise "no EndElement found" if stop.nil?
  raise "wrong name: #{stop.name.inspect}" unless stop.name == 'config'
end

run_test('test_stream_text_event') do
  events = CXLib.stream('[greeting Hello World]')
  text_e = events.find { |e| e.type == 'Text' }
  raise "no Text event found" if text_e.nil?
  raise "wrong value: #{text_e.value.inspect}" unless text_e.value == 'Hello World'
end

run_test('test_stream_scalar_event_typed') do
  events = CXLib.stream('[count :int 42]')
  scalar = events.find { |e| e.type == 'Scalar' }
  raise "no Scalar event found" if scalar.nil?
  raise "wrong value: #{scalar.value.inspect}" unless scalar.value == 42
  raise "expected Integer" unless scalar.value.is_a?(Integer)
  raise "wrong data_type: #{scalar.data_type.inspect}" unless scalar.data_type == 'int'
end

run_test('test_stream_nested_elements') do
  events = CXLib.stream(fx('stream/stream_nested.cx'))
  starts = events.select { |e| e.type == 'StartElement' }
  ends   = events.select { |e| e.type == 'EndElement' }
  raise "expected paired start/end" unless starts.size == ends.size
  raise "expected level1 root" unless starts.first.name == 'level1'
end

run_test('test_stream_events_fixture') do
  events = CXLib.stream(fx('stream/stream_events.cx'))
  start_names = events.select { |e| e.type == 'StartElement' }.map(&:name)
  raise "doc element not found" unless start_names.include?('doc')
  raise "server element not found" unless start_names.include?('server')
  server = events.find { |e| e.start_element?('server') }
  raise "server not found" if server.nil?
  host = server.attrs.find { |a| a.name == 'host' }
  raise "host attr missing" if host.nil?
  raise "wrong host: #{host.value.inspect}" unless host.value == 'localhost'
end

run_test('test_stream_helper_methods') do
  events = CXLib.stream('[root [child x]]')
  root_e = events.find { |e| e.start_element?('root') }
  raise "start_element? failed" if root_e.nil?
  raise "start_element?('root') should be true"  unless root_e.start_element?('root')
  raise "start_element?('other') should be false" if root_e.start_element?('other')
  end_root = events.find { |e| e.end_element?('root') }
  raise "end_element? failed" if end_root.nil?
  raise "end_element?('root') should be true" unless end_root.end_element?('root')
end

# ── summary ───────────────────────────────────────────────────────────────────

total  = $passed + $failed
status = $failed == 0 ? 'OK' : 'FAILED'
puts "ruby/cxlib/test/test_api.rb: #{$passed} passed, #{$failed} failed  [#{status}]"
exit($failed == 0 ? 0 : 1)
