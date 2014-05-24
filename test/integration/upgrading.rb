require_relative '_lib'
require 'socket'
require 'pry'

class UpgradeTests < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

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

  describe 'when upgrading a running einhorn without preloading' do
    before do
      @dir = prepare_fixture_directory('upgrade_project')
      @port = find_free_port
      @server_program = File.join(@dir, "upgrading_server.rb")
      @socket_path = File.join(@dir, "einhorn.sock")
    end
    after { cleanup_fixtured_directories }

    it 'can restart' do
      File.write(File.join(@dir, "version"), "0")
      with_running_einhorn(%W{einhorn -m manual -b 127.0.0.1:#{@port} -d #{@socket_path} -- ruby #{@server_program}}) do |process|
        wait_for_command_socket(@socket_path)
        assert_equal("0", read_version, "Should report the initial version")

        File.write(File.join(@dir, "version"), "1")
        einhornsh(%W{-d #{@socket_path} -e upgrade})
        assert_equal("1", read_version, "Should report the upgraded version")

        process.terminate
      end
    end
  end

  describe 'handling environments on upgrade' do
    before do
      @dir = prepare_fixture_directory('env_printer')
      @port = find_free_port
      @server_program = File.join(@dir, "env_printer.rb")
      @socket_path = File.join(@dir, "einhorn.sock")
    end
    after { cleanup_fixtured_directories }

    describe 'when running with --reexec-as' do
      it 'preserves environment variables across restarts' do
        File.write(File.join(@dir, "version"), "0")
        # exec the new einhorn with the same environment:
        reexec_cmdline = 'env VAR=a bundle exec einhorn'

        with_running_einhorn(%W{einhorn -m manual -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR},
                             :env => ENV.to_hash.merge({'VAR' => 'a'})) do |process|

          wait_for_command_socket(@socket_path)
          einhornsh(%W{-d #{@socket_path} -e upgrade})
          assert_equal("a", read_version, "Should report the upgraded version")

          process.terminate
        end
      end

      describe 'without preloading' do
        it 'can update environment variables when the reexec command line says to' do
          File.write(File.join(@dir, "version"), "0")
          # exec the new einhorn with the same environment:
          reexec_cmdline = 'env VAR=b OINK=b bundle exec einhorn'

          with_running_einhorn(%W{einhorn -m manual -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR},
                               :env => ENV.to_hash.merge({'VAR' => 'a'})) do |process|

            wait_for_command_socket(@socket_path)
            einhornsh(%W{-d #{@socket_path} -e upgrade})
            assert_equal("b", read_version, "Should report the upgraded version")

            process.terminate
          end
        end
      end

      describe 'with preloading' do
        it 'can update environment variables on preloaded code when the reexec command line says to' do
          File.write(File.join(@dir, "version"), "0")
          # exec the new einhorn with the same environment:
          reexec_cmdline = 'env VAR=b OINK=b bundle exec einhorn'

          with_running_einhorn(%W{einhorn -m manual -p #{@server_program} -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR},
                               :env => ENV.to_hash.merge({'VAR' => 'a'})) do |process|

            wait_for_command_socket(@socket_path)
            einhornsh(%W{-d #{@socket_path} -e upgrade})
            assert_equal("b", read_version, "Should report the upgraded version")

            process.terminate
          end
        end
      end
    end
  end
end
