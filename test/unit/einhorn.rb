require File.expand_path(File.join(File.dirname(__FILE__), "../_lib"))

require "einhorn"

class EinhornTest < EinhornTestCase
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
      quiet do
        Einhorn.preload
      end
      assert_equal(true, Einhorn::State.preloaded)
      # Attempt another preload
      quiet do
        Einhorn.preload
      end
      assert_equal(true, Einhorn::State.preloaded)
    end

    it "updates preload to failed with previous success" do
      Einhorn.stubs(:set_argv).returns
      Einhorn::State.path = "#{__dir__}/_lib/sleep_worker.rb"
      assert_equal(false, Einhorn::State.preloaded)
      quiet do
        Einhorn.preload
      end
      assert_equal(true, Einhorn::State.preloaded)
      # Change path to bad worker and preload again, should be false
      Einhorn::State.path = "#{__dir__}/_lib/bad_worker.rb"
      quiet do
        Einhorn.preload
      end
      assert_equal(false, Einhorn::State.preloaded)
    end

    it "preload is false after failing" do
      Einhorn.stubs(:set_argv).returns
      Einhorn::State.path = "#{__dir__}/bad_worker.rb"
      assert_equal(false, Einhorn::State.preloaded)
      quiet do
        Einhorn.preload
      end
      assert_equal(false, Einhorn::State.preloaded)
    end
  end
end
