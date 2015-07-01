lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include? lib
require 'unravel/version'

Gem::Specification.new do |spec|
  spec.name = 'unravel'
  spec.version = Unravel::VERSION
  spec.summary = "Solves complex non-deterministic problems given symptoms, causes and fixes"
  spec.description = 'Tool for solving non-deterministic problems given goals, symptoms, fixes and root causes'
  spec.authors = 'Cezary Baginski <cezary@chronomantic.net>'
  spec.files = ['README.md', 'lib/unravel.rb', 'lib/unravel/exec.rb', 'lib/unravel/version.rb']
  spec.licenses = ['mit']
  spec.email = 'cezary@chronomantic.net'
  spec.homepage = 'https://github.com/e2/unravel'
end
