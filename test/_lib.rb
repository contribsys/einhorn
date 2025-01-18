require "rubygems"
require "bundler/setup"

require "minitest/autorun"
require "minitest/spec"
require "mocha/minitest"

class EinhornTestCase < ::Minitest::Spec
  def setup
    # Put global stubs here
  end
end

def quiet(lvl = 2)
  old = Einhorn::State.verbosity
  Einhorn::State.verbosity = lvl
  yield
ensure
  Einhorn::State.verbosity = old
end
