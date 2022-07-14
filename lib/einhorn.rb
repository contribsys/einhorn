require "fcntl"
require "optparse"
require "pp"
require "set"
require "socket"
require "tmpdir"
require "yaml"
require "shellwords"
require "einhorn/safe_yaml"

module Einhorn
  module AbstractState
    def default_state
      raise NotImplementedError.new("Override in extended modules")
    end

    def state
      @state ||= default_state
    end

    def state=(v)
      @state = v
    end

    def dumpable_state
      state
    end

    def respond_to_missing?(name)
      ((name.to_s =~ /(.*)=$/) && state.has_key?($1.to_sym)) ||
        state.has_key?(name) ||
        default_state.has_key?(name)
    end

    def method_missing(name, *args)
      if (name.to_s =~ /(.*)=$/) && state.has_key?($1.to_sym)
        state.send(:[]=, $1.to_sym, *args)
      elsif state.has_key?(name)
        state[name]
      else
        ds = default_state
        if ds.has_key?(name)
          ds[name]
        else
          super
        end
      end
    end
  end

  module State
    extend AbstractState

    # WARNING: Don't change or remove these variables without thinking
    # about backwards/forwards compatibility for upgrades/downgrades
    def self.default_state
      {
        children: {},
        config: {number: 1, backlog: 100, seconds: 1},
        versions: {},
        version: 0,
        sockets: {},
        orig_cmd: nil,
        bind: [],
        bind_fds: [],
        bound_ports: [],
        cmd: nil,
        script_name: nil,
        respawn: true,
        upgrading: false,
        smooth_upgrade: false,
        reloading_for_upgrade: false,
        path: nil,
        cmd_name: nil,
        verbosity: 1,
        generation: 0,
        last_spinup: nil,
        ack_mode: {type: :timer, timeout: 1},
        kill_children_on_exit: false,
        command_socket_as_fd: false,
        socket_path: nil,
        pidfile: nil,
        lockfile: nil,
        consecutive_deaths_before_ack: 0,
        last_upgraded: nil,
        nice: {master: nil, worker: nil, renice_cmd: "/usr/bin/renice"},
        reexec_commandline: nil,
        drop_environment_variables: [],
        signal_timeout: nil,
        preloaded: false
      }
    end
  end

  module TransientState
    extend AbstractState
    def self.default_state
      {
        whatami: :master,
        script_name: nil,
        argv: [],
        environ: {},
        has_outstanding_spinup_timer: false,
        stateful: nil,
        # Holds references so that the GC doesn't go and close your sockets.
        socket_handles: Set.new
      }
    end
  end

  def self.restore_state(state)
    parsed = SafeYAML.load(state)
    updated_state, message = update_state(Einhorn::State, "einhorn", parsed[:state])
    Einhorn::State.state = updated_state
    Einhorn::Event.restore_persistent_descriptors(parsed[:persistent_descriptors])
    # Do this after setting state so verbosity is right
    Einhorn.log_info("Using loaded state: #{parsed.inspect}")
    Einhorn.log_info(message) if message
  end

  def self.update_state(store, store_name, old_state)
    message = []
    updated_state = old_state.dup

    # Handle changes in state format updates from previous einhorn versions
    if store == Einhorn::State && updated_state[:children]
      # Depending on what is passed for --reexec-as, it's possible
      # that the process received a SIGCHLD while something other
      # than einhorn was the active executable. If that happened,
      # einhorn might not know about a dead child, so let's check
      # them all
      dead = []
      updated_state[:children].each do |pid, v|
        pid = Process.wait(pid, Process::WNOHANG)
        dead << pid if pid
      rescue Errno::ECHILD
        dead << pid
      end
      Einhorn::Event::Timer.open(0) do
        dead.each { |pid| Einhorn::Command.cleanup(pid) }
      end
    end

    default = store.default_state
    added_keys = default.keys - updated_state.keys
    deleted_keys = updated_state.keys - default.keys
    return [updated_state, message.first] if added_keys.length == 0 && deleted_keys.length == 0

    added_keys.each { |key| updated_state[key] = default[key] }
    deleted_keys.each { |key| updated_state.delete(key) }

    message << "adding default values for #{added_keys.inspect}"
    message << "deleting values for #{deleted_keys.inspect}"
    message = "State format for #{store_name} has changed: #{message.join(", ")}"

    # Can't print yet, since state hasn't been set, so we pass along the message.
    [updated_state, message]
  end

  def self.print_state
    log_info(Einhorn::State.state.pretty_inspect)
  end

  def self.bind(addr, port, flags)
    log_info("Binding to #{addr}:#{port} with flags #{flags.inspect}")
    sd = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    Einhorn::Compat.cloexec!(sd, false)

    if flags.include?("r") || flags.include?("so_reuseaddr")
      sd.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    end

    sd.bind(Socket.pack_sockaddr_in(port, addr))
    sd.listen(Einhorn::State.config[:backlog])

    if flags.include?("n") || flags.include?("o_nonblock")
      fl = sd.fcntl(Fcntl::F_GETFL)
      sd.fcntl(Fcntl::F_SETFL, fl | Fcntl::O_NONBLOCK)
    end

    Einhorn::TransientState.socket_handles << sd
    [sd.fileno, sd.local_address.ip_port]
  end

  # Implement these ourselves so it plays nicely with state persistence
  def self.log_debug(msg, tag = nil)
    warn("#{log_tag} DEBUG: #{msg}\n") if Einhorn::State.verbosity <= 0
    $stderr.flush
    send_tagged_message(tag, msg) if tag
  end

  def self.log_info(msg, tag = nil)
    warn("#{log_tag} INFO: #{msg}\n") if Einhorn::State.verbosity <= 1
    $stderr.flush
    send_tagged_message(tag, msg) if tag
  end

  def self.log_error(msg, tag = nil)
    warn("#{log_tag} ERROR: #{msg}\n") if Einhorn::State.verbosity <= 2
    $stderr.flush
    send_tagged_message(tag, "ERROR: #{msg}") if tag
  end

  def self.send_tagged_message(tag, message, last = false)
    Einhorn::Command::Interface.send_tagged_message(tag, message, last)
  end

  def self.log_tag
    case whatami = Einhorn::TransientState.whatami
    when :master
      "[MASTER #{$$}]"
    when :worker
      "[WORKER #{$$}]"
    when :state_passer
      "[STATE_PASSER #{$$}]"
    else
      "[UNKNOWN (#{whatami.inspect}) #{$$}]"
    end
  end
  private_class_method :log_tag

  def self.which(cmd)
    if cmd.include?("/")
      return cmd if File.exist?(cmd)
      raise "Could not find #{cmd}"
    else
      ENV["PATH"].split(":").each do |f|
        abs = File.join(f, cmd)
        return abs if File.exist?(abs)
      end
      raise "Could not find #{cmd} in PATH"
    end
  end

  # Not really a thing, but whatever.
  def self.is_script(file)
    File.open(file) do |f|
      bytes = f.read(2)
      bytes == "#!"
    end
  end

  def self.preload
    if (path = Einhorn::State.path)
      set_argv(Einhorn::State.cmd, false)

      begin
        # Reset preloaded state to false - this allows us to monitor for failed preloads during reloads.
        Einhorn::State.preloaded = false
        # If it's not going to be requireable, then load it.
        if !path.end_with?(".rb") && File.exist?(path)
          log_info("Loading #{path} (if this hangs, make sure your code can be properly loaded as a library)", :upgrade)
          load path
        else
          log_info("Requiring #{path} (if this hangs, make sure your code can be properly loaded as a library)", :upgrade)
          require path

          force_move_to_oldgen if Einhorn::State.config[:gc_before_fork]
        end
      rescue StandardError, LoadError => e
        log_info("Proceeding with postload -- could not load #{path}: #{e} (#{e.class})\n  #{e.backtrace.join("\n  ")}", :upgrade)
      else
        if defined?(einhorn_main)
          log_info("Successfully loaded #{path}", :upgrade)
          Einhorn::State.preloaded = true
        else
          log_info("Proceeding with postload -- loaded #{path}, but no einhorn_main method was defined", :upgrade)
        end
      end
    end
  end

  # Make the GC more copy-on-write friendly by forcibly incrementing the generation
  # counter on all objects to its maximum value. Learn more at: https://github.com/ko1/nakayoshi_fork
  def self.force_move_to_oldgen
    log_info("Starting GC to improve copy-on-write memory sharing", :upgrade)

    GC.start
    3.times do
      GC.start(full_mark: false)
    end

    GC.compact if GC.respond_to?(:compact)

    log_info("Finished GC after preloading", :upgrade)
  end
  private_class_method :force_move_to_oldgen

  def self.set_argv(cmd, set_ps_name)
    # TODO: clean up this hack
    idx = 0
    if /(^|\/)ruby$/.match?(cmd[0])
      idx = 1
    elsif !is_script(cmd[0])
      log_info("WARNING: Going to set $0 to #{cmd[idx]}, but it doesn't look like a script")
    end

    if set_ps_name
      # Note this will mess up $0 if we try using it in our code, but
      # we don't so that's basically ok. It's a bit annoying that this
      # is how Ruby exposes changing the output of ps. Note that Ruby
      # doesn't seem to shrink your cmdline buffer, so ps just ends up
      # having lots of trailing spaces if we set $0 to something
      # short. In the future, we could try to not pass einhorn's
      # state in ARGV.
      $0 = worker_ps_name
    end

    ARGV[0..-1] = cmd[idx + 1..-1]
    log_info("Set#{set_ps_name ? " $0 = #{$0.inspect}, " : nil} ARGV = #{ARGV.inspect}")
  end

  def self.set_master_ps_name
    $0 = master_ps_name
  end

  def self.master_ps_name
    "einhorn: #{worker_ps_name}"
  end

  def self.worker_ps_name
    Einhorn::State.cmd_name ? "ruby #{Einhorn::State.cmd_name}" : Einhorn::State.orig_cmd.join(" ")
  end

  def self.renice_self
    whatami = Einhorn::TransientState.whatami
    return unless (nice = Einhorn::State.nice[whatami])
    pid = $$

    unless nice.is_a?(Integer)
      raise "Nice must be a fixnum: #{nice.inspect}"
    end

    # Explicitly don't shellescape the renice command
    cmd = "#{Einhorn::State.nice[:renice_cmd]} #{nice} -p #{pid}"
    log_info("Running #{cmd.inspect} to renice self to level #{nice}")
    `#{cmd}`
    unless $?.exitstatus == 0
      # TODO: better error handling?
      log_error("Renice command exited with status: #{$?.inspect}, but continuing on anyway.")
    end
  end

  def self.socketify_env!
    Einhorn::State.bind.each do |host, port, flags|
      fd, actual_port = bind(host, port, flags)
      Einhorn::State.bind_fds << fd
      Einhorn::State.bound_ports << actual_port
    end
  end

  # Construct and a command and args that can be used to re-exec
  # Einhorn for upgrades.
  def self.upgrade_commandline(einhorn_flags = [])
    cmdline = []
    if Einhorn::State.reexec_commandline
      cmdline += Einhorn::State.reexec_commandline
    else
      cmdline << Einhorn::TransientState.script_name
    end
    cmdline += einhorn_flags
    cmdline << "--"
    cmdline += Einhorn::State.cmd
    [cmdline[0], cmdline[1..-1]]
  end

  # Returns true if a reload of the einhorn master via re-execing is
  # not likely to be completely unsafe (that is, the new process's
  # environment won't prevent it from loading its code on exec).
  def self.can_safely_reload?
    upgrade_sentinel = fork do
      Einhorn::TransientState.whatami = :upgrade_sentinel
      Einhorn.initialize_reload_environment
      Einhorn::Compat.exec(*Einhorn.upgrade_commandline(["--upgrade-check"]))
    end
    Process.wait(upgrade_sentinel)
    $?.exitstatus.zero?
  end

  # Set up the environment for reloading the einhorn master:
  # 1. Clear the current process's environment,
  # 2. Set it to the environmment at startup
  # 3. Delete all variables marked to be dropped via `--drop-env-var`
  #
  # This method is safe to call in the master only before `exec`ing
  # something.
  def self.initialize_reload_environment
    ENV.clear
    ENV.update(Einhorn::TransientState.environ)
    Einhorn::State.drop_environment_variables.each do |var|
      ENV.delete(var)
    end
  end

  # Log info about the environment as observed by ruby on
  # startup. Currently, this means the bundler and rbenv versions.
  def self.dump_environment_info
    log_info("Running under Ruby #{RUBY_VERSION}", :environment)
    log_info("Rbenv ruby version: #{ENV["RBENV_VERSION"]}", :environment) if ENV["RBENV_VERSION"]
    begin
      bundler_gem = Gem::Specification.find_by_name("bundler")
      log_info("Using Bundler #{bundler_gem.version}", :environment)
    rescue Gem::LoadError
    end
  end

  def self.run
    Einhorn::Command::Interface.init
    Einhorn::Event.init

    unless Einhorn::TransientState.stateful
      if Einhorn::State.config[:number] < 1
        log_error("You need to spin up at least at least 1 copy of the process")
        return
      end
      Einhorn::Command::Interface.persistent_init

      Einhorn::State.orig_cmd = ARGV.dup
      Einhorn::State.cmd = ARGV.dup
      # TODO: don't actually alter ARGV[0]?
      Einhorn::State.cmd[0] = which(Einhorn::State.cmd[0])
      socketify_env!
    end

    set_master_ps_name
    renice_self
    preload

    # In the middle of upgrading
    if Einhorn::State.reloading_for_upgrade
      Einhorn::Command.upgrade_workers
      Einhorn::State.reloading_for_upgrade = false
    end

    # If setting a signal-timeout, timeout the event loop
    # in the same timeframe, ensuring processes are culled
    # on a regular basis.
    if Einhorn::State.signal_timeout
      Einhorn::Event.default_timeout = Einhorn::Event.default_timeout.nil? ?
        Einhorn::State.signal_timeout : [Einhorn::State.signal_timeout, Einhorn::Event.default_timeout].min
    end

    while Einhorn::State.respawn || Einhorn::State.children.size > 0
      log_debug("Entering event loop")

      # All of these are non-blocking
      Einhorn::Command.reap
      Einhorn::Command.replenish
      Einhorn::Command.cull

      # Make sure to do this last, as it's blocking.
      Einhorn::Event.loop_once
    end
  end
end

require "einhorn/command"
require "einhorn/compat"
require "einhorn/client"
require "einhorn/event"
require "einhorn/worker"
require "einhorn/worker_pool"
require "einhorn/version"
