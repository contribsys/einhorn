require 'einhorn/client'
require 'einhorn/command/interface'

module Einhorn
  module Worker
    class WorkerError < RuntimeError; end

    def self.is_worker?
      begin
        ensure_worker!
      rescue WorkerError
        false
      else
        true
      end
    end

    def self.ensure_worker!
      # Make sure that EINHORN_MASTER_PID is my parent
      if ppid_s = ENV['EINHORN_MASTER_PID']
        ppid = ppid_s.to_i
        raise WorkerError.new("EINHORN_MASTER_PID environment variable is #{ppid_s.inspect}, but my parent's pid is #{Process.ppid.inspect}. This probably means that I am a subprocess of an Einhorn worker, but am not one myself.") unless Process.ppid == ppid
        true
      else
        raise WorkerError.new("No EINHORN_MASTER_PID environment variable set. Are you running your process under Einhorn?") unless Process.ppid == ppid
      end
    end

    def self.ack(*args)
      begin
        ack!(*args)
      rescue WorkerError
      end
    end

    def self.send_state(state)
      unless @client
        raise "No client set; Did you call 'ack'?"
      end
      @client.command({
        'command' => 'worker:state',
        'pid'     => $$,
        'state'   => state
      })
    end

    # Call this once your app is up and running in a good state.
    # Arguments:
    #
    # @discovery: How to discover the master process's command socket.
    #   :env:        Discover the path from ENV['EINHORN_SOCK_PATH']
    #   :fd:         Just use the file descriptor in ENV['EINHORN_SOCK_FD'].
    #                Must run the master with the -g flag. This is mostly
    #                useful if you don't have a nice library like Einhorn::Worker.
    #   :direct:     Provide the path to the command socket in @options.
    #
    # Accepts the following options in @options:
    #
    #   :keep_open:  If true, keep the command socket open to send further
    #                commands to the einhorn master.
    #   :path        With @discovery == :direct, the socket path to use.
    #
    # TODO: add a :fileno option? Easy to implement; not sure if it'd
    # be useful for anything. Maybe if it's always fd 3, because then
    # the user wouldn't have to provide an arg.
    def self.ack!(discovery=:env, options=nil)
      ensure_worker!

      if options && !options.is_a?(Hash)
        if discover == :fd
          options = {:keep_open => options}
        elsif discover == :direct
          options = {:path => options}
        end
      end

      case discovery
      when :env
        socket = ENV['EINHORN_SOCK_PATH']
        client = Einhorn::Client.for_path(socket)
      when :fd
        raise "No EINHORN_SOCK_FD provided in environment. Did you run einhorn with the -g flag?" unless fd_str = ENV['EINHORN_SOCK_FD']

        fd = Integer(fd_str)
        client = Einhorn::Client.for_fd(fd)
      when :direct
        socket = options[:path]
        raise ":direct discover specified, but no path given in #{options.inspect}" unless socket
        client = Einhorn::Client.for_path(socket)
      else
        raise "Unrecognized socket discovery mechanism: #{discovery.inspect}. Must be one of :filesystem, :argv, or :direct"
      end

      client.command({
        'command' => 'worker:ack',
        'pid' => $$,
        'keep-open' => options[:keep_open]
      })

      if options[:keep_open]
        @client = client
      else
        client.close
      end
      true
    end

    def self.socket(number=nil)
      number ||= 0
      einhorn_fd(number)
    end

    def self.socket!(number=nil)
      number ||= 0

      unless count = einhorn_fd_count
        raise "No EINHORN_FD_COUNT provided in environment. Are you running under Einhorn?"
      end

      unless number < count
        raise "Only #{count} FDs available, but FD #{number} was requested"
      end

      unless fd = einhorn_fd(number)
        raise "No EINHORN_FD_#{number} provided in environment. That's pretty weird"
      end

      fd
    end

    def self.einhorn_fd(n)
      unless raw_fd = ENV["EINHORN_FD_#{n}"]
        return nil
      end
      Integer(raw_fd)
    end

    def self.einhorn_fd_count
      unless raw_count = ENV['EINHORN_FD_COUNT']
        return 0
      end
      Integer(raw_count)
    end

    # Call this to handle graceful shutdown requests to your app.
    def self.graceful_shutdown(&blk)
      Signal.trap('USR2', &blk)
    end

    private

    def self.socket_from_filesystem(cmd_name)
      ppid = Process.ppid
      socket_path_file = Einhorn::Command::Interface.socket_path_file(ppid)
      File.read(socket_path_file)
    end
  end
end
