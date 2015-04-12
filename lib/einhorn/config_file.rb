require 'yaml'

module Einhorn
  class ConfigFile
    def self.check_config_file!
      return unless (config = load_config!)
      annotate_error('the top-level') do
        assert_keys(config, %w{bind})
      end

      config['bind'].each_with_index do |bind, i|
        annotate_error("at index #{i} under binds") do
          assert_keys(config, %w{addr port flags fd}, where)
          assert_type(config, 'addr', String)
          assert_type(config, 'port', Integer)
          assert_type(config, 'flags', Array) if config['flags']
          assert_type(config, 'fd', Integer) if config['fd']
        end
      end
    end

    def self.assert_type(hash, key, expected)
      value = hash[key]
      if !value.kind_of?(expected)
        raise "Expected #{key} to be of type #{expected}, not #{value.class} (#{value.inspect})"
      end
    end

    def self.assert_keys(hash, allowed_keys)
      if !hash.kind_of?(Hash)
        raise "Expected a Hash, but got a #{hash.class} (#{hash.inspect}"
      end

      extra = hash.keys - allowed_keys
      if extra.length > 0
        raise "Unrecognized keys: #{extra.inspect}"
      end
    end

    def self.annotate_error(where, &blk)
      begin
        blk.call
      rescue => e
        e.message[0...-1] = "Config check failed: #{e.message} (#{where})"
      end
    end

    # Loads and applies the config in the specified config file.
    def self.apply_config_file!
      return unless (config = load_config!)
      apply_binds(config)
    end

    def self.apply_binds(config)
      current = {}
      Einhorn::State.bind.zip(Einhorn::State.bind_fds).each do |(addr, port, flags), fd|
        current[[addr, port]] = {:fd => fd, :flags => flags}
      end

      desired = {}
      config.fetch('bind', {}).each do |bind|
        addr = bind.fetch('addr')
        port = bind.fetch('port')
        flags = bind.fetch('flags')
        fd = bind.fetch('fd', nil)

        # No need to parse flags, as they should be an array already
        desired[[addr, port]] = {:fd => fd, :flags => flags}
      end

      (current.keys + desired.keys).uniq.each do |addr, port|
        config = current[[addr, port]]
        desired_config = desired[[addr, port]]
        apply_bind(addr, port, config, desired_config, current)
      end

      # Convert everything back into Einhorn internal state
      bind_fds = []
      bind = desired.map do |(addr, port), conf|
        bind_fds << conf[:fd]
        [addr, port, conf[:flags]]
      end
      Einhorn::State.bind = bind
      Einhorn::State.bind_fds = bind_fds
    end

    def self.apply_bind(addr, port, config, desired_config, current)
      if !desired_config
        # No one wants this addr/port anymore, let's shut it down!
        fd = config[:fd]
        Einhorn.log_info("Closing fd for #{addr}:#{port} (#{fd})")
        IO.new(fd).close
        return
      end

      # Make sure that the desired FD is available
      desired_config[:fd] ||= config[:fd]
      desired_fd = desired_config[:fd]
      desired_flags = desired_config[:flags]

      # Check on whether anyone's squatting on our FD
      holder_addr, holder_conf = current.detect {|k, conf| conf[:fd] == desired_fd}
      if holder_addr && holder_addr == [addr, port]
        # No binding needed here
      elsif holder_addr
        # Someone else is occupying this FD. Need to dup their FD and
        # clear up the current slot.
        holder_io = IO.new(desired_fd)

        fd2 = holder_io.fcntl(Fcntl::F_DUPFD)
        Einhorn.log_info("Clearing room for #{addr}:#{port} by renumbering fd for #{holder_addr.join(':')} from #{desired_fd} -> #{fd2}")

        # Force it closed since Ruby 1.8 would do an autoclose
        # anyway, and we can close it out for now.
        holder_io.close
        holder_conf[:fd] = fd2
      end

      if !config
        # Open up our own fresh file descriptor, since the desired one
        # must now be free.
        actual_fd = Einhorn::FD.bind(addr, port, desired_flags)
        # This is the only case where we might change the value of
        # desired_config[:fd], so we can't use desired_fd here.
        desired_config[:fd] ||= actual_fd
        if actual_fd != desired_config[:fd]
          Einhorn::FD.dup2flags(actual_fd, desired_config[:fd])
          IO.new(actual_fd).close
        end
        return
      end

      # Check on whether we need to change our existing FD number
      if config && (current_fd = config[:fd]) != desired_fd
        Einhorn.log_info("Renumbering #{addr}:#{port} from #{current_fd} -> #{desired_fd}")

        # Actually renumber to the current value if needed
        current_io = IO.new(current_fd)
        Einhorn::FD.dup2flags(current_io, desired_fd)
        current_io.close
        config[:fd] = desired_fd
      end

      # Check on whether we need to change our existing flags
      if config && config[:flags] != desired_flags
        Einhorn.log_info("Changing flags on #{addr}:#{port} (#{desired_fd}) from #{config[:flags]} to #{desired_flags}")

        Einhorn::FD.set_flags(desired_fd, desired_flags)
      end
    end

    def self.load_config!
      return unless (file = Einhorn::State.config_file)
      load!(file)
    end

    def self.load!(filepath)
      es = []
      begin
        es << Psych::BadAlias
      rescue NameError
      end

      begin
        loaded = YAML.load_file(filepath)
      rescue *es => e
        # YAML parse-time errors include the filepath already, but
        # load-time errors do not.
        #
        # Specifically, `Psych::BadAlias` (raised by doing something
        # like `YAML.load('foo: *bar')`) does not:
        # https://github.com/tenderlove/psych/issues/192
        e.message << " (while loading #{filepath})"
        raise
      end
      unless loaded.is_a?(Hash)
        raise Error.new("YAML.load(#{filepath.inspect}) parses into a #{loaded.class}, not a Hash")
      end
      loaded
    end
  end
end
