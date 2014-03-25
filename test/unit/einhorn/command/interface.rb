require File.expand_path(File.join(File.dirname(__FILE__), '../../../_lib'))

require 'einhorn'

class InterfaceTest < EinhornTestCase
  include Einhorn::Command

  describe "when a command is received" do
    it "calls that command" do
      conn = stub(:log_debug => nil)
      conn.expects(:write).once.with do |message|
        # Remove trailing newline
        message = message[0...-1]
        parsed = YAML.load(URI.unescape(message))
        parsed['message'] =~ /Welcome, gdb/
      end
      request = {
        'command' => 'ehlo',
        'user' => 'gdb'
      }
      Interface.process_command(conn, YAML.dump(request))
    end
  end

  describe "when an unrecognized command is received" do
    it "calls the unrecognized_command method" do
      conn = stub(:log_debug => nil)
      Interface.expects(:unrecognized_command).once
      request = {
        'command' => 'made-up',
      }
      Interface.process_command(conn, YAML.dump(request))
    end
  end

  describe "when a worker ack is received" do
    it "registers ack and close the connection" do
      conn = stub(:log_debug => nil)
      conn.expects(:close).once
      conn.expects(:write).never
      request = {
        'command' => 'worker:ack',
        'pid' => 1234
      }
      Einhorn::Command.expects(:register_manual_ack).once.with(1234)
      Interface.process_command(conn, YAML.dump(request))
    end
  end
end
