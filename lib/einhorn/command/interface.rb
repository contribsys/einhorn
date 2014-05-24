require 'tmpdir'
require 'socket'

module Einhorn::Command
  module Interface
    @@commands = {}
    @@command_server = nil

    def self.command_server=(server)
      raise "Command server already set" if @@command_server && server
      @@command_server = server
    end

    def self.command_server
      @@command_server
    end

    def self.init
      install_handlers
      at_exit do
        if Einhorn::TransientState.whatami == :master
          to_remove = [pidfile]
          # Don't nuke socket_path if we never successfully acquired it
          to_remove << socket_path if @@command_server
          to_remove.each do |file|
            begin
              File.unlink(file)
            rescue Errno::ENOENT
            end
          end
        end
      end
    end

    def self.persistent_init
      socket = open_command_socket
      Einhorn::Event::CommandServer.open(socket)

      # Could also rewrite this on reload. Might be useful in case
      # someone goes and accidentally clobbers/deletes. Should make
      # sure that the clobber is atomic if we we were do do that.
      write_pidfile
    end

    def self.open_command_socket
      path = socket_path

      with_file_lock do
        # Need to avoid time-of-check to time-of-use bugs in blowing
        # away and recreating the old socketfile.
        destroy_old_command_socket(path)
        Einhorn::Compat.unixserver_new(path)
      end
    end

    # Lock against other Einhorn workers. Unfortunately, have to leave
    # this lockfile lying around forever.
    def self.with_file_lock(&blk)
      path = lockfile
      File.open(path, 'w', 0600) do |f|
        unless f.flock(File::LOCK_EX|File::LOCK_NB)
          raise "File lock already acquired by another Einhorn process. This likely indicates you tried to run Einhorn masters with the same cmd_name at the same time. This is a pretty rare race condition."
        end

        blk.call
      end
    end

    def self.destroy_old_command_socket(path)
      # Socket isn't actually owned by anyone
      begin
        sock = UNIXSocket.new(path)
      rescue Errno::ECONNREFUSED
        # This happens with non-socket files and when the listening
        # end of a socket has exited.
      rescue Errno::ENOENT
        # Socket doesn't exist
        return
      else
        # Rats, it's still active
        sock.close
        raise Errno::EADDRINUSE.new("Another process (probably another Einhorn) is listening on the Einhorn command socket at #{path}. If you'd like to run this Einhorn as well, pass a `-d PATH_TO_SOCKET` to change the command socket location.")
      end

      # Socket should still exist, so don't need to handle error.
      stat = File.stat(path)
      unless stat.socket?
        raise Errno::EADDRINUSE.new("Non-socket file present at Einhorn command socket path #{path}. Either remove that file and restart Einhorn, or pass a `-d PATH_TO_SOCKET` to change the command socket location.")
      end

      Einhorn.log_info("Blowing away old Einhorn command socket at #{path}. This likely indicates a previous Einhorn master which exited uncleanly.")
      # Whee, blow it away.
      File.unlink(path)
    end

    def self.write_pidfile
      file = pidfile
      Einhorn.log_info("Writing PID to #{file}")
      File.open(file, 'w') {|f| f.write($$)}
    end

    def self.uninit
      remove_handlers
    end

    def self.socket_path
      Einhorn::State.socket_path || default_socket_path
    end

    def self.default_socket_path(cmd_name=nil)
      cmd_name ||= Einhorn::State.cmd_name
      if cmd_name
        filename = "einhorn-#{cmd_name}.sock"
      else
        filename = "einhorn.sock"
      end
      File.join(Dir.tmpdir, filename)
    end

    def self.lockfile
      Einhorn::State.lockfile || default_lockfile_path
    end

    def self.default_lockfile_path(cmd_name=nil)
      cmd_name ||= Einhorn::State.cmd_name
      if cmd_name
        filename = "einhorn-#{cmd_name}.lock"
      else
        filename = "einhorn.lock"
      end
      File.join(Dir.tmpdir, filename)
    end

    def self.pidfile
      Einhorn::State.pidfile || default_pidfile
    end

    def self.default_pidfile(cmd_name=nil)
      cmd_name ||= Einhorn::State.cmd_name
      if cmd_name
        filename = "einhorn-#{cmd_name}.pid"
      else
        filename = "einhorn.pid"
      end
      File.join(Dir.tmpdir, filename)
    end

    ## Signals
    def self.install_handlers
      trap_async("INT") do
        Einhorn::Command.signal_all("USR2", Einhorn::WorkerPool.workers)
        Einhorn::Command.stop_respawning
      end
      trap_async("TERM") do
        Einhorn::Command.signal_all("TERM", Einhorn::WorkerPool.workers)
        Einhorn::Command.stop_respawning
      end
      # Note that quit is a bit different, in that it will actually
      # make Einhorn quit without waiting for children to exit.
      trap_async("QUIT") do
        Einhorn::Command.signal_all("QUIT", Einhorn::WorkerPool.workers)
        Einhorn::Command.stop_respawning
        exit(1)
      end
      trap_async("HUP") {Einhorn::Command.full_upgrade_smooth}
      trap_async("ALRM") do
        Einhorn.log_error("Upgrading using SIGALRM is deprecated. Please switch to SIGHUP")
        Einhorn::Command.full_upgrade_smooth
      end
      trap_async("CHLD") {}
      trap_async("USR2") do
        Einhorn::Command.signal_all("USR2", Einhorn::WorkerPool.workers)
        Einhorn::Command.stop_respawning
      end
      at_exit do
        if Einhorn::State.kill_children_on_exit && Einhorn::TransientState.whatami == :master
          Einhorn::Command.signal_all("USR2", Einhorn::WorkerPool.workers)
          Einhorn::Command.stop_respawning
        end
      end
    end

    def self.trap_async(signal, &blk)
      Signal.trap(signal) do
        # We try to do as little work in the signal handler as
        # possible. This avoids potential races between e.g. iteration
        # and mutation.
        Einhorn::Event.break_loop
        Einhorn::Event.register_signal_action(&blk)
      end
    end

    def self.remove_handlers
      %w{INT TERM QUIT HUP ALRM CHLD USR2}.each do |signal|
        Signal.trap(signal, "DEFAULT")
      end
    end

    ## Commands
    def self.command(name, description=nil, &code)
      @@commands[name] = {:description => description, :code => code}
    end

    def self.process_command(conn, command)
      begin
        request = Einhorn::Client::Transport.deserialize_message(command)
      rescue Einhorn::Client::Transport::ParseError
      end
      unless request.kind_of?(Hash)
        send_message(conn, "Could not parse command")
        return
      end

      message = generate_message(conn, request)
      if !message.nil?
        send_message(conn, message, request['id'], true)
      else
        conn.log_debug("Got back nil response, so not responding to command.")
      end
    end

    def self.send_tagged_message(tag, message, last=false)
      Einhorn::Event.connections.each do |conn|
        if id = conn.subscription(tag)
          self.send_message(conn, message, id, last)
          conn.unsubscribe(tag) if last
        end
      end
    end

    def self.send_message(conn, message, request_id=nil, last=false)
      if request_id
        response = {'message' => message, 'request_id' => request_id }
        response['wait'] = true unless last
      else
        # support old-style protocol
        response = {'message' => message}
      end
      Einhorn::Client::Transport.send_message(conn, response)
    end

    def self.generate_message(conn, request)
      unless command_name = request['command']
        return 'No "command" parameter provided; not sure what you want me to do.'
      end

      if command_spec = @@commands[command_name]
        conn.log_debug("Received command: #{request.inspect}")
        begin
          return command_spec[:code].call(conn, request)
        rescue StandardError => e
          msg = "Error while processing command #{command_name.inspect}: #{e} (#{e.class})\n  #{e.backtrace.join("\n  ")}"
          conn.log_error(msg)
          return msg
        end
      else
        conn.log_debug("Received unrecognized command: #{request.inspect}")
        return unrecognized_command(conn, request)
      end
    end

    def self.command_descriptions
      command_specs = @@commands.select do |_, spec|
        spec[:description]
      end.sort_by {|name, _| name}

      command_specs.map do |name, spec|
        "#{name}: #{spec[:description]}"
      end.join("\n")
    end

    def self.unrecognized_command(conn, request)
      <<EOF
