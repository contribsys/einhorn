require(File.expand_path('_lib', File.dirname(__FILE__)))

class PdeathsigTest < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe 'when run with -k' do
    before do
      @dir = prepare_fixture_directory('pdeathsig_printer')
      @port = find_free_port
      @server_program = File.join(@dir, 'pdeathsig_printer.rb')
      @socket_path = File.join(@dir, 'einhorn.sock')
    end
    after { cleanup_fixtured_directories }

    it 'sets pdeathsig to USR2 in the child process' do
      with_running_einhorn(%W{einhorn -m manual -b 127.0.0.1:#{@port} -d #{@socket_path} -k -- ruby #{@server_program}}) do |process|
        wait_for_open_port
        output = read_from_port
        if output != "not implemented" then
          assert_equal("USR2", output)
        end
        process.terminate
      end
    end
  end
end
