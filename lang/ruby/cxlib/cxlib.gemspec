Gem::Specification.new do |s|
  s.name        = 'cxlib'
  s.version     = '0.5.0'
  s.summary     = 'CX format library'
  s.description = 'Parse, stream, and convert CX/XML/JSON/YAML/TOML/Markdown via libcx'
  s.license     = 'MIT'
  s.files       = Dir['lib/**/*']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 3.1'
  s.add_runtime_dependency 'ffi', '~> 1.15'
end
