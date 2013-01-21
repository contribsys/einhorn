require 'pp'
require 'set'
require 'tmpdir'

require 'einhorn/command/interface'

module Einhorn
  module Command
    def self.reap
      begin
        while true
          Einhorn.log_debug('Going to reap a child process')

          pid = Process.wait(-1, Process::WNOHANG)
          return unless pid
          mourn(pid)
          Einhorn::Event.break_loop
        end
      rescue Errno::ECHILD
      end
    end

    # Mourn the death of your child
    def self.mourn(pid)
      unless spec = Einhorn::State.children[pid]
        Einhorn.log_error("Could not find any config for exited child #{pid.inspect}! This probably indicates a bug in Einhorn.")
        return
      end

      Einhorn::State.children.delete(pid)

      # Unacked worker
      if spec[:type] == :worker && !spec[:acked]
        Einhorn::State.consecutive_deaths_before_ack += 1
        extra = ' before it was ACKed'
      else
        extra = nil
      end

      case type = spec[:type]
      when :worker
        Einhorn.log_info("===> Exited worker #{pid.inspect}#{extra}")
      when :state_passer
        Einhorn.log_debug("===> Exited state passing process #{pid.inspect}")
      else
        Einhorn.log_error("===> Exited process #{pid.inspect} has unrecgonized type #{type.inspect}: #{spec.inspect}")
      end
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
      unless spec = Einhorn::State.children[pid]
        Einhorn.log_error("Could not find state for PID #{pid.inspect}; ignoring ACK.")
        return
      end

      if spec[:acked]
        Einhorn.log_error("Pid #{pid.inspect} already ACKed; ignoring new ACK.")
        return
      end

      if Einhorn::State.consecutive_deaths_before_ack > 0
        extra = ", breaking the streak of #{Einhorn::State.consecutive_deaths_before_ack} consecutive unacked workers dying"
      else
        extra = nil
      end
      Einhorn::State.consecutive_deaths_before_ack = 0

      spec[:acked] = true
      Einhorn.log_info("Up to #{Einhorn::WorkerPool.ack_count} / #{Einhorn::WorkerPool.ack_target} #{Einhorn::State.ack_mode[:type]} ACKs#{extra}")
      # Could call cull here directly instead, I believe.
      Einhorn::Event.break_loop
    end

    def self.signal_all(signal, children=nil, record=true)
      children ||= Einhorn::WorkerPool.workers

      signaled = []
      Einhorn.log_info("Sending #{signal} to #{children.inspect}")

      children.each do |child|
        unless spec = Einhorn::State.children[child]
          Einhorn.log_error("Trying to send #{signal} to dead child #{child.inspect}. The fact we tried this probably indicates a bug in Einhorn.")
          next
        end

        if record
          if spec[:signaled].include?(signal)
            Einhorn.log_error("Re-sending #{signal} to already-signaled child #{child.inspect}. It may be slow to spin down, or it may be swallowing #{signal}s.")
          end
          spec[:signaled].add(signal)
        end

        begin
          Process.kill(signal, child)
        rescue Errno::ESRCH
        else
          signaled << child
        end
      end

      "Successfully sent #{signal}s to #{signaled.length} processes: #{signaled.inspect}"
    end

    def self.increment
      Einhorn::Event.break_loop
      old = Einhorn::State.config[:number]
      new = (Einhorn::State.config[:number] += 1)
      output = "Incrementing number of workers from #{old} -> #{new}"
      $stderr.puts(output)
      output
    end

    def self.decrement
      if Einhorn::State.config[:number] <= 1
        output = "Can't decrease number of workers (already at #{Einhorn::State.config[:number]}).  Run kill #{$$} if you really want to kill einhorn."
        $stderr.puts(output)
        return output
      end

      Einhorn::Event.break_loop
      old = Einhorn::State.config[:number]
      new = (Einhorn::State.config[:number] -= 1)
      output = "Decrementing number of workers from #{old} -> #{new}"
      $stderr.puts(output)
      output
    end

    def self.dumpable_state
      global_state = Einhorn::State.state
      descriptor_state = Einhorn::Event.persistent_descriptors.map do |descriptor|
        descriptor.to_state
      end

      {
        :state => global_state,
        :persistent_descriptors => descriptor_state
      }
    end

    def self.reload
      unless Einhorn::State.respawn
        Einhorn.log_info("Not reloading einhorn because we're exiting")
        return
      end

      Einhorn.log_info("Reloading einhorn (#{Einhorn::TransientState.script_name})...")

      # In case there's anything lurking
      $stdout.flush

      # Spawn a child to pass the state through the pipe
      read, write = IO.pipe
      fork do
        Einhorn::TransientState.whatami = :state_passer
        Einhorn::State.generation += 1
        Einhorn::State.children[$$] = {
          :type => :state_passer
        }
        read.close

        write.write(YAML.dump(dumpable_state))
        write.close

        exit(0)
      end
      write.close

      Einhorn::Event.uninit

      # Reload the original environment
      ENV.clear
      ENV.update(Einhorn::TransientState.environ)

      exec [Einhorn::TransientState.script_name, Einhorn::TransientState.script_name], *(['--with-state-fd', read.fileno.to_s, '--'] + Einhorn::State.cmd)
    end

    def self.spinup(cmd=nil)
      cmd ||= Einhorn::State.cmd
      if Einhorn::TransientState.preloaded
        pid = fork do
          Einhorn::TransientState.whatami = :worker
          prepare_child_process

          Einhorn.log_info('About to tear down Einhorn state and run einhorn_main')
          Einhorn::Command::Interface.uninit
          Einhorn::Event.close_all_for_worker
          Einhorn.set_argv(cmd, true)

          prepare_child_environment
          einhorn_main
        end
      else
        pid = fork do
          Einhorn::TransientState.whatami = :worker
          prepare_child_process

          Einhorn.log_info("About to exec #{cmd.inspect}")
          # Here's the only case where cloexec would help. Since we
          # have to track and manually close FDs for other cases, we
          # may as well just reuse close_all rather than also set
          # cloexec on everything.
          Einhorn::Event.close_all_for_worker

          prepare_child_environment
          exec [cmd[0], cmd[0]], *cmd[1..-1]
        end
      end

      Einhorn.log_info("===> Launched #{pid}")
      Einhorn::State.children[pid] = {
        :type => :worker,
        :version => Einhorn::State.version,
        :acked => false,
        :signaled => Set.new
      }
      Einhorn::State.last_spinup = Time.now

      # Set up whatever's needed for ACKing
      ack_mode = Einhorn::State.ack_mode
      case type = ack_mode[:type]
      when :timer
        Einhorn::Event::ACKTimer.open(ack_mode[:timeout], pid)
      when :manual
      else
        Einhorn.log_error("Unrecognized ACK mode #{type.inspect}")
      end
    end

    def self.prepare_child_environment
      # This is run from the child
      ENV['EINHORN_MASTER_PID'] = Process.ppid.to_s
      ENV['EINHORN_SOCK_PATH'] = Einhorn::Command::Interface.socket_path
      if Einhorn::State.command_socket_as_fd
        socket = UNIXSocket.open(Einhorn::Command::Interface.socket_path)
        Einhorn::TransientState.socket_handles << socket
        ENV['EINHORN_SOCK_FD'] = socket.fileno.to_s
      end
      # Try to match Upstart's internal support for space-separated FD
      # lists. (I don't think anyone actually uses that functionality,
      # but seems reasonable enough.)
      ENV['EINHORN_FDS'] = Einhorn::State.bind_fds.map(&:to_s).join(' ')
    end

    def self.prepare_child_process
      Einhorn.renice_self(false)
    end

    def self.full_upgrade
      if Einhorn::State.path && !Einhorn::State.reloading_for_preload_upgrade
        reload_for_preload_upgrade
      else
        upgrade_workers
      end
    end

    def self.reload_for_preload_upgrade
      Einhorn::State.reloading_for_preload_upgrade = true
      reload
    end

    def self.upgrade_workers
      if Einhorn::State.upgrading
        Einhorn.log_info("Currently upgrading (#{Einhorn::WorkerPool.ack_count} / #{Einhorn::WorkerPool.ack_target} ACKs; bumping version and starting over)...")
      else
        Einhorn::State.upgrading = true
        Einhorn.log_info("Starting upgrade to #{Einhorn::State.version}...")
      end

      # Reset this, since we've just upgraded to a new universe (I'm
      # not positive this is the right behavior, but it's not
      # obviously wrong.)
      Einhorn::State.consecutive_deaths_before_ack = 0
      Einhorn::State.last_upgraded = Time.now

      Einhorn::State.version += 1
      replenish_immediately
    end

    def self.cull
      acked = Einhorn::WorkerPool.ack_count
      target = Einhorn::WorkerPool.ack_target

      if Einhorn::State.upgrading && acked >= target
        Einhorn::State.upgrading = false
        Einhorn.log_info("Upgrade to version #{Einhorn::State.version} complete.")
      end

      old_workers = Einhorn::WorkerPool.old_workers
      if !Einhorn::State.upgrading && old_workers.length > 0
        Einhorn.log_info("Killing off #{old_workers.length} old workers.")
        signal_all("USR2", old_workers)
      end

      if acked > target
        excess = Einhorn::WorkerPool.acked_unsignaled_modern_workers[0...(acked-target)]
        Einhorn.log_info("Have too many workers at the current version, so killing off #{excess.length} of them.")
        signal_all("USR2", excess)
      end
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
      missing.times {spinup}
    end

    def self.replenish_gradually
      return if Einhorn::TransientState.has_outstanding_spinup_timer
      return unless Einhorn::WorkerPool.missing_worker_count > 0

      # Exponentially backoff automated spinup if we're just having
      # things die before ACKing
      spinup_interval = Einhorn::State.config[:seconds] * (1.5 ** Einhorn::State.consecutive_deaths_before_ack)
      seconds_ago = (Time.now - Einhorn::State.last_spinup).to_f

      if seconds_ago > spinup_interval
        msg = "Last spinup was #{seconds_ago}s ago, and spinup_interval is #{spinup_interval}s, so spinning up a new process"

        if Einhorn::State.consecutive_deaths_before_ack > 0
          Einhorn.log_info("#{msg} (there have been #{Einhorn::State.consecutive_deaths_before_ack} consecutive unacked worker deaths)")
        else
          Einhorn.log_debug(msg)
        end

        spinup
      else
        Einhorn.log_debug("Last spinup was #{seconds_ago}s ago, and spinup_interval is #{spinup_interval}s, so not spinning up a new process")
      end

      Einhorn::TransientState.has_outstanding_spinup_timer = true
      Einhorn::Event::Timer.open(spinup_interval) do
        Einhorn::TransientState.has_outstanding_spinup_timer = false
        replenish
      end
    end

    def self.quieter(log=true)
      Einhorn::State.verbosity += 1 if Einhorn::State.verbosity < 2
      output = "Verbosity set to #{Einhorn::State.verbosity}"
      Einhorn.log_info(output) if log
      output
    end

    def self.louder(log=true)
      Einhorn::State.verbosity -= 1 if Einhorn::State.verbosity > 0
      output = "Verbosity set to #{Einhorn::State.verbosity}"
      Einhorn.log_info(output) if log
      output
    end
  end
end
