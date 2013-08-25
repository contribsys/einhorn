require File.expand_path(File.join(File.dirname(__FILE__), '../../_lib'))

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

class EventTest < EinhornTestCase
  describe "when running the event loop" do
    before do
      Einhorn::Event.reset
    end

    after do
      Einhorn::Event.reset
    end

    it "selects on readable descriptors" do
      sock1 = stub(:fileno => 4)
      sock2 = stub(:fileno => 5)

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

    it "selects on writeable descriptors" do
      sock1 = stub(:fileno => 4)
      sock2 = stub(:fileno => 5)

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

    it "runs callbacks for ready selectables" do
      sock1 = stub(:fileno => 4)
      sock2 = stub(:fileno => 5)

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
