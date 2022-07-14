module Einhorn::Event
  class AbstractTextDescriptor
    attr_accessor :read_buffer, :write_buffer
    attr_reader :client_id

    @@instance_counter = 0

    def self.open(sock)
      new(sock)
    end

    def initialize(sock)
      @@instance_counter += 1

      @socket = sock
      @client_id = "#{@@instance_counter}:#{sock.fileno}"

      @read_buffer = ""
      @write_buffer = ""

      @closed = false

      register!
    end

    def close
      @closed = true
      deregister!
      @socket.close
    end

    # API method
    def read(&blk)
      raise "Already registered a read block" if @read_blk
      raise "No block provided" unless blk
      raise "Must provide a block that accepts two arguments" unless blk.arity == 2

      @read_blk = blk
      notify_readable # Read what you can
    end

    def notify_readable
      loop do
        return if @closed
        chunk = @socket.read_nonblock(1024)
      rescue Errno::EAGAIN
        break
      rescue EOFError, Errno::EPIPE, Errno::ECONNRESET
        close
        break
      rescue => e
        log_error("Caught unrecognized error while reading from socket: #{e} (#{e.class})")
        close
        break
      else
        log_debug("read #{chunk.length} bytes (#{chunk.inspect[0..20]})")
        @read_buffer << chunk
        process_read_buffer
      end
    end

    # API method
    def write(data)
      @write_buffer << data
      notify_writeable # Write what you can
    end

    def write_pending?
      @write_buffer.length > 0
    end

    def notify_writeable
      return if @closed
      written = @socket.write_nonblock(@write_buffer)
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
    rescue Errno::EPIPE, Errno::ECONNRESET
      close
    rescue => e
      log_error("Caught unrecognized error while writing to socket: #{e} (#{e.class})")
      close
    else
      log_debug("wrote #{written} bytes")
      @write_buffer = @write_buffer[written..-1]
    end

    def to_io
      @socket
    end

    def register!
      Einhorn::Event.register_readable(self)
      Einhorn::Event.register_writeable(self)
    end

    def deregister!
      Einhorn::Event.deregister_readable(self)
      Einhorn::Event.deregister_writeable(self)
    end

    def process_read_buffer
      loop do
        if @read_buffer.length > 0
          break unless (split = parse_record)
          record, remainder = split
          log_debug("Read a record of #{record.length} bytes.")
          @read_buffer = remainder
          consume_record(record)
        else
          break
        end
      end
    end

    # Override in subclass. This lets you do streaming reads.
    def parse_record
      [@read_buffer, ""]
    end

    def consume_record(record)
      raise NotImplementedError.new
    end

    def log_debug(msg)
      Einhorn.log_debug("[client #{client_id}] #{msg}")
    end

    def log_info(msg)
      Einhorn.log_info("[client #{client_id}] #{msg}")
    end

    def log_error(msg)
      Einhorn.log_error("[client #{client_id}] #{msg}")
    end
  end
end
