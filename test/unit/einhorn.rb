require File.expand_path(File.join(File.dirname(__FILE__), "../_lib"))

require "einhorn"

class EinhornTest < EinhornTestCase
  describe "when sockifying" do
    after do
      Einhorn::State.sockets = {}
    end

    it "correctly parses srv: arguments" do
      cmd = ["foo", "srv:1.2.3.4:123,llama,test", "bar"]
      Einhorn.expects(:bind).once.with("1.2.3.4", "123", ["llama", "test"]).returns([4, 10087])

      Einhorn.socketify!(cmd)

      assert_equal(["foo", "4", "bar"], cmd)
    end

    it "correctly parses --opt=srv: arguments" do
      cmd = ["foo", "--opt=srv:1.2.3.4:456", "baz"]
      Einhorn.expects(:bind).once.with("1.2.3.4", "456", []).returns([5, 10088])

      Einhorn.socketify!(cmd)

      assert_equal(["foo", "--opt=5", "baz"], cmd)
    end

    it "uses the same fd number for the same server spec" do
      cmd = ["foo", "--opt=srv:1.2.3.4:8910", "srv:1.2.3.4:8910"]
      Einhorn.expects(:bind).once.with("1.2.3.4", "8910", []).returns([10, 10089])

      Einhorn.socketify!(cmd)

      assert_equal(["foo", "--opt=10", "10"], cmd)
    end
  end

  describe ".update_state" do
    it "correctly updates keys to match new default state hash" do
      Einhorn::State.stubs(:default_state).returns(baz: 23, foo: 1)
      old_state = {foo: 2, bar: 2}

      updated_state, message = Einhorn.update_state(Einhorn::State, "einhorn", old_state)
      assert_equal({baz: 23, foo: 2}, updated_state)
      assert_match(/State format for einhorn has changed/, message)
    end

    it "does not change the state if the format has not changed" do
      Einhorn::State.stubs(:default_state).returns(baz: 23, foo: 1)
      old_state = {baz: 14, foo: 1234}

      updated_state, message = Einhorn.update_state(Einhorn::State, "einhorn", old_state)
      assert_equal({baz: 14, foo: 1234}, updated_state)
      assert(message.nil?)
    end
  end

  describe ".preload" do
    before do
      Einhorn::State.preloaded = false
    end

    it "updates preload on success" do
      Einhorn.stubs(:set_argv).returns
      # preloads the sleep worker since it has einhorn main
      Einhorn::State.path = "#{__dir__}/_lib/sleep_worker.rb"
      assert_equal(false, Einhorn::State.preloaded)
      Einhorn.preload
      assert_equal(true, Einhorn::State.preloaded)
      # Attempt another preload
      Einhorn.preload
      assert_equal(true, Einhorn::State.preloaded)
    end

    it "updates preload to failed with previous success" do
      Einhorn.stubs(:set_argv).returns
      Einhorn::State.path = "#{__dir__}/_lib/sleep_worker.rb"
      assert_equal(false, Einhorn::State.preloaded)
      Einhorn.preload
      assert_equal(true, Einhorn::State.preloaded)
      # Change path to bad worker and preload again, should be false
      Einhorn::State.path = "#{__dir__}/_lib/bad_worker.rb"
      Einhorn.preload
      assert_equal(false, Einhorn::State.preloaded)
    end

    it "preload is false after failing" do
      Einhorn.stubs(:set_argv).returns
      Einhorn::State.path = "#{__dir__}/bad_worker.rb"
      assert_equal(false, Einhorn::State.preloaded)
      Einhorn.preload
      assert_equal(false, Einhorn::State.preloaded)
    end
  end
end