Unrecognized command: #{request['command'].inspect}

#{command_descriptions}
EOF
    end

    # Used by workers
    command 'worker:ack' do |conn, request|
      if pid = request['pid']
        Einhorn::Command.register_manual_ack(pid)
      else
        conn.log_error("Invalid request (no pid): #{request.inspect}")
      end
      # Throw away this connection in case the application forgets to
      conn.close
      nil
    end

    # Used by einhornsh
    command 'ehlo' do |conn, request|
      <<EOF
Welcome, #{request['user']}! You are speaking to Einhorn Master Process #{$$}#{Einhorn::State.cmd_name ? " (#{Einhorn::State.cmd_name})" : ''}.
This is Einhorn #{Einhorn::VERSION}.
EOF
    end

    command 'help', 'Print out available commands' do
"You are speaking to the Einhorn command socket. You can run the following commands:

#{command_descriptions}
"
    end

    command 'state', "Get a dump of Einhorn's current state" do
      YAML.dump(Einhorn::Command.dumpable_state)
    end

    command 'reload', 'Reload Einhorn' do |conn, request|
      # TODO: make reload actually work (command socket reopening is
      # an issue). Would also be nice if user got a confirmation that
      # the reload completed, though that's not strictly necessary.

      # In the normal case, this will do a write
      # synchronously. Otherwise, the bytes will be stuck into the
      # buffer and lost upon reload.
      send_message(conn, 'Reloading, as commanded', request['id'], true)
      Einhorn::Command.reload
    end

    command 'inc', 'Increment the number of Einhorn child processes' do
      Einhorn::Command.increment
    end

    command 'dec', 'Decrement the number of Einhorn child processes' do
      Einhorn::Command.decrement
    end

    command 'set_workers', 'Set the number of Einhorn child processes' do |conn, request|
      args = request['args']
      if message = validate_args(args)
        next message
      end

      count = args[0].to_i
      if count < 1 || count > 100
        # sancheck. 100 is kinda arbitrary.
        next "Invalid count: '#{args[0]}'. Must be an integer in [1,100)."
      end

      Einhorn::Command.set_workers(count)
    end

    command 'quieter', 'Decrease verbosity' do
      Einhorn::Command.quieter
    end

    command 'louder', 'Increase verbosity' do
      Einhorn::Command.louder
    end

    command 'upgrade', 'Upgrade all Einhorn workers smoothly. This causes Einhorn to reload its own code as well.' do |conn, request|
      # send first message directly for old clients that don't support request
      # ids or subscriptions. Everything else is sent tagged with request id
      # for new clients.
      send_message(conn, 'Upgrading smoothly, as commanded', request['id'])
      conn.subscribe(:upgrade, request['id'])
      # If the app is preloaded this doesn't return.
      Einhorn::Command.full_upgrade_smooth
      nil
    end

    command 'upgrade_fleet', 'Upgrade all Einhorn workers a fleet at a time. This causes Einhorn to reload its own code as well.' do |conn, request|
      # send first message directly for old clients that don't support request
      # ids or subscriptions. Everything else is sent tagged with request id
      # for new clients.
      send_message(conn, 'Upgrading fleet, as commanded', request['id'])
      conn.subscribe(:upgrade, request['id'])
      # If the app is preloaded this doesn't return.
      Einhorn::Command.full_upgrade_fleet
      nil
    end

    command 'signal', 'Send one or more signals to all workers (args: SIG1 [SIG2 ...])' do |conn, request|
      args = request['args']
      if message = validate_args(args)
        next message
      end

      args = normalize_signals(args)

      if message = validate_signals(args)
        next message
      end

      results = args.map do |signal|
        Einhorn::Command.signal_all(signal, nil, false)
      end

      results.join("\n")
    end

    command 'die', 'Send SIGNAL (default: SIGUSR2) to all workers, stop spawning new ones, and exit once all workers die (args: [SIGNAL])' do |conn, request|
      # TODO: dedup this code with signal
      args = request['args']
      if message = validate_args(args)
        next message
      end

      args = normalize_signals(args)

      if message = validate_signals(args)
        next message
      end

      signal = args[0] || "USR2"

      response = Einhorn::Command.signal_all(signal, Einhorn::WorkerPool.workers)
      Einhorn::Command.stop_respawning

      "Einhorn is going down! #{response}"
    end

    command 'config', 'Merge in a new set of config options. (Note: this will likely be subsumed by config file reloading at some point.)' do |conn, request|
      args = request['args']
      if message = validate_args(args)
        next message
      end

      unless args.length > 0
        next 'Must pass in a YAML-encoded hash'
      end

      begin
        # We do the joining so people don't need to worry about quoting
        parsed = YAML.load(args.join(' '))
      rescue ArgumentError => e
        next 'Could not parse argument. Must be a YAML-encoded hash'
      end

      unless parsed.kind_of?(Hash)
        next "Parsed argument is a #{parsed.class}, not a hash"
      end

      Einhorn::State.state.merge!(parsed)

      "Successfully merged in config: #{parsed.inspect}"
    end

    def self.validate_args(args)
      return 'No args provided' unless args
      return 'Args must be an array' unless args.kind_of?(Array)

      args.each do |arg|
        return "Argument is a #{arg.class}, not a string: #{arg.inspect}" unless arg.kind_of?(String)
      end

      nil
    end

    def self.validate_signals(args)
      args.each do |signal|
        unless Signal.list.include?(signal)
          return "Invalid signal: #{signal.inspect}"
        end
      end

      nil
    end

    def self.normalize_signals(args)
      args.map do |signal|
        signal = signal.upcase
        signal = $1 if signal =~ /\ASIG(.*)\Z/
        signal
      end
    end
  end
end
