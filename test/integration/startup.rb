require_relative '_lib'

class StartupTest < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe 'when invoked without args' do
    it 'prints usage and exits with 1' do
      with_running_einhorn([], :expected_exit_code => 1) do |process|
        stdout, stderr = process.communicate
        assert_match(/\A## Usage/, stdout)
      end
    end
  end

  describe 'when invoked with --upgrade-check' do
    it 'successfully exits' do
      with_running_einhorn(%w[--upgrade-check], :expected_exit_code => 0)
    end
  end
end
