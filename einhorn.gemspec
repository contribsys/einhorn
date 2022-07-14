require File.expand_path("../lib/einhorn/version", __FILE__)

Gem::Specification.new do |gem|
  gem.authors = ["Stripe", "Mike Perham"]
  gem.email = ["support+github@stripe.com", "mperham@gmail.com"]
  gem.summary = "Einhorn: the language-independent shared socket manager"
  gem.description = "Einhorn makes it easy to run multiple instances of an application server, all listening on the same port. You can also seamlessly restart your workers without dropping any requests. Einhorn requires minimal application-level support, making it easy to use with an existing project."
  gem.homepage = "https://github.com/contribsys/einhorn"
  gem.license = "MIT"

  gem.files = ["einhorn.gemspec", "README.md", "Changes.md", "LICENSE.txt"] + `git ls-files bin lib example`.split("\n")
  gem.executables = %w[einhorn einhornsh]
  gem.test_files = []
  gem.name = "einhorn"
  gem.require_paths = ["lib"]
  gem.required_ruby_version = ">= 2.5.0"
  gem.version = Einhorn::VERSION

  gem.metadata = {
    "bug_tracker_uri" => "https://github.com/contribsys/einhorn/issues",
    "documentation_uri" => "https://github.com/contribsys/einhorn/wiki",
    "changelog_uri" => "https://github.com/contribsys/einhorn/blob/main/Changes.md"
  }

  gem.add_development_dependency "rake", "~> 13"
  gem.add_development_dependency "minitest", "~> 5"
  gem.add_development_dependency "mocha", "~> 1"
  gem.add_development_dependency "subprocess", "~> 1"
end
