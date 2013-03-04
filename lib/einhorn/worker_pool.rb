module Einhorn
  module WorkerPool
    def self.workers_with_state
      Einhorn::State.children.select do |pid, spec|
        spec[:type] == :worker
      end
    end

    def self.workers
      workers_with_state.map {|pid, _| pid}
    end

    def self.unsignaled_workers
      workers_with_state.select do |pid, spec|
        spec[:signaled].length == 0
      end.map {|pid, _| pid}
    end

    def self.modern_workers_with_state
      workers_with_state.select do |pid, spec|
        spec[:version] == Einhorn::State.version
      end
    end

    def self.acked_modern_workers_with_state
      modern_workers_with_state.select {|pid, spec| spec[:acked]}
    end

    def self.modern_workers
      modern_workers_with_state.map {|pid, _| pid}
    end

    def self.acked_modern_workers
      acked_modern_workers_with_state.map {|pid, _| pid}
    end

    def self.acked_unsignaled_modern_workers
      acked_modern_workers_with_state.select do |_, spec|
        spec[:signaled].length == 0
      end.map {|pid, _| pid}
    end

    # Use the number of modern workers, rather than unsignaled modern
    # workers. This means if e.g. we do bunch of decs and then incs,
    # any workers which haven't died yet will count towards our number
    # of workers. Since workers really should be dying shortly after
    # they are USR2'd, that indicates a bad state and we shouldn't
    # make it worse by spinning up more processes. Once they die,
    # order will be restored.
    def self.missing_worker_count
      ack_target - modern_workers.length
    end

    def self.ack_count
      acked_unsignaled_modern_workers.length
    end

    def self.ack_target
      Einhorn::State.config[:number]
    end

    def self.old_workers
      unsignaled_workers - modern_workers
    end
  end
end
