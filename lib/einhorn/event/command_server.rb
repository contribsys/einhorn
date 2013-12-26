module Einhorn::Event
  class CommandServer
    include Persistent

    def self.open(server)
      self.new(server)
    end

    def initialize(server)
      @server = server

      @closed = false

      register!
    end

    def notify_readable
      begin
        while true
          return if @closed
          sock = Einhorn::Compat.accept_nonblock(@server)
          Connection.open(sock)
        end
      rescue Errno::EAGAIN
      end
    end

    def to_io
      @server
    end

    def to_state
      {:class => self.class.to_s, :server => @server.fileno}
    end

    def self.from_state(state)
      fd = state[:server]
      socket = UNIXServer.for_fd(fd)
      self.open(socket)
    end

    def close
      @closed = true
      deregister!
      @server.close
    end

    def register!
      Einhorn::Command::Interface.command_server = self
      Einhorn::Event.register_readable(self)
    end

    def deregister!
      Einhorn::Command::Interface.command_server = nil
      Einhorn::Event.deregister_readable(self)
    end
  end
end
