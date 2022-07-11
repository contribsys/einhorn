# -*- encoding: utf-8 -*-
require File.expand_path('../lib/einhorn/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ['Stripe', 'Mike Perham']
  gem.email         = ['support+github@stripe.com', 'mperham@gmail.com']
  gem.summary       = 'Einhorn: the language-independent shared socket manager'
  gem.description   = 'Einhorn makes it easy to run multiple instances of an application server, all listening on the same port. You can also seamlessly restart your workers without dropping any requests. Einhorn requires minimal application-level support, making it easy to use with an existing project.'
  gem.homepage      = 'https://github.com/contribsys/einhorn'
  gem.license       = 'MIT'

  gem.files         = ["einhorn.gemspec", "README.md", "Changes.md", "LICENSE.txt"] + `git ls-files bin lib example`.split("\n")
  gem.executables   = %w[einhorn einhornsh]
  gem.test_files    = []
  gem.name          = 'einhorn'
  gem.require_paths = ['lib']

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'minitest'
  gem.add_development_dependency 'mocha'
  gem.add_development_dependency 'subprocess'

  gem.version       = Einhorn::VERSION
end
