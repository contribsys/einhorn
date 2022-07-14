require "pp"
require "set"
require "tmpdir"

require "einhorn/command/interface"
require "einhorn/prctl"

module Einhorn
  module Command
    def self.reap
      loop do
        Einhorn.log_debug("Going to reap a child process")
        pid = Process.wait(-1, Process::WNOHANG)
        return unless pid
        cleanup(pid)
        Einhorn::Event.break_loop
      end
    rescue Errno::ECHILD
    end

    def self.cleanup(pid)
      unless (spec = Einhorn::State.children[pid])
        Einhorn.log_error("Could not find any config for exited child #{pid.inspect}! This probably indicates a bug in Einhorn.")
        return
      end

      Einhorn::State.children.delete(pid)

      # Unacked worker
      if spec[:type] == :worker && !spec[:acked]
        Einhorn::State.consecutive_deaths_before_ack += 1
        extra = " before it was ACKed"
      else
        extra = nil
      end

      case type = spec[:type]
      when :worker
        Einhorn.log_info("===> Exited worker #{pid.inspect}#{extra}", :upgrade)
      when :state_passer
        Einhorn.log_debug("===> Exited state passing process #{pid.inspect}", :upgrade)
      else
        Einhorn.log_error("===> Exited process #{pid.inspect} has unrecgonized type #{type.inspect}: #{spec.inspect}", :upgrade)
      end
    end

    def self.register_ping(pid, request_id)
      unless (spec = Einhorn::State.children[pid])
        Einhorn.log_error("Could not find state for PID #{pid.inspect}; ignoring ACK.")
        return
      end

      spec[:pinged_at] = Time.now
      spec[:pinged_request_id] = request_id
    end

    def self.register_manual_ack(pid)
      ack_mode = Einhorn::State.ack_mode
      unless ack_mode[:type] == :manual
        Einhorn.log_error("Received a manual ACK for #{pid.inspect}, but ack_mode is #{ack_mode.inspect}. Ignoring ACK.")
        return
      end
      Einhorn.log_info("Received a manual ACK from #{pid.inspect}")
      register_ack(pid)
    end

    def self.register_timer_ack(time, pid)
      ack_mode = Einhorn::State.ack_mode
      unless ack_mode[:type] == :timer
        Einhorn.log_error("Received a timer ACK for #{pid.inspect}, but ack_mode is #{ack_mode.inspect}. Ignoring ACK.")
        return
      end

      unless Einhorn::State.children[pid]
        # TODO: Maybe cancel pending ACK timers upon death?
        Einhorn.log_debug("Worker #{pid.inspect} died before its timer ACK happened.")
        return
      end

      Einhorn.log_info("Worker #{pid.inspect} has been up for #{time}s, so we are considering it alive.")
      register_ack(pid)
    end

    def self.register_ack(pid)
      unless (spec = Einhorn::State.children[pid])
        Einhorn.log_error("Could not find state for PID #{pid.inspect}; ignoring ACK.")
        return
      end

      if spec[:acked]
        Einhorn.log_error("Pid #{pid.inspect} already ACKed; ignoring new ACK.")
        return
      end

      extra = if Einhorn::State.consecutive_deaths_before_ack > 0
        ", breaking the streak of #{Einhorn::State.consecutive_deaths_before_ack} consecutive unacked workers dying"
      end
      Einhorn::State.consecutive_deaths_before_ack = 0

      spec[:acked] = true
      Einhorn.log_info("Up to #{Einhorn::WorkerPool.ack_count} / #{Einhorn::WorkerPool.ack_target} #{Einhorn::State.ack_mode[:type]} ACKs#{extra}")
      # Could call cull here directly instead, I believe.
      Einhorn::Event.break_loop
    end

    def self.signal_all(signal, children = nil, record = true)
      children ||= Einhorn::WorkerPool.workers
      signaled = {}

      Einhorn.log_info("Sending #{signal} to #{children.inspect}", :upgrade)

      children.each do |child|
        unless (spec = Einhorn::State.children[child])
          Einhorn.log_error("Trying to send #{signal} to dead child #{child.inspect}. The fact we tried this probably indicates a bug in Einhorn.", :upgrade)
          next
        end

        if record
          if spec[:signaled].include?(signal)
            Einhorn.log_error("Re-sending #{signal} to already-signaled child #{child.inspect}. It may be slow to spin down, or it may be swallowing #{signal}s.", :upgrade)
          end
          spec[:signaled].add(signal)
          spec[:last_signaled_at] = Time.now
        end

        begin
          Process.kill(signal, child)
        rescue Errno::ESRCH
          Einhorn.log_debug("Attempted to #{signal} child #{child.inspect} but the process does not exist", :upgrade)
        else
          signaled[child] = spec
        end
      end

      if Einhorn::State.signal_timeout && record
        Einhorn::Event::Timer.open(Einhorn::State.signal_timeout) do
          children.each do |child|
            spec = Einhorn::State.children[child]
            next unless spec # Process is already dead and removed by cleanup
            signaled_spec = signaled[child]
            next unless signaled_spec # We got ESRCH when trying to signal
            if spec[:spinup_time] != signaled_spec[:spinup_time]
              Einhorn.log_info("Different spinup time recorded for #{child} after #{Einhorn::State.signal_timeout}s. This probably indicates a PID rollover.", :upgrade)
              next
            end

            Einhorn.log_info("Child #{child.inspect} is still active after #{Einhorn::State.signal_timeout}s. Sending SIGKILL.")
            begin
              Process.kill("KILL", child)
            rescue Errno::ESRCH
            end
            spec[:signaled].add("KILL")
          end
        end

        Einhorn.log_info("Successfully sent #{signal}s to #{signaled.length} processes: #{signaled.keys}")
      end
    end

    def self.increment
      Einhorn::Event.break_loop
      old = Einhorn::State.config[:number]
      new = (Einhorn::State.config[:number] += 1)
      output = "Incrementing number of workers from #{old} -> #{new}"
      warn(output)
      output
    end

    def self.decrement
      if Einhorn::State.config[:number] <= 1
        output = "Can't decrease number of workers (already at #{Einhorn::State.config[:number]}).  Run kill #{$$} if you really want to kill einhorn."
        warn(output)
        return output
      end

      Einhorn::Event.break_loop
      old = Einhorn::State.config[:number]
      new = (Einhorn::State.config[:number] -= 1)
      output = "Decrementing number of workers from #{old} -> #{new}"
      warn(output)
      output
    end

    def self.set_workers(new)
      if new == Einhorn::State.config[:number]
        return ""
      end

      Einhorn::Event.break_loop
      old = Einhorn::State.config[:number]
      Einhorn::State.config[:number] = new
      output = "Altering worker count, #{old} -> #{new}. Will "
      output << if old < new
        "spin up additional workers."
      else
        "gracefully terminate workers."
      end
      warn(output)
      output
    end

    def self.dumpable_state
      global_state = Einhorn::State.dumpable_state
      descriptor_state = Einhorn::Event.persistent_descriptors.map do |descriptor|
        descriptor.to_state
      end

      {
        state: global_state,
        persistent_descriptors: descriptor_state
      }
    end

    def self.reload
      unless Einhorn::State.respawn
        Einhorn.log_info("Not reloading einhorn because we're exiting")
        return
      end

      Einhorn.log_info("Reloading einhorn master (#{Einhorn::TransientState.script_name})...", :reload)

      # In case there's anything lurking
      $stdout.flush

      # Spawn a child to pass the state through the pipe
      read, write = Einhorn::Compat.pipe

      fork do
        Einhorn::TransientState.whatami = :state_passer
        Einhorn::State.children[Process.pid] = {type: :state_passer}
        Einhorn::State.generation += 1
        read.close

        begin
          write.write(YAML.dump(dumpable_state))
        rescue Errno::EPIPE => e
          e.message << " (state worker could not write state, which likely means the parent process has died)"
          raise e
        end
        write.close

        exit(0)
      end
      write.close

      unless Einhorn.can_safely_reload?
        Einhorn.log_error("Can not initiate einhorn master reload safely, aborting", :reload)
        Einhorn::State.reloading_for_upgrade = false
        read.close
        return
      end

      begin
        Einhorn.initialize_reload_environment
        respawn_commandline = Einhorn.upgrade_commandline(["--with-state-fd", read.fileno.to_s])
        respawn_commandline << {close_others: false}
        Einhorn.log_info("About to re-exec einhorn master as #{respawn_commandline.inspect}", :reload)
        Einhorn::Compat.exec(*respawn_commandline)
      rescue SystemCallError => e
        Einhorn.log_error("Could not reload! Attempting to continue. Error was: #{e}", :reload)
        Einhorn::State.reloading_for_upgrade = false
        read.close
      end
    end

    def self.next_index
      all_indexes = Set.new(Einhorn::State.children.map { |k, st| st[:index] })
      0.upto(all_indexes.length) do |i|
        return i unless all_indexes.include?(i)
      end
    end

    def self.spinup(cmd = nil)
      cmd ||= Einhorn::State.cmd
      index = next_index
      expected_ppid = Process.pid
      pid = if Einhorn::State.preloaded
        fork do
          Einhorn::TransientState.whatami = :worker
          prepare_child_process

          Einhorn.log_info("About to tear down Einhorn state and run einhorn_main")
          Einhorn::Command::Interface.uninit
          Einhorn::Event.close_all_for_worker
          Einhorn.set_argv(cmd, true)

          reseed_random

          setup_parent_watch(expected_ppid)

          prepare_child_environment(index)
          einhorn_main
        end
      else
        fork do
          Einhorn::TransientState.whatami = :worker
          prepare_child_process

          Einhorn.log_info("About to exec #{cmd.inspect}")
          Einhorn::Command::Interface.uninit
          # Here's the only case where cloexec would help. Since we
          # have to track and manually close FDs for other cases, we
          # may as well just reuse close_all rather than also set
          # cloexec on everything.
          #
          # Note that Ruby 1.9's close_others option is useful here.
          Einhorn::Event.close_all_for_worker

          setup_parent_watch(expected_ppid)

          prepare_child_environment(index)
          Einhorn::Compat.exec(cmd[0], cmd[1..-1], close_others: false)
        end
      end

      Einhorn.log_info("===> Launched #{pid} (index: #{index})", :upgrade)
      Einhorn::State.last_spinup = Time.now
      Einhorn::State.children[pid] = {
        type: :worker,
        version: Einhorn::State.version,
        acked: false,
        signaled: Set.new,
        last_signaled_at: nil,
        index: index,
        spinup_time: Einhorn::State.last_spinup
      }

      # Set up whatever's needed for ACKing
      ack_mode = Einhorn::State.ack_mode
      case type = ack_mode[:type]
      when :timer
        Einhorn::Event::ACKTimer.open(ack_mode[:timeout], pid)
      when :manual
        # nothing to do
      else
        Einhorn.log_error("Unrecognized ACK mode #{type.inspect}")
      end
    end

    def self.prepare_child_environment(index)
      # This is run from the child
      ENV["EINHORN_MASTER_PID"] = Process.ppid.to_s
      ENV["EINHORN_SOCK_PATH"] = Einhorn::Command::Interface.socket_path
      if Einhorn::State.command_socket_as_fd
        socket = UNIXSocket.open(Einhorn::Command::Interface.socket_path)
        Einhorn::TransientState.socket_handles << socket
        ENV["EINHORN_SOCK_FD"] = socket.fileno.to_s
      end

      ENV["EINHORN_FD_COUNT"] = Einhorn::State.bind_fds.length.to_s
      Einhorn::State.bind_fds.each_with_index { |fd, i| ENV["EINHORN_FD_#{i}"] = fd.to_s }

      ENV["EINHORN_CHILD_INDEX"] = index.to_s
    end

    # Reseed common ruby random number generators.
    #
    # OpenSSL::Random uses the PID to reseed after fork, which means that if a
    # long-lived master process over its lifetime spawns two workers with the
    # same PID, those workers will start with the same OpenSSL seed.
    #
    # Ruby >= 1.9 has a guard against this in SecureRandom, but any direct
    # users of OpenSSL::Random will still be affected.
    #
    # Ruby 1.8 didn't even reseed the default random number generator used by
    # Kernel#rand in certain releases.
    #
    # https://bugs.ruby-lang.org/issues/4579
    #
    def self.reseed_random
      # reseed Kernel#rand
      srand

      # reseed OpenSSL::Random if it's loaded
      if defined?(OpenSSL::Random)
        seed = if defined?(Random)
          Random.new_seed
        else
          # Ruby 1.8
          rand
        end
        OpenSSL::Random.seed(seed.to_s)
      end
    end

    def self.prepare_child_process
      Process.setpgrp
      Einhorn.renice_self
    end

    def self.setup_parent_watch(expected_ppid)
      if Einhorn::State.kill_children_on_exit
        begin
          # NB: Having the USR2 signal handler set to terminate (the default) at
          # this point is required. If it's set to a ruby handler, there are
          # race conditions that could cause the worker to leak.

          Einhorn::Prctl.set_pdeathsig("USR2")
          if Process.ppid != expected_ppid
            Einhorn.log_error("Parent process died before we set pdeathsig; cowardly refusing to exec child process.")
            exit(1)
          end
        rescue NotImplementedError
          # Unsupported OS; silently continue.
        end
      end
    end

    # @param options [Hash]
    #
    # @option options [Boolean] :smooth (false) Whether to perform a smooth or
    #   fleet upgrade. In a smooth upgrade, bring up new workers and cull old
    #   workers one by one as soon as there is a replacement. In a fleet
    #   upgrade, bring up all the new workers and don't cull any old workers
    #   until they're all up.
    #
    def self.full_upgrade(options = {})
      options = {smooth: false}.merge(options)

      Einhorn::State.smooth_upgrade = options.fetch(:smooth)
      reload_for_upgrade
    end

    def self.full_upgrade_smooth
      full_upgrade(smooth: true)
    end

    def self.full_upgrade_fleet
      full_upgrade(smooth: false)
    end

    def self.reload_for_upgrade
      Einhorn::State.reloading_for_upgrade = true
      reload
    end

    def self.upgrade_workers
      if Einhorn::State.upgrading
        Einhorn.log_info("Currently upgrading (#{Einhorn::WorkerPool.ack_count} / #{Einhorn::WorkerPool.ack_target} ACKs; bumping version and starting over)...", :upgrade)
      else
        Einhorn::State.upgrading = true
        u_type = Einhorn::State.smooth_upgrade ? "smooth" : "fleet"
        Einhorn.log_info("Starting #{u_type} upgrade from version" \
                         " #{Einhorn::State.version}...", :upgrade)
      end

      # Reset this, since we've just upgraded to a new universe (I'm
      # not positive this is the right behavior, but it's not
      # obviously wrong.)
      Einhorn::State.consecutive_deaths_before_ack = 0
      Einhorn::State.last_upgraded = Time.now

      Einhorn::State.version += 1
      if Einhorn::State.smooth_upgrade
        replenish_gradually
      else
        replenish_immediately
      end
    end

    def self.cull
      acked = Einhorn::WorkerPool.ack_count
      unsignaled = Einhorn::WorkerPool.unsignaled_count
      target = Einhorn::WorkerPool.ack_target

      if Einhorn::State.upgrading && acked >= target
        Einhorn::State.upgrading = false
        Einhorn.log_info("Upgraded successfully to version #{Einhorn::State.version} (Einhorn #{Einhorn::VERSION}).", :upgrade)
        Einhorn.send_tagged_message(:upgrade, "Upgrade done", true)
      end

      old_workers = Einhorn::WorkerPool.old_workers
      Einhorn.log_debug("#{acked} acked, #{unsignaled} unsignaled, #{target} target, #{old_workers.length} old workers")
      if !Einhorn::State.upgrading && old_workers.length > 0
        Einhorn.log_info("Killing off #{old_workers.length} old workers.", :upgrade)
        signal_all("USR2", old_workers)
      elsif Einhorn::State.upgrading && Einhorn::State.smooth_upgrade
        # In a smooth upgrade, kill off old workers one by one when we have
        # sufficiently many new workers.
        excess = (old_workers.length + acked) - target
        if excess > 0
          Einhorn.log_info("Smooth upgrade: killing off #{excess} old workers.", :upgrade)
          signal_all("USR2", old_workers.take(excess))
        else
          Einhorn.log_debug("Not killing old workers, as excess is #{excess}.")
        end
      end

      if unsignaled > target
        excess = Einhorn::WorkerPool.unsignaled_modern_workers_with_priority[0...(unsignaled - target)]
        Einhorn.log_info("Have too many workers at the current version, so killing off #{excess.length} of them.")
        signal_all("USR2", excess)
      end

      # Ensure all signaled workers that have outlived signal_timeout get killed.
      kill_expired_signaled_workers if Einhorn::State.signal_timeout
    end

    def self.kill_expired_signaled_workers
      now = Time.now
      children = Einhorn::State.children.select do |_, c|
        # Only interested in USR2 signaled workers
        next unless c[:signaled] && c[:signaled].length > 0
        next unless c[:signaled].include?("USR2")

        # Ignore processes that have received KILL since it can't be trapped.
        next if c[:signaled].include?("KILL")

        # Filter out those children that have not reached signal_timeout yet.
        next unless c[:last_signaled_at]
        expires_at = c[:last_signaled_at] + Einhorn::State.signal_timeout
        next unless now >= expires_at

        true
      end

      Einhorn.log_info("#{children.size} expired signaled workers found.") if children.size > 0
      children.each do |pid, child|
        Einhorn.log_info("Child #{pid.inspect} was signaled #{(child[:last_signaled_at] - now).abs.to_i}s ago. Sending SIGKILL as it is still active after #{Einhorn::State.signal_timeout}s timeout.", :upgrade)
        begin
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          Einhorn.log_debug("Attempted to SIGKILL child #{pid.inspect} but the process does not exist.")
        end

        child[:signaled].add("KILL")
        child[:last_signaled_at] = Time.now
      end
    end

    def self.stop_respawning
      Einhorn::State.respawn = false
      Einhorn::Event.break_loop
    end

    def self.replenish
      return unless Einhorn::State.respawn

      if !Einhorn::State.last_spinup
        replenish_immediately
      else
        replenish_gradually
      end
    end

    def self.replenish_immediately
      missing = Einhorn::WorkerPool.missing_worker_count
      if missing <= 0
        Einhorn.log_error("Missing is currently #{missing.inspect}, but should always be > 0 when replenish_immediately is called. This probably indicates a bug in Einhorn.")
        return
      end
      Einhorn.log_info("Launching #{missing} new workers")
      missing.times { spinup }
    end

    # Unbounded exponential backoff is not a thing: we run into problems if
    # e.g., each of our hundred workers simultaneously fail to boot for the same
    # ephemeral reason. Instead cap backoff by some reasonable maximum, so we
    # don't wait until the heat death of the universe to spin up new capacity.
    MAX_SPINUP_INTERVAL = 30.0

    def self.replenish_gradually(max_unacked = nil)
      return if Einhorn::TransientState.has_outstanding_spinup_timer
      return unless Einhorn::WorkerPool.missing_worker_count > 0

      max_unacked ||= Einhorn::State.config[:max_unacked]

      # default to spinning up at most NCPU workers at once
      unless max_unacked
        begin
          @processor_count ||= Einhorn::Compat.processor_count
        rescue => err
          Einhorn.log_error(err.inspect)
          @processor_count = 1
        end
        max_unacked = @processor_count
      end

      if max_unacked <= 0
        raise ArgumentError.new("max_unacked must be positive")
      end

      # Exponentially backoff automated spinup if we're just having
      # things die before ACKing
      spinup_interval = Einhorn::State.config[:seconds] * (1.5**Einhorn::State.consecutive_deaths_before_ack)
      spinup_interval = [spinup_interval, MAX_SPINUP_INTERVAL].min
      seconds_ago = (Time.now - Einhorn::State.last_spinup).to_f

      if seconds_ago > spinup_interval
        if trigger_spinup?(max_unacked)
          msg = "Last spinup was #{seconds_ago}s ago, and spinup_interval is #{spinup_interval}s, so spinning up a new process."

          if Einhorn::State.consecutive_deaths_before_ack > 0
            Einhorn.log_info("#{msg} (there have been #{Einhorn::State.consecutive_deaths_before_ack} consecutive unacked worker deaths)", :upgrade)
          else
            Einhorn.log_debug(msg)
          end

          spinup
        end
      else
        Einhorn.log_debug("Last spinup was #{seconds_ago}s ago, and spinup_interval is #{spinup_interval}s, so not spinning up a new process.")
      end

      Einhorn::TransientState.has_outstanding_spinup_timer = true
      Einhorn::Event::Timer.open(spinup_interval) do
        Einhorn::TransientState.has_outstanding_spinup_timer = false
        replenish
      end
    end

    def self.quieter(log = true)
      Einhorn::State.verbosity += 1 if Einhorn::State.verbosity < 2
      output = "Verbosity set to #{Einhorn::State.verbosity}"
      Einhorn.log_info(output) if log
      output
    end

    def self.louder(log = true)
      Einhorn::State.verbosity -= 1 if Einhorn::State.verbosity > 0
      output = "Verbosity set to #{Einhorn::State.verbosity}"
      Einhorn.log_info(output) if log
      output
    end

    def self.trigger_spinup?(max_unacked)
      unacked = Einhorn::WorkerPool.unacked_unsignaled_modern_workers.length
      if unacked >= max_unacked
        Einhorn.log_info("There are #{unacked} unacked new workers, and max_unacked is #{max_unacked}, so not spinning up a new process.")
        return false
      elsif Einhorn::State.config[:max_upgrade_additional]
        capacity_exceeded = (Einhorn::State.config[:number] + Einhorn::State.config[:max_upgrade_additional]) - Einhorn::WorkerPool.workers_with_state.length
        if capacity_exceeded < 0
          Einhorn.log_info("Over worker capacity by #{capacity_exceeded.abs} during upgrade, #{Einhorn::WorkerPool.modern_workers.length} new workers of #{Einhorn::WorkerPool.workers_with_state.length} total. Waiting for old workers to exit before spinning up a process.")

          return false
        end
      end

      true
    end
  end
end
