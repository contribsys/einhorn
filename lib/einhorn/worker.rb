require "einhorn/client"
require "einhorn/command/interface"

module Einhorn
  module Worker
    class WorkerError < RuntimeError; end

    def self.is_worker?
      ensure_worker!
    rescue WorkerError
      false
    else
      true
    end

    def self.ensure_worker!
      # Make sure that EINHORN_MASTER_PID is my parent
      if (ppid_s = ENV["EINHORN_MASTER_PID"])
        ppid = ppid_s.to_i
        raise WorkerError.new("EINHORN_MASTER_PID environment variable is #{ppid_s.inspect}, but my parent's pid is #{Process.ppid.inspect}. This probably means that I am a subprocess of an Einhorn worker, but am not one myself.") unless Process.ppid == ppid
        true
      else
        raise WorkerError.new("No EINHORN_MASTER_PID environment variable set. Are you running your process under Einhorn?") unless Process.ppid == ppid
      end
    end

    def self.ack(*args)
      ack!(*args)
    rescue WorkerError
    end

    # Returns the index of this Einhorn child process.
    #
    # If an Einhorn master has N children, this will be an integer in
    # the range [0,N), and no two workers running concurrently will
    # ever have the same index.
    #
    # Returns nil if not running in Einhorn, or running on a version
    # of Einhorn that does not support indexing children.
    def self.einhorn_child_index
      index = ENV["EINHORN_CHILD_INDEX"]
      if index.nil? || index !~ /\A \d+ \z/x
        index
      else
        index.to_i
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
    def self.ack!(discovery = :env, arg = nil)
      handle_command_socket(discovery, arg) do |client|
        client.send_command("command" => "worker:ack", "pid" => $$)
      end
    end

    # Call this to indicate your child process is up and in a healthy state.
    # Arguments:
    #
    # @request_id: Identifies the request ID of the worker, can be used to debug wedged workers.
    #
    # @discovery: How to discover the master process's command socket.
    #   :env:        Discover the path from ENV['EINHORN_SOCK_PATH']
    #   :fd:         Just use the file descriptor in ENV['EINHORN_SOCK_FD'].
    #                Must run the master with the -g flag. This is mostly
    #                useful if you don't have a nice library like Einhorn::Worker.
    #                Then @arg being true causes the FD to be left open after ACK;
    #                otherwise it is closed.
    #   :direct:     Provide the path to the command socket in @arg.
    def self.ping!(request_id, discovery = :env, arg = nil)
      handle_command_socket(discovery, arg) do |client|
        client.send_command("command" => "worker:ping", "pid" => $$, "request_id" => request_id)
      end
    end

    def self.socket(number = nil)
      number ||= 0
      einhorn_fd(number)
    end

    def self.socket!(number = nil)
      number ||= 0

      unless (count = einhorn_fd_count)
        raise "No EINHORN_FD_COUNT provided in environment. Are you running under Einhorn?"
      end

      unless number < count
        raise "Only #{count} FDs available, but FD #{number} was requested"
      end

      unless (fd = einhorn_fd(number))
        raise "No EINHORN_FD_#{number} provided in environment. That's pretty weird"
      end

      fd
    end

    def self.einhorn_fd(n)
      unless (raw_fd = ENV["EINHORN_FD_#{n}"])
        return nil
      end
      Integer(raw_fd)
    end

    def self.einhorn_fd_count
      unless (raw_count = ENV["EINHORN_FD_COUNT"])
        return 0
      end
      Integer(raw_count)
    end

    # Call this to handle graceful shutdown requests to your app.
    def self.graceful_shutdown(&blk)
      Signal.trap("USR2", &blk)
    end

    def self.handle_command_socket(discovery, contextual_arg)
      ensure_worker!
      close_after_use = true

      case discovery
      when :env
        socket = ENV["EINHORN_SOCK_PATH"]
        client = Einhorn::Client.for_path(socket)
      when :fd
        raise "No EINHORN_SOCK_FD provided in environment. Did you run einhorn with the -g flag?" unless (fd_str = ENV["EINHORN_SOCK_FD"])

        fd = Integer(fd_str)
        client = Einhorn::Client.for_fd(fd)
        close_after_use = false if contextual_arg
      when :direct
        socket = contextual_arg
        client = Einhorn::Client.for_path(socket)
      else
        raise "Unrecognized socket discovery mechanism: #{discovery.inspect}. Must be one of :filesystem, :argv, or :direct"
      end

      yield client
      client.close if close_after_use

      true
    end
    private_class_method :handle_command_socket

    def self.socket_from_filesystem(cmd_name)
      ppid = Process.ppid
      socket_path_file = Einhorn::Command::Interface.socket_path_file(ppid)
      File.read(socket_path_file)
    end
    private_class_method :socket_from_filesystem
  end
end
