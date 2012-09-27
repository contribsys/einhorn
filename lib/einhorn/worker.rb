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

    # Call this once your app is up and running in a good state.
    # Arguments:
    #
    # @discovery: How to discover the master process's command socket.
    #   :env:        Discover the path from ENV['EINHORN_SOCK_PATH']
    #   :fd:         Just use the file descriptor in ENV['EINHORN_SOCK_FD'].
    #                Must run the master with the -g flag. This is mostly
    #                useful if you don't have a nice library like Einhorn::Worker.
    #                Then @arg being true causes the FD to be left open after ACK;
    #                otherwise it is closed.
    #   :direct:     Provide the path to the command socket in @arg.
    #
    # TODO: add a :fileno option? Easy to implement; not sure if it'd
    # be useful for anything. Maybe if it's always fd 3, because then
    # the user wouldn't have to provide an arg.
    def self.ack!(discovery=:env, arg=nil)
      ensure_worker!
      close_after_use = true

      case discovery
      when :env
        socket = ENV['EINHORN_SOCK_PATH']
        client = Einhorn::Client.for_path(socket)
      when :fd
        raise "No EINHORN_SOCK_FD provided in environment. Did you run einhorn with the -g flag?" unless fd_str = ENV['EINHORN_SOCK_FD']

        fd = Integer(fd_str)
        client = Einhorn::Client.for_fd(fd)
        close_after_use = false if arg
      when :direct
        socket = arg
        client = Einhorn::Client.for_path(socket)
      else
        raise "Unrecognized socket discovery mechanism: #{discovery.inspect}. Must be one of :filesystem, :argv, or :direct"
      end

      client.command({
          'command' => 'worker:ack',
          'pid' => $$
        })

      client.close if close_after_use
      true
    end

    def self.socket(number=nil)
      number ||= 0
      fds = einhorn_fds
      fds ? fds[number] : nil
    end

    def self.socket!(number=nil)
      number ||= 0

      unless fds = einhorn_fds
        raise "No EINHORN_FDS provided in environment. Are you running under Einhorn?"
      end

      unless number < fds.length
        raise "Only #{fds.length} FDs available, but FD #{number} was requested"
      end

      fds[number]
    end

    def self.einhorn_fds
      unless raw_fds = ENV['EINHORN_FDS']
        return nil
      end

      raw_fds.split(' ').map {|fd| Integer(fd)}
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
