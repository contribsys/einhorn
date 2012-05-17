require File.expand_path(File.join(File.dirname(__FILE__), '../../test_helper'))

require 'set'
require 'einhorn'

module Einhorn::Event
  def self.reset
    @@loopbreak_reader = nil
    @@loopbreak_writer = nil
    @@readable = {}
    @@writeable = {}
    @@timers = {}
  end
end

class EventTest < Test::Unit::TestCase
  context "when run the event loop" do
    setup do
      Einhorn::Event.reset
    end

    teardown do
      Einhorn::Event.reset
    end

    should "select on readable descriptors" do
      sock1 = mock(:fileno => 4)
      sock2 = mock(:fileno => 5)

      conn1 = Einhorn::Event::Connection.open(sock1)
      conn2 = Einhorn::Event::Connection.open(sock2)

      IO.expects(:select).once.with do |readers, writers, errs, timeout|
        Set.new(readers) == Set.new([sock1, sock2]) &&
          writers == [] &&
          errs == nil &&
          timeout == nil
      end.returns([[], [], []])

      Einhorn::Event.loop_once
    end

    should "select on writeable descriptors" do
      sock1 = mock(:fileno => 4)
      sock2 = mock(:fileno => 5)

      conn1 = Einhorn::Event::Connection.open(sock1)
      conn2 = Einhorn::Event::Connection.open(sock2)

      sock2.expects(:write_nonblock).once.raises(Errno::EWOULDBLOCK.new)
      conn2.write('Hello!')

      IO.expects(:select).once.with do |readers, writers, errs, timeout|
        Set.new(readers) == Set.new([sock1, sock2]) &&
          writers == [sock2] &&
          errs == nil &&
          timeout == nil
      end.returns([[], [], []])

      Einhorn::Event.loop_once
    end

    should "run callbacks for ready selectables" do
      sock1 = mock(:fileno => 4)
      sock2 = mock(:fileno => 5)

      conn1 = Einhorn::Event::Connection.open(sock1)
      conn2 = Einhorn::Event::Connection.open(sock2)

      sock2.expects(:write_nonblock).once.raises(Errno::EWOULDBLOCK.new)
      conn2.write('Hello!')

      IO.expects(:select).once.with do |readers, writers, errs, timeout|
        Set.new(readers) == Set.new([sock1, sock2]) &&
          writers == [sock2] &&
          errs == nil &&
          timeout == nil
      end.returns([[sock1], [sock2], []])

      conn1.expects(:notify_readable).once
      conn2.expects(:notify_writeable).never

      conn1.expects(:notify_readable).never
      conn2.expects(:notify_writeable).once

      Einhorn::Event.loop_once
    end
  end
end
