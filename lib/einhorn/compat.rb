module Einhorn
  module Compat
    # In Ruby 2.1.0 (and possibly earlier), IO.pipe sets cloexec on
    # the descriptors.
    def self.pipe
      readable, writeable = IO.pipe
      Einhorn::FD.cloexec!(readable, false)
      Einhorn::FD.cloexec!(writeable, false)
      [readable, writeable]
    end

    # Opts are ignored in Ruby 1.8
    def self.exec(script, args, opts={})
      cmd = [script, script]
      begin
        Kernel.exec(cmd, *(args + [opts]))
      rescue TypeError
        Kernel.exec(cmd, *args)
      end
    end

    def self.unixserver_new(path)
      server = UNIXServer.new(path)
      Einhorn::FD.cloexec!(server, false)
      server
    end

    def self.accept_nonblock(server)
      sock = server.accept_nonblock
      Einhorn::FD.cloexec!(sock, false)
      sock
    end

    def self.processor_count
      # jruby
      if defined? Java::Java
        return Java::Java.lang.Runtime.getRuntime.availableProcessors
      end

      # linux / friends
      begin
        return File.read('/proc/cpuinfo').scan(/^processor\s*:/).count
      rescue Errno::ENOENT
      end

      # OS X
      if RUBY_PLATFORM =~ /darwin/
        return Integer(`sysctl -n hw.logicalcpu`)
      end

      # windows / friends
      begin
        require 'win32ole'
      rescue LoadError
      else
        wmi = WIN32OLE.connect("winmgmts://")
        wmi.ExecQuery("select * from Win32_ComputerSystem").each do |system|
          begin
            processors = system.NumberOfLogicalProcessors
          rescue
            processors = 0
          end
          return [system.NumberOfProcessors, processors].max
        end
      end

      raise "Failed to detect number of CPUs"
    end
  end
end
