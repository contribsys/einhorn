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

  context '.update_state' do
    should 'correctly update keys to match new default state hash' do
      Einhorn::State.stubs(:default_state).returns(:baz => 23, :foo => 1)
      old_state = {:foo => 2, :bar => 2}

      updated_state, message = Einhorn.update_state(old_state)
      assert_equal({:baz => 23, :foo => 2}, updated_state)
      assert_match(/State format has changed/, message)
    end

    should 'not change the state if the format has not changed' do
      Einhorn::State.stubs(:default_state).returns(:baz => 23, :foo => 1)
      old_state = {:baz => 14, :foo => 1234}

      updated_state, message = Einhorn.update_state(old_state)
      assert_equal({:baz => 14, :foo => 1234}, updated_state)
      assert(message.nil?)
    end
  end
end
