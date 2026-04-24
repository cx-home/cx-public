#!/usr/bin/env ruby
# frozen_string_literal: true
#
# CX Ruby demo — Document Model, Streaming, CXPath, and Transform APIs.
#
# Run from repo root:
#   ruby lang/ruby/cxlib/examples/demo.rb
#
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'cxlib'

CX_INPUT = <<~CX
  [config version='1.0' debug=false
    [server host=localhost port=8080]
    [database url='postgres://localhost/mydb' pool=10]
    [cache enabled=true ttl=300]
  ]
CX

puts "=== Document Model ===\n\n"

doc = CXLib.parse(CX_INPUT)

server = doc.at('config/server')
puts "host: #{server.attr('host')}"
puts "port: #{server.attr('port')}"

server.set_attr('host', 'prod.example.com')
server.append(CXLib::Element.new('timeout', items: [CXLib::ScalarNode.new('int', 30)]))

config = doc.root
cache = config.get('cache')
config.remove(cache)

puts "\n--- Modified document ---"
puts doc.to_cx

puts "\n=== Streaming ===\n\n"
CXLib.stream(CX_INPUT).each do |ev|
  if ev.start_element?
    attrs_str = ev.attrs.map { |a| "#{a.name}=#{a.value}" }.join('  ')
    puts "#{ev.name}  #{attrs_str}"
  end
end

SERVICES = <<~CX
  [services
    [service name=auth  port=8080 active=true]
    [service name=api   port=9000 active=false]
    [service name=web   port=80   active=true]
  ]
CX

puts "\n=== CXPath Select ===\n\n"
sdoc = CXLib.parse(SERVICES)
first = sdoc.select('//service')
puts "first service: #{first.attr('name')}"
sdoc.select_all('//service[@active=true]').each { |svc| puts "active: #{svc.attr('name')}" }

puts "\n=== Transform ===\n\n"
updated = sdoc.transform('services/service') { |el| el.set_attr('name', 'renamed-auth'); el }
puts updated.to_cx

all_active = sdoc.transform_all('//service') { |el| el.set_attr('active', true); el }
count = all_active.select_all('//service[@active=true]').length
puts "Active services after transform_all: #{count}"
