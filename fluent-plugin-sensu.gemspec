# coding: utf-8
# vim: et sw=2 sts=2

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-sensu"
  spec.version       = '1.0.1'
  spec.authors       = ["MIYAKAWA Taku"]
  spec.email         = ["miyakawa.taku@gmail.com"]
  spec.description   = 'Fluentd output plugin to send checks' +
                       ' to sensu-client.'
  spec.summary       = spec.description
  spec.homepage      = "https://github.com/miyakawataku/fluent-plugin-sensu"
  spec.license       = "Apache License, v2.0"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rr"
  spec.add_runtime_dependency "fluentd"
end
