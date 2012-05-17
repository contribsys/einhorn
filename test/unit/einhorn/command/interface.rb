require File.expand_path(File.join(File.dirname(__FILE__), '../../../test_helper'))

require 'einhorn'

class InterfaceTest < Test::Unit::TestCase
  include Einhorn::Command

  context "when a command is received" do
    should "call that command" do
      conn = stub(:log_debug => nil)
      conn.expects(:write).once.with do |message|
        parsed = JSON.parse(message)
        parsed['message'] =~ /Welcome gdb/
      end
      request = {
        'command' => 'ehlo',
        'user' => 'gdb'
      }
      Interface.process_command(conn, JSON.generate(request))
    end
  end

  context "when an unrecognized command is received" do
    should "call the unrecognized_command method" do
      conn = stub(:log_debug => nil)
      Interface.expects(:unrecognized_command).once
      request = {
        'command' => 'made-up',
      }
      Interface.process_command(conn, JSON.generate(request))
    end
  end

  context "when a worker ack is received" do
    should "register ack and close the connection" do
      conn = stub(:log_debug => nil)
      conn.expects(:close).once
      conn.expects(:write).never
      request = {
        'command' => 'worker:ack',
        'pid' => 1234
      }
      Einhorn::Command.expects(:register_manual_ack).once.with(1234)
      Interface.process_command(conn, JSON.generate(request))
    end
  end
end
