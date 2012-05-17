require File.expand_path(File.join(File.dirname(__FILE__), '../../test_helper'))

require 'einhorn'

class CommandTest < Test::Unit::TestCase
  include Einhorn

  context "when running quieter" do
    should "increase the verbosity threshold" do
      Einhorn::State.stubs(:verbosity => 1)
      Einhorn::State.expects(:verbosity=).once.with(2).returns(2)
      Command.quieter
    end

    should "max out at 2" do
      Einhorn::State.stubs(:verbosity => 2)
      Einhorn::State.expects(:verbosity=).never
      Command.quieter
    end
  end
end
