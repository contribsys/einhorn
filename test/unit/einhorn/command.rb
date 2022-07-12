require File.expand_path(File.join(File.dirname(__FILE__), "../../_lib"))

require "einhorn"

class CommandTest < EinhornTestCase
  include Einhorn

  describe "when running quieter" do
    it "increases the verbosity threshold" do
      Einhorn::State.stubs(verbosity: 1)
      Einhorn::State.expects(:verbosity=).once.with(2).returns(2)
      Command.quieter
    end

    it "maxes out at 2" do
      Einhorn::State.stubs(verbosity: 2)
      Einhorn::State.expects(:verbosity=).never
      Command.quieter
    end
  end

  describe "resignal_timeout" do
    it "does not kill any children" do
      Einhorn::State.stubs(signal_timeout: 5 * 60)
      Einhorn::State.stubs(children: {
        12345 => {last_signaled_at: nil},
        12346 => {signaled: Set.new(["USR1"]), last_signaled_at: Time.now - (2 * 60)}
      })

      Process.expects(:kill).never
      Einhorn::Command.kill_expired_signaled_workers

      refute(Einhorn::State.children[12346][:signaled].include?("KILL"), "Process was KILLed when it shouldn't have been")
    end

    it "KILLs stuck child processes" do
      Time.stub :now, Time.at(0) do
        Process.stub(:kill, true) do
          Einhorn::State.stubs(signal_timeout: 60)
          Einhorn::State.stubs(children: {
            12346 => {signaled: Set.new(["USR2"]), last_signaled_at: Time.now - (2 * 60)}
          })

          Einhorn::Command.kill_expired_signaled_workers

          child = Einhorn::State.children[12346]
          assert(child[:signaled].include?("KILL"), "Process was not KILLed as expected")
          assert(child[:last_signaled_at] == Time.now, "The last_processed_at was not updated as expected")
        end
      end
    end
  end

  describe "trigger_spinup?" do
    it "is true by default" do
      assert(Einhorn::Command.trigger_spinup?(1))
    end

    it "is false if unacked >= max_unacked" do
      Einhorn::State.stubs(children: {12346 => {type: :worker, acked: false, signaled: Set.new}})
      assert(Einhorn::Command.trigger_spinup?(1))
    end

    it "is false if capacity is exceeded" do
      Einhorn::State.stubs(config: {max_upgrade_additional: 1, number: 1})
      Einhorn::State.stubs(
        children: {
          1 => {type: :worker, acked: true, signaled: Set.new},
          2 => {type: :worker, acked: true, signaled: Set.new},
          3 => {type: :worker, acked: true, signaled: Set.new}
        }
      )
      refute(Einhorn::Command.trigger_spinup?(1))
    end

    it "is true if under capacity" do
      Einhorn::State.stubs(config: {max_upgrade_additional: 2, number: 1})
      Einhorn::State.stubs(children: {1 => {type: :worker, acked: true, signaled: Set.new}})
      assert(Einhorn::Command.trigger_spinup?(1))
    end
  end

  describe "replenish_gradually" do
    it "does nothing if an outstanding spinup timer exists" do
      Einhorn::TransientState.stubs(has_outstanding_spinup_timer: true)
      Einhorn::Command.expects(:spinup).never
      Einhorn::Command.replenish_gradually
    end
    it "does nothing if the worker pool is full" do
      Einhorn::TransientState.stubs(has_outstanding_spinup_timer: false)
      Einhorn::WorkerPool.stubs(missing_worker_count: 0)
      Einhorn::Command.expects(:spinup).never
      Einhorn::Command.replenish_gradually
    end

    it "does nothing if we have not reached the spinup interval" do
      Einhorn::TransientState.stubs(has_outstanding_spinup_timer: false)
      Einhorn::WorkerPool.stubs(missing_worker_count: 1)
      Einhorn::State.stubs(last_spinup: Time.now)
      Einhorn::Command.expects(:spinup).never
      Einhorn::Command.replenish_gradually
    end

    it "calls trigger_spinup? if we have reached the spinup interval" do
      Einhorn::TransientState.stubs(has_outstanding_spinup_timer: false)
      Einhorn::State.stubs(config: {seconds: 1, max_unacked: 2, number: 1})
      Einhorn::WorkerPool.stubs(missing_worker_count: 1)
      Einhorn::State.stubs(last_spinup: Time.now - 2) # 2 seconds ago
      Einhorn::Command.expects(:trigger_spinup?).with(2).returns(false)
      Einhorn::Command.replenish_gradually
    end

    it "can handle sub-second spinup intervals" do
      Einhorn::TransientState.stubs(has_outstanding_spinup_timer: false)
      Einhorn::State.stubs(config: {seconds: 0.1, max_unacked: 2, number: 1})
      Einhorn::WorkerPool.stubs(missing_worker_count: 1)
      Einhorn::State.stubs(last_spinup: Time.now - 0.5) # Half a second ago
      Einhorn::Command.stubs(trigger_spinup?: true)
      Einhorn::Command.expects(:spinup)
      Einhorn::Command.replenish_gradually
    end

    it "registers a timer to run again at spinup interval" do
      Einhorn::TransientState.stubs(has_outstanding_spinup_timer: false)
      Einhorn::State.stubs(config: {seconds: 0.1, max_unacked: 2, number: 1})
      Einhorn::WorkerPool.stubs(missing_worker_count: 1)
      Einhorn::State.stubs(last_spinup: Time.now - 1)
      Einhorn::Command.stubs(trigger_spinup?: true)
      Einhorn::Command.stubs(:spinup)
      Einhorn::TransientState.expects(:has_outstanding_spinup_timer=).with(true)
      Einhorn::Event::Timer.expects(:open).with(0.1)
      Einhorn::Command.replenish_gradually
    end
  end
end
