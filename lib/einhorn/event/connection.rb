module Einhorn::Event
  class Connection < AbstractTextDescriptor
    include Persistent

    def parse_record
      split = @read_buffer.split("\n", 2)
      if split.length > 1
        split
      else
        nil
      end
    end

    def consume_record(command)
      Einhorn::Command::Interface.process_command(self, command)
    end

    def to_state
      state = {:class => self.class.to_s, :socket => @socket.fileno}
      # Don't include by default because it's not that pretty
      state[:read_buffer] = @read_buffer if @read_buffer.length > 0
      state[:write_buffer] = @write_buffer if @write_buffer.length > 0
      state
    end

    def self.from_state(state)
      fd = state[:socket]
      socket = Socket.for_fd(fd)
      conn = self.open(socket)
      conn.read_buffer = state[:read_buffer] if state[:read_buffer]
      conn.write_buffer = state[:write_buffer] if state[:write_buffer]
      conn
    end

    def register!
      log_info("client connected")
      super
    end

    def deregister!
      log_info("client disconnected") if Einhorn::TransientState.whatami == :master
      super
    end
  end
end
