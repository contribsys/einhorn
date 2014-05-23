require 'subprocess'
require 'timeout'

module Helpers
  module EinhornHelpers
    def einhorn_code_dir
      File.expand_path('../../../../', File.dirname(__FILE__))
    end

    def default_einhorn_command
      ['bundle', 'exec', File.expand_path('bin/einhorn', einhorn_code_dir)]
    end

    def with_running_einhorn(cmdline, options = {})
      options = options.dup
      einhorn_command = options.delete(:einhorn_command) { default_einhorn_command }
      expected_exit_code = options.delete(:expected_exit_code) { nil }
      cwd = options.delete(:cwd) { einhorn_code_dir }

      stdout, stderr = "", ""
      communicator = nil
      process = Bundler.with_clean_env do
        Dir.chdir(cwd) do
          default_options = {
            :stdout => Subprocess::PIPE,
            :stderr => Subprocess::PIPE,
            :stdin => '/dev/null',
          }
          Subprocess::Process.new(Array(einhorn_command) + cmdline, default_options.merge(options))
        end
      end
      begin
        communicator = Thread.new { stdout, stderr = process.communicate }
        yield(process) if block_given?
      ensure
        status = -1
        begin
          Timeout.timeout(10) do  # (Argh, I'm so sorry)
            status = process.wait
          end
        rescue Timeout::Error
          $stderr.puts "Could not get Einhorn to quit within 10 seconds, killing it forcefully..."
          process.send_signal("KILL")
          status = process.wait
        end
        assert_equal(expected_exit_code, status.exitstatus) unless expected_exit_code == nil
        communicator.join
        return stdout, stderr
      end
    end

    def einhornsh(commandline, options = {})
      Subprocess.check_call(%W{bundle exec #{File.expand_path('bin/einhornsh')}} + commandline,
                            {
                              :stdin => '/dev/null',
                              :stdout => '/dev/null',
                              :stderr => '/dev/null'
                            }.merge(options))
    end

    def fixture_path(name)
      File.expand_path(File.join('../fixtures', name), File.dirname(__FILE__))
    end

    # Creates a new temporary directory with the initial contents from
    # test/integration/_lib/fixtures/{name} and returns the path to
    # it.  The contents of this directory are temporary and can be
    # safely overwritten.
    def prepare_fixture_directory(name)
      @fixtured_dirs ||= Set.new
      new_dir = Dir.mktmpdir(name)
      @fixtured_dirs << new_dir
      FileUtils.cp_r(File.join(fixture_path(name), '.'), new_dir)

      new_dir
    end

    def cleanup_fixtured_directories
      (@fixtured_dirs || []).each { |dir| FileUtils.rm_rf(dir) }
    end

    def find_free_port(host='127.0.0.1')
      open_port = TCPServer.new(host, 0)
      open_port.addr[1]
    ensure
      open_port.close
    end

    def wait_for_command_socket(path)
      until File.exist?(path)
        sleep 0.01
      end
    end
  end
end
