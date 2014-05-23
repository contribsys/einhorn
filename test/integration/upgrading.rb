require 'pry'
require_relative '_lib'
require 'socket'

class UpgradeTests < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe 'when upgrading a running einhorn without preloading' do
    before do
      @dir = prepare_fixture_directory('upgrade_project')
      @port = find_free_port
      @server_program = File.join(@dir, "upgrading_server.rb")
      @socket_path = File.join(@dir, "einhorn.sock")
    end
    after { cleanup_fixtured_directories }

    def read_version
      socket = Socket.new(Socket::PF_INET, Socket::SOCK_STREAM)
      sockaddr = Socket.pack_sockaddr_in(@port, '127.0.0.1')
      begin
        socket.connect_nonblock(sockaddr)
      rescue IO::WaitWritable
        IO.select(nil, [socket], [], 5)
        begin
          socket.connect_nonblock(sockaddr)
        rescue Errno::EISCONN
        end
      end
      socket.read.chomp
    ensure
      socket.close if socket
    end

    it 'can restart' do
      File.write(File.join(@dir, "version"), "0")
      reexec_cmdline = 'bundle exec einhorn'
      with_running_einhorn(%W{einhorn -m manual -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program}},
                           :stdout => 1,
                           :stderr => 2,
                           :expected_exit_code => nil) do |process|
        wait_for_command_socket(@socket_path)
        assert_equal("0", read_version, "Should report the initial version")

        File.write(File.join(@dir, "version"), "1")
        einhornsh(%W{-d #{@socket_path} -e upgrade})
        assert_equal("1", read_version, "Should report the upgraded version")

        $stderr.puts "Waiting for #{process} to terminate from a SIGTERM..."
        process.send_signal("TERM")
      end
    end
  end
end
