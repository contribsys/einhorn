module Einhorn::Event
  class Connection < AbstractTextDescriptor
    include Persistent

    def initialize(*args)
      @subscriptions = {}
      super
    end

    def parse_record
      split = @read_buffer.split("\n", 2)
      if split.length > 1
        split
      end
    end

    def consume_record(command)
      Einhorn::Command::Interface.process_command(self, command)
    end

    def to_state
      state = {class: self.class.to_s, socket: @socket.fileno}
      # Don't include by default because it's not that pretty
      state[:read_buffer] = @read_buffer if @read_buffer.length > 0
      state[:write_buffer] = @write_buffer if @write_buffer.length > 0
      state[:subscriptions] = @subscriptions
      state
    end

    def self.from_state(state)
      fd = state[:socket]
      socket = Socket.for_fd(fd)
      conn = self.open(socket)
      conn.read_buffer = state[:read_buffer] if state[:read_buffer]
      conn.write_buffer = state[:write_buffer] if state[:write_buffer]
      # subscriptions could be empty if upgrading from an older version of einhorn
      state.fetch(:subscriptions, {}).each do |tag, id|
        conn.subscribe(tag, id)
      end
      conn
    end

    def subscribe(tag, request_id)
      if request_id
        @subscriptions[tag] = request_id
      end
    end

    def subscription(tag)
      @subscriptions[tag]
    end

    def unsubscribe(tag)
      @subscriptions.delete(tag)
    end

    def register!
      log_debug("client connected")
      Einhorn::Event.register_connection(self, @socket.fileno)
      super
    end

    def deregister!
      log_debug("client disconnected") if Einhorn::TransientState.whatami == :master
      Einhorn::Event.deregister_connection(@socket.fileno)
      super
    end
  end
end
