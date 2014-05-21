require_relative '_lib'

class StartupTest < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe 'when invoked without args' do
    it 'prints usage and exits with 1' do
      with_running_einhorn([], :expected_exit_code => 1) do |stdout, stderr|
        assert_match(/\A## Usage/, stdout)
      end
    end
  end
end
