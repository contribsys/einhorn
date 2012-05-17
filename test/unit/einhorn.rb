require File.expand_path(File.join(File.dirname(__FILE__), '../test_helper'))

require 'einhorn'

class EinhornTest < Test::Unit::TestCase
  context "when sockifying" do
    teardown do
      Einhorn::State.sockets = {}
    end

    should "correctly parse srv: arguments" do
      cmd = ['foo', 'srv:1.2.3.4:123,llama,test', 'bar']
      Einhorn.expects(:bind).once.with('1.2.3.4', '123', ['llama', 'test']).returns(4)

      Einhorn.socketify!(cmd)

      assert_equal(['foo', '4', 'bar'], cmd)
    end

    should "correctly parse --opt=srv: arguments" do
      cmd = ['foo', '--opt=srv:1.2.3.4:456', 'baz']
      Einhorn.expects(:bind).once.with('1.2.3.4', '456', []).returns(5)

      Einhorn.socketify!(cmd)

      assert_equal(['foo', '--opt=5', 'baz'], cmd)
    end

    should "use the same fd number for the same server spec" do
      cmd = ['foo', '--opt=srv:1.2.3.4:8910', 'srv:1.2.3.4:8910']
      Einhorn.expects(:bind).once.with('1.2.3.4', '8910', []).returns(10)

      Einhorn.socketify!(cmd)

      assert_equal(['foo', '--opt=10', '10'], cmd)
    end
  end
end
