module Einhorn
  module FD
    def self.cloexec!(fd, enable)
      fd = io_without_autoclose(fd)
      original = fd.fcntl(Fcntl::F_GETFD)
      if enable
        new = original | Fcntl::FD_CLOEXEC
      else
        new = original & (-Fcntl::FD_CLOEXEC-1)
      end
      fd.fcntl(Fcntl::F_SETFD, new)
    end

    def self.nonblock!(fd, enable)
      fd = io_without_autoclose(fd)
      original = fd.fcntl(Fcntl::F_GETFD)
      if enable
        new = original | Fcntl::O_NONBLOCK
      else
        new = original & (-Fcntl::O_NONBLOCK-1)
      end
      fd.fcntl(Fcntl::F_SETFD, new)
    end

    def self.cloexec?(fd)
      fd.fcntl(Fcntl::F_GETFD) & Fcntl::FD_CLOEXEC
    end

    # Parse flags as specified on the commandline
    def self.parse_flags(flags)
      flags.split(',').
        select {|flag| flag.length > 0}.
        map {|flag| flag.downcase}
    end

    def self.set_flags(fd_num, flags)
      io = io_without_autoclose(fd_num)
      nonblock!(io, flags.include?('n') || flags.include?('o_nonblock'))
    end

    def self.bind(addr, port, flags)
      Einhorn.log_info("Binding to #{addr}:#{port} with flags #{flags.inspect}")
      sd = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      Einhorn::FD.cloexec!(sd, false)

      if flags.include?('r') || flags.include?('so_reuseaddr')
        sd.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
      end

      sd.bind(Socket.pack_sockaddr_in(port, addr))
      sd.listen(Einhorn::State.config[:backlog])

      hold(sd)
      sd.fileno
    end

    def self.to_fileno(file)
      if file.respond_to?(:fileno)
        file.fileno
      else
        file
      end
    end

    # Leaks memory in 1.8 (needed to avoid Ruby 1.8's IO autoclose
    # behavior).
    def self.io_without_autoclose(fd_num)
      if fd_num.respond_to?(:fileno)
        return fd_num
      end

      io = IO.new(fd_num)

      if io.respond_to?(:autoclose)
        io.autoclose = false
      else
        hold(io)
      end
      io
    end

    # Perform a dup2 and also copies over file descriptor flags.
    def self.dup2flags(fildes, fildes2)
      dup2(fildes, fildes2)
      fildes = io_without_autoclose(fildes)
      fildes2 = io_without_autoclose(fildes2)
      fildes2.fcntl(Fcntl::F_SETFD, fildes.fcntl(Fcntl::F_GETFD))
    end

    # It'd be preferable to just shell out to dup2, but looks like
    # we'd need a C extension to do so. Note the concurrency story
    # here is a bit off, and this probably doesn't copy over all FD
    # state properly. But should be fine for now.
    def self.dup2(fildes, fildes2)
      original = io_without_autoclose(fildes)
      if original.fileno == fildes2
        return
      end

      begin
        copy = io_without_autoclose(fildes2)
      rescue Errno::EBADF
      else
        copy.close
      end

      # For some reason, Ruby 1.9 doesn't seem to let you close
      # stdout/sterr. So if we didn't manage to close it above, then
      # just use reopen. We could get rid of the close attempt above,
      # but I'd rather leave this code as close to doing the same
      # thing everywhere as possible.
      begin
        copy = io_without_autoclose(fildes2)
      rescue Errno::EBADF
        res = original.fcntl(Fcntl::F_DUPFD, fildes2)
        if res != fildes2
          raise "Tried to open #{fildes2} but ended up with #{res} instead. This probably indicates a race, where someone else reclaimed #{fildes2}."
        end
      else
        copy.reopen(original)
      end
    end

    private

    @references = []
    def self.hold(*references)
      # Needed for Ruby 1.8, where we can't set IO objects to not
      # close the underlying FD on destruction
      @references += references
    end
  end
end
