require(File.expand_path("_lib", File.dirname(__FILE__)))

class StartupTest < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe "when invoked without args" do
    it "prints usage and exits with 1" do
      assert_raises(Subprocess::NonZeroExit) do
        Subprocess.check_call(default_einhorn_command,
          stdout: Subprocess::PIPE,
          stderr: Subprocess::PIPE) do |einhorn|
          stdout, _stderr = einhorn.communicate
          assert_match(/\A## Usage/, stdout)
          assert_equal(1, einhorn.wait.exitstatus)
        end
      end
    end
  end

  describe "when invoked with --upgrade-check" do
    it "successfully exits" do
      Subprocess.check_call(default_einhorn_command + %w[--upgrade-check],
        stdout: Subprocess::PIPE,
        stderr: Subprocess::PIPE) do |einhorn|
        _stdout, _stderr = einhorn.communicate
        status = einhorn.wait
        assert_equal(0, status.exitstatus)
      end
    end
  end
end
