require File.expand_path(File.join(File.dirname(__FILE__), '../../_lib'))

require 'einhorn'

class CommandTest < EinhornTestCase
  include Einhorn

  describe "when running quieter" do
    it "increases the verbosity threshold" do
      Einhorn::State.stubs(:verbosity => 1)
      Einhorn::State.expects(:verbosity=).once.with(2).returns(2)
      Command.quieter
    end

    it "maxes out at 2" do
      Einhorn::State.stubs(:verbosity => 2)
      Einhorn::State.expects(:verbosity=).never
      Command.quieter
    end
  end
end
