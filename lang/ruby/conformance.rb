#!/usr/bin/env ruby
# frozen_string_literal: true
#
# CX Ruby conformance runner.
# Run: /opt/homebrew/opt/ruby/bin/ruby lang/ruby/conformance.rb
#
$LOAD_PATH.unshift File.expand_path('../cxlib/lib', __FILE__)
require 'cxlib'
require 'json'

# ── suite parser ──────────────────────────────────────────────────────────────

def parse_suite(path)
  tests   = []
  cur     = nil
  section = nil
  buf     = []

  flush = lambda do
    if cur && section
      lines = buf.dup
      lines.shift while lines.first && lines.first.strip.empty?
      lines.pop   while lines.last  && lines.last.strip.empty?
      cur[:sections][section] = lines.join("\n")
    end
    buf.clear
  end

  File.foreach(path) do |raw|
    raw = raw.chomp
    if raw.start_with?('=== test:')
      flush.call
      tests << cur if cur
      cur     = { name: raw[9..].strip, sections: {} }
      section = nil
    elsif raw.start_with?('level:') && cur
      cur[:level] = raw[6..].strip
    elsif raw.start_with?('tags:') && cur
      cur[:tags] = raw[5..].strip.split
    elsif raw.start_with?('--- ') && cur
      flush.call
      section = raw[4..].strip
    elsif section && cur
      buf << raw
    end
  end

  flush.call
  tests << cur if cur
  tests
end

# ── test runner ───────────────────────────────────────────────────────────────

def run_test(t)
  failures = []
  s = t[:sections]

  if    s.key?('in_cx')   then src, fmt = s['in_cx'],   'cx'
  elsif s.key?('in_xml')  then src, fmt = s['in_xml'],  'xml'
  elsif s.key?('in_json') then src, fmt = s['in_json'], 'json'
  elsif s.key?('in_yaml') then src, fmt = s['in_yaml'], 'yaml'
  elsif s.key?('in_toml') then src, fmt = s['in_toml'], 'toml'
  elsif s.key?('in_md')   then src, fmt = s['in_md'],   'md'
  else  return failures
  end

  emit = case fmt
  when 'xml'  then ->(out) { "xml_to_#{out}"   }
  when 'json' then ->(out) { "json_to_#{out}"  }
  when 'yaml' then ->(out) { "yaml_to_#{out}"  }
  when 'toml' then ->(out) { "toml_to_#{out}"  }
  when 'md'   then ->(out) { "md_to_#{out}"    }
  else             ->(out) { "to_#{out}"        }
  end

  call = lambda do |out_fmt|
    begin
      [CXLib.send(emit.call(out_fmt), src), nil]
    rescue RuntimeError => e
      [nil, e.message]
    end
  end

  # out_ast
  if s.key?('out_ast')
    out, err = call.call('ast')
    if err
      failures << "out_ast parse error: #{err}"
    else
      expected = JSON.parse(s['out_ast'])
      got      = JSON.parse(out)
      unless expected == got
        failures << "out_ast mismatch\n  expected: #{JSON.generate(expected)}\n  got:      #{JSON.generate(got)}"
      end
    end
  end

  # out_xml
  if s.key?('out_xml')
    out, err = call.call('xml')
    if err
      failures << "out_xml parse error: #{err}"
    elsif s['out_xml'].strip != out.strip
      failures << "out_xml mismatch\n  expected:\n#{s['out_xml']}\n  got:\n#{out}"
    end
  end

  # out_cx
  if s.key?('out_cx')
    out, err = call.call('cx')
    if err
      failures << "out_cx parse error: #{err}"
    elsif s['out_cx'].strip != out.strip
      failures << "out_cx mismatch\n  expected:\n#{s['out_cx']}\n  got:\n#{out}"
    end
  end

  # out_json
  if s.key?('out_json')
    out, err = call.call('json')
    if err
      failures << "out_json parse error: #{err}"
    else
      expected = JSON.parse(s['out_json'])
      got      = JSON.parse(out)
      unless expected == got
        failures << "out_json mismatch\n  expected: #{JSON.generate(expected)}\n  got:      #{JSON.generate(got)}"
      end
    end
  end

  # out_md
  if s.key?('out_md')
    out, err = call.call('md')
    if err
      failures << "out_md parse error: #{err}"
    elsif s['out_md'].strip != out.strip
      failures << "out_md mismatch\n  expected:\n#{s['out_md']}\n  got:\n#{out}"
    end
  end

  failures
end

# ── suite runner ──────────────────────────────────────────────────────────────

def run_suite(path)
  tests  = parse_suite(path)
  passed = 0
  failed = 0
  tests.each do |t|
    begin
      failures = run_test(t)
    rescue => e
      failures = ["runner exception: #{e}"]
    end
    if failures.empty?
      passed += 1
    else
      failed += 1
      puts "FAIL  #{t[:name]}"
      failures.each { |f| f.each_line { |l| puts "      #{l.chomp}" } }
    end
  end
  puts "#{path}: #{passed} passed, #{failed} failed"
  failed
end

# ── entry point ───────────────────────────────────────────────────────────────

base = File.expand_path('../../../conformance', __FILE__)
suites = ARGV.empty? ? [
  File.join(base, 'core.txt'),
  File.join(base, 'extended.txt'),
  File.join(base, 'xml.txt'),
  File.join(base, 'md.txt'),
] : ARGV

total_failed = suites.sum { |s| run_suite(s) }
exit(total_failed > 0 ? 1 : 0)
