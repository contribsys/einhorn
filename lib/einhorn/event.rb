require 'set'

module Einhorn
  module Event
    @@loopbreak_reader = nil
    @@loopbreak_writer = nil
    @@readable = {}
    @@writeable = {}
    @@timers = {}

    def self.cloexec!(fd)
      fd.fcntl(Fcntl::F_SETFD, fd.fcntl(Fcntl::F_GETFD) | Fcntl::FD_CLOEXEC)
    end

    def self.init
      readable, writeable = IO.pipe
      @@loopbreak_reader = LoopBreaker.open(readable)
      @@loopbreak_writer = writeable

      cloexec!(readable)
      cloexec!(writeable)
    end

    def self.close_all
      @@loopbreak_reader.close
      @@loopbreak_writer.close
      (@@readable.values + @@writeable.values).each do |descriptors|
        descriptors.each do |descriptor|
          descriptor.close
        end
      end
    end

    def self.close_all_for_worker
      close_all
    end

    def self.persistent_descriptors
      descriptor_sets = @@readable.values + @@writeable.values + @@timers.values
      descriptors = descriptor_sets.inject {|a, b| a | b}
      descriptors.select {|descriptor| Einhorn::Event::Persistent.persistent?(descriptor)}
    end

    def self.restore_persistent_descriptors(persistent_descriptors)
      persistent_descriptors.each do |descriptor_state|
        Einhorn::Event::Persistent.from_state(descriptor_state)
      end
    end

    def self.register_readable(reader)
      @@readable[reader.to_io] ||= Set.new
      @@readable[reader.to_io] << reader
    end

    def self.deregister_readable(reader)
      readers = @@readable[reader.to_io]
      readers.delete(reader)
      @@readable.delete(reader.to_io) if readers.length == 0
    end

    def self.readable_fds
      readers = @@readable.keys
      Einhorn.log_debug("Readable fds are #{readers.inspect}")
      readers
    end

    def self.register_writeable(writer)
      @@writeable[writer.to_io] ||= Set.new
      @@writeable[writer.to_io] << writer
    end

    def self.deregister_writeable(writer)
      writers = @@writeable[writer.to_io]
      writers.delete(writer)
      @@readable.delete(writer.to_io) if writers.length == 0
    end

    def self.writeable_fds
      writers = @@writeable.select do |io, writers|
        writers.any? {|writer| writer.write_pending?}
      end.map {|io, writers| io}
      Einhorn.log_debug("Writeable fds are #{writers.inspect}")
      writers
    end

    def self.register_timer(timer)
      @@timers[timer.expires_at] ||= Set.new
      @@timers[timer.expires_at] << timer
    end

    def self.deregister_timer(timer)
      timers = @@timers[timer.expires_at]
      timers.delete(timer)
      @@timers.delete(timer.expires_at) if timers.length == 0
    end

    def self.loop_once
      run_selectables
      run_timers
    end

    def self.timeout
      # (expires_at of the next timer) - now
      if expires_at = @@timers.keys.sort[0]
        expires_at - Time.now
      else
        nil
      end
    end

    def self.run_selectables
      time = timeout
      Einhorn.log_debug("Loop timeout is #{time.inspect}")
      # Time's already up
      return if time && time < 0

      readable, writeable, _ = IO.select(readable_fds, writeable_fds, nil, time)
      (readable || []).each do |io|
        @@readable[io].each {|reader| reader.notify_readable}
      end

      (writeable || []).each do |io|
        @@writeable[io].each {|writer| writer.notify_writeable}
      end
    end

    def self.run_timers
      @@timers.select {|expires_at, _| expires_at <= Time.now}.each do |expires_at, timers|
        # Going to be modifying the set, so let's dup it.
        timers.dup.each {|timer| timer.ring!}
      end
    end

    def self.break_loop
      Einhorn.log_debug("Breaking the loop")
      begin
        @@loopbreak_writer.write_nonblock('a')
      rescue Errno::EWOULDBLOCK, Errno::EAGAIN
        Einhorn.log_error("Loop break pipe is full -- probably means that we are quite backlogged")
      end
    end
  end
end

require 'einhorn/event/persistent'
require 'einhorn/event/timer'

require 'einhorn/event/abstract_text_descriptor'
require 'einhorn/event/ack_timer'
require 'einhorn/event/command_server'
require 'einhorn/event/connection'
require 'einhorn/event/loop_breaker'
