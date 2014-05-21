# -*- encoding: utf-8 -*-
require File.expand_path('../lib/einhorn/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ['Greg Brockman']
  gem.email         = ['gdb@stripe.com']
  gem.summary       = 'Einhorn: the language-independent shared socket manager'
  gem.description   = 'Einhorn makes it easy to run multiple instances of an application server, all listening on the same port. You can also seamlessly restart your workers without dropping any requests. Einhorn requires minimal application-level support, making it easy to use with an existing project.'
  gem.homepage      = 'https://github.com/stripe/einhorn'
  gem.license       = 'MIT'

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = 'einhorn'
  gem.require_paths = ['lib']

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'minitest', '< 5.0'
  gem.add_development_dependency 'mocha', '~> 0.13'
  gem.add_development_dependency 'chalk-rake'
  gem.add_development_dependency 'subprocess'

  gem.version       = Einhorn::VERSION
end
