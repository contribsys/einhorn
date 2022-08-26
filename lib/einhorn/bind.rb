require "socket"

module Einhorn::Bind
  class Bind
    attr_reader :flags

    def ==(other)
      other.class == self.class && other.state == state
    end
  end

  class Inet < Bind
    def initialize(host, port, flags)
      @host = host
      @port = port
      @flags = flags
    end

    def state
      [@host, @port, @flags]
    end

    def family
      Socket::AF_INET
    end

    def address
      "#{@host}:#{@port}"
    end

    def make_socket
      sd = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)

      if @flags.include?("r") || @flags.include?("so_reuseaddr")
        sd.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
      end

      sd
    end

    def bind(sock)
      sock.bind(Socket.pack_sockaddr_in(@port, @host))
    end
  end

  class Unix < Bind
    def initialize(path, flags)
      @path = path
      @flags = flags
    end

    def state
      [@path, @flags]
    end

    def family
      Socket::AF_UNIX
    end

    def address
      @path.to_s
    end

    def make_socket
      Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
    end

    def clean_old_unix_socket
      begin
        sock = UNIXSocket.new(@path)
      rescue Errno::ECONNREFUSED
        # This happens with non-socket files and when the listening
        # end of a socket has exited.
      rescue Errno::ENOENT
        # Socket doesn't exist
        return
      else
        # Rats, it's still active
        sock.close
        raise Errno::EADDRINUSE.new("Another process is listening on the UNIX socket at #{@path}. If you'd like to run this Einhorn as well, pass a `-b PATH_TO_SOCKET` to change the socket location.")
      end

      stat = File.stat(@path)
      unless stat.socket?
        raise Errno::EADDRINUSE.new("Non-socket file present at UNIX socket path #{@path}. Either remove that file and restart Einhorn, or pass a different `-b PATH_TO_SOCKET` to change where you are binding.")
      end

      Einhorn.log_info("Blowing away old UNIX socket at #{@path}. This likely indicates a previous Einhorn master which exited uncleanly.")
      File.unlink(@path)
    end

    def bind(sock)
      clean_old_unix_socket
      sock.bind(Socket.pack_sockaddr_un(@path))
    end
  end
end
