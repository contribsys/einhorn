require File.expand_path(File.join(File.dirname(__FILE__), '../../test_helper'))

require 'einhorn'

class WorkerPoolTest < Test::Unit::TestCase
  def stub_children
    Einhorn::State.stubs(:children).returns(
      1234 => {:type => :worker, :signaled => Set.new(['INT'])},
      1235 => {:type => :state_passer},
      1236 => {:type => :worker, :signaled => Set.new}
      )
  end

  context "#workers_with_state" do
    setup do
      stub_children
    end

    should "select only the workers" do
      workers_with_state = Einhorn::WorkerPool.workers_with_state
      # Sort only needed for Ruby 1.8
      assert_equal([
          [1234, {:type => :worker, :signaled => Set.new(['INT'])}],
          [1236, {:type => :worker, :signaled => Set.new}]
        ], workers_with_state.sort)
    end
  end

  context "#unsignaled_workers" do
    setup do
      stub_children
    end

    should "selects unsignaled workers" do
      unsignaled_workers = Einhorn::WorkerPool.unsignaled_workers
      assert_equal([1236], unsignaled_workers)
    end
  end
end
