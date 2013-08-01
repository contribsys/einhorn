require File.expand_path(File.join(File.dirname(__FILE__), '../_lib'))

require 'einhorn'

class EinhornTest < EinhornTestCase
  describe "when sockifying" do
    after do
      Einhorn::State.sockets = {}
    end

    it "correctly parses srv: arguments" do
      cmd = ['foo', 'srv:1.2.3.4:123,llama,test', 'bar']
      Einhorn.expects(:bind).once.with('1.2.3.4', '123', ['llama', 'test']).returns(4)

      Einhorn.socketify!(cmd)

      assert_equal(['foo', '4', 'bar'], cmd)
    end

    it "correctly parses --opt=srv: arguments" do
      cmd = ['foo', '--opt=srv:1.2.3.4:456', 'baz']
      Einhorn.expects(:bind).once.with('1.2.3.4', '456', []).returns(5)

      Einhorn.socketify!(cmd)

      assert_equal(['foo', '--opt=5', 'baz'], cmd)
    end

    it "uses the same fd number for the same server spec" do
      cmd = ['foo', '--opt=srv:1.2.3.4:8910', 'srv:1.2.3.4:8910']
      Einhorn.expects(:bind).once.with('1.2.3.4', '8910', []).returns(10)

      Einhorn.socketify!(cmd)

      assert_equal(['foo', '--opt=10', '10'], cmd)
    end
  end

  describe '.update_state' do
    it 'correctly updates keys to match new default state hash' do
      Einhorn::State.stubs(:default_state).returns(:baz => 23, :foo => 1)
      old_state = {:foo => 2, :bar => 2}

      updated_state, message = Einhorn.update_state(Einhorn::State, 'einhorn', old_state)
      assert_equal({:baz => 23, :foo => 2}, updated_state)
      assert_match(/State format for einhorn has changed/, message)
    end

    it 'does not change the state if the format has not changed' do
      Einhorn::State.stubs(:default_state).returns(:baz => 23, :foo => 1)
      old_state = {:baz => 14, :foo => 1234}

      updated_state, message = Einhorn.update_state(Einhorn::State, 'einhorn', old_state)
      assert_equal({:baz => 14, :foo => 1234}, updated_state)
      assert(message.nil?)
    end
  end
end
