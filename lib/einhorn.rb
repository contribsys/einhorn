require 'fcntl'
require 'optparse'
require 'pp'
require 'set'
require 'socket'
require 'tmpdir'
require 'yaml'

module Einhorn
  module AbstractState
    def default_state; raise NotImplementedError.new('Override in extended modules'); end
    def state; @state ||= default_state; end
    def state=(v); @state = v; end

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
    def self.default_state
      {
        :children => {},
        :config => {:number => 1, :backlog => 100, :seconds => 1},
        :versions => {},
        :version => 0,
        :sockets => {},
        :orig_cmd => nil,
        :cmd => nil,
        :script_name => nil,
        :respawn => true,
        :upgrading => false,
        :reloading_for_preload_upgrade => false,
        :path => nil,
        :cmd_name => nil,
        :verbosity => 1,
        :generation => 0,
        :last_spinup => nil,
        :ack_mode => {:type => :timer, :timeout => 1},
        :kill_children_on_exit => false,
        :command_socket_as_fd => false,
        :socket_path => nil,
        :pidfile => nil,
        :lockfile => nil
      }
    end
  end

  module TransientState
    extend AbstractState
    def self.default_state
      {
        :whatami => :master,
        :preloaded => false,
        :script_name => nil,
        :argv => [],
        :environ => {},
        :has_outstanding_spinup_timer => false,
        :stateful => nil,
        # Holds references so that the GC doesn't go and close your sockets.
        :socket_handles => Set.new
      }
    end
  end

  def self.restore_state(state)
    parsed = YAML.load(state)
    Einhorn::State.state = parsed[:state]
    Einhorn::Event.restore_persistent_descriptors(parsed[:persistent_descriptors])
    # Do this after setting state so verbosity is right9
    Einhorn.log_info("Using loaded state: #{parsed.inspect}")
  end

  def self.print_state
    log_info(Einhorn::State.state.pretty_inspect)
  end

  def self.bind(addr, port, flags)
    log_info("Binding to #{addr}:#{port} with flags #{flags.inspect}")
    sd = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)

    if flags.include?('r') || flags.include?('so_reuseaddr')
      sd.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    end

    sd.bind(Socket.pack_sockaddr_in(port, addr))
    sd.listen(Einhorn::State.config[:backlog])

    if flags.include?('n') || flags.include?('o_nonblock')
      fl = sd.fcntl(Fcntl::F_GETFL)
      sd.fcntl(Fcntl::F_SETFL, fl | Fcntl::O_NONBLOCK)
    end

    Einhorn::TransientState.socket_handles << sd
    sd.fileno
  end

  # Implement these ourselves so it plays nicely with state persistence
  def self.log_debug(msg)
    $stderr.puts("#{log_tag} DEBUG: #{msg}") if Einhorn::State.verbosity <= 0
  end
  def self.log_info(msg)
    $stderr.puts("#{log_tag} INFO: #{msg}") if Einhorn::State.verbosity <= 1
  end
  def self.log_error(msg)
    $stderr.puts("#{log_tag} ERROR: #{msg}") if Einhorn::State.verbosity <= 2
  end

  private

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

  public

  def self.which(cmd)
    if cmd.include?('/')
      return cmd if File.exists?(cmd)
      raise "Could not find #{cmd}"
    else
      ENV['PATH'].split(':').each do |f|
        abs = File.join(f, cmd)
        return abs if File.exists?(abs)
      end
      raise "Could not find #{cmd} in PATH"
    end
  end

  # Not really a thing, but whatever.
  def self.is_script(file)
    File.open(file) do |f|
      bytes = f.read(2)
      bytes == '#!'
    end
  end

  def self.preload
    if path = Einhorn::State.path
      set_argv(Einhorn::State.cmd, false)

      begin
        # If it's not going to be requireable, then load it.
        if !path.end_with?('.rb') && File.exists?(path)
          log_info("Loading #{path} (if this hangs, make sure your code can be properly loaded as a library)")
          load path
        else
          log_info("Requiring #{path} (if this hangs, make sure your code can be properly loaded as a library)")
          require path
        end
      rescue Exception => e
        log_info("Proceeding with postload -- could not load #{path}: #{e} (#{e.class})\n  #{e.backtrace.join("\n  ")}")
      else
        if defined?(einhorn_main)
          log_info("Successfully loaded #{path}")
          Einhorn::TransientState.preloaded = true
        else
          log_info("Proceeding with postload -- loaded #{path}, but no einhorn_main method was defined")
        end
      end
    end
  end

  def self.set_argv(cmd, set_ps_name)
    # TODO: clean up this hack
    idx = 0
    if cmd[0] =~ /(^|\/)ruby$/
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

    ARGV[0..-1] = cmd[idx+1..-1]
    log_info("Set#{set_ps_name ? " $0 = #{$0.inspect}, " : nil} ARGV = #{ARGV.inspect}")
  end

  def self.set_master_ps_name
    $0 = master_ps_name
  end

  def self.master_ps_name
    "einhorn: #{worker_ps_name}"
  end

  def self.worker_ps_name
    Einhorn::State.cmd_name ? "ruby #{Einhorn::State.cmd_name}" : Einhorn::State.orig_cmd.join(' ')
  end

  def self.socketify!(cmd)
    cmd.map! do |arg|
      if arg =~ /^(.*=|)srv:([^:]+):(\d+)((?:,\w+)*)$/
        opt = $1
        host = $2
        port = $3
        flags = $4.split(',').select {|flag| flag.length > 0}.map {|flag| flag.downcase}
        fd = (Einhorn::State.sockets[[host, port]] ||= bind(host, port, flags))
        "#{opt}#{fd}"
      else
        arg
      end
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
      socketify!(Einhorn::State.cmd)
    end

    set_master_ps_name
    preload

    # In the middle of upgrading
    if Einhorn::State.reloading_for_preload_upgrade
      Einhorn::Command.upgrade_workers
      Einhorn::State.reloading_for_preload_upgrade = false
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

require 'einhorn/command'
require 'einhorn/client'
require 'einhorn/event'
require 'einhorn/worker'
require 'einhorn/worker_pool'
require 'einhorn/version'
