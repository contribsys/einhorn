require_relative '_lib'

class StartupTest < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe 'when invoked without args' do
    it 'prints usage and exits with 1' do
      assert_raises(Subprocess::NonZeroExit) do
        Subprocess.check_call(default_einhorn_command,
                              :stdout => Subprocess::PIPE,
                              :stderr => Subprocess::PIPE) do |einhorn|
          stdout, stderr = einhorn.communicate
          assert_match(/\A## Usage/, stdout)
          assert_equal(1, einhorn.wait.exitstatus)
        end
      end
    end
  end

  describe 'when invoked with --upgrade-check' do
    it 'successfully exits' do
      Subprocess.check_call(default_einhorn_command + %w[--upgrade-check],
                            :stdout => Subprocess::PIPE,
                            :stderr => Subprocess::PIPE) do |einhorn|
        stdout, stderr = einhorn.communicate
        status = einhorn.wait
        assert_equal(0, status.exitstatus)
      end
    end
  end
end
