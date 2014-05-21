require 'subprocess'

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
      expected_exit_code = options.delete(:expected_exit_code) { 0 }
      cwd = options.delete(:cwd) { einhorn_code_dir }

      process = Bundler.with_clean_env do
        Dir.chdir(cwd) do
          default_options = {
            :stdout => Subprocess::PIPE,
            :stderr => Subprocess::PIPE
          }
          Subprocess::Process.new(Array(einhorn_command) + cmdline, default_options.merge(options))
        end
      end
      begin
        output = process.communicate
        yield(*output) if block_given?
      ensure
        status = process.wait
        assert_equal(expected_exit_code, status.exitstatus) unless expected_exit_code == nil
      end
    end
  end
end
