require(File.expand_path("_lib", File.dirname(__FILE__)))
require "socket"
require "einhorn/client"

class UpgradeTests < EinhornIntegrationTestCase
  include Helpers::EinhornHelpers

  describe "when upgrading a running einhorn without preloading" do
    before do
      @dir = prepare_fixture_directory("upgrade_project")
      @port = find_free_port
      @server_program = File.join(@dir, "upgrading_server.rb")
      @socket_path = File.join(@dir, "einhorn.sock")
    end
    after { cleanup_fixtured_directories }

    it "can restart" do
      File.write(File.join(@dir, "version"), "0")
      with_running_einhorn(%W[einhorn -m manual -b 127.0.0.1:#{@port} -d #{@socket_path} -- ruby #{@server_program}]) do |process|
        wait_for_open_port
        assert_equal("0", read_from_port, "Should report the initial version")

        File.write(File.join(@dir, "version"), "1")
        einhornsh(%W[-d #{@socket_path} -e upgrade])
        assert_equal("1", read_from_port, "Should report the upgraded version")

        process.terminate
      end
    end
  end

  describe "handling environments on upgrade" do
    before do
      @dir = prepare_fixture_directory("env_printer")
      @port = find_free_port
      @server_program = File.join(@dir, "env_printer.rb")
      @socket_path = File.join(@dir, "einhorn.sock")

      mangler = ('a'..'z').to_a.shuffle[0,8].join
      @unix_listener_socket_path = "unix-listener-einhorn-#{mangler}.sock"
    end
    after { cleanup_fixtured_directories }

    describe "when running as a unix domain socket listener" do
      it "preserves environment variables across restarts" do
        # exec the new einhorn with the same environment:
        reexec_cmdline = "env VAR=a bundle exec --keep-file-descriptors einhorn"

        with_running_einhorn(%W[einhorn -m manual -b #{@unix_listener_socket_path} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR],
          env: ENV.to_hash.merge({"VAR" => "a"})) do |process|
          wait_for_open_socket
          einhornsh(%W[-d #{@socket_path} -e upgrade])
          assert_equal("a", read_from_socket, "Should report the upgraded version")

          process.terminate
        end
      end
    end

    describe "when running with --reexec-as" do
      it "preserves environment variables across restarts" do
        # exec the new einhorn with the same environment:
        reexec_cmdline = "env VAR=a bundle exec --keep-file-descriptors einhorn"

        with_running_einhorn(%W[einhorn -m manual -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR],
          env: ENV.to_hash.merge({"VAR" => "a"})) do |process|
          wait_for_open_port
          einhornsh(%W[-d #{@socket_path} -e upgrade])
          assert_equal("a", read_from_port, "Should report the upgraded version")

          process.terminate
        end
      end

      it "cleans up if a child dies during the reexec" do
        # attempt to setup a scenario where a child exits in the
        # interlude after old einhorn has execed the reexec-as
        # command, but before the reexec-as command execs new einhorn

        @dir = prepare_fixture_directory("exit_during_upgrade")
        @server_program = File.join(@dir, "exiting_server.rb")
        @socket_path = File.join(@dir, "einhorn.sock")

        reexec_cmdline = File.join(@dir, "upgrade_reexec.sh")

        with_running_einhorn(%W[einhorn -m manual -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program}]) do |process|
          wait_for_open_port

          Process.kill("USR2", read_from_port.to_i)
          einhornsh(%W[-d #{@socket_path} -e upgrade])

          client = Einhorn::Client.for_path(@socket_path)
          client.send_command("command" => "state")
          resp = client.receive_message

          state = Einhorn::SafeYAML.load(resp["message"])
          assert_equal(1, state[:state][:children].count)

          child = state[:state][:children].first.last
          assert_in_delta(child[:pinged_at], Time.now, 60)
          assert_equal("id-1", child[:pinged_request_id])

          process.terminate
        end
      end

      describe "without preloading" do
        it "can update environment variables when the reexec command line says to" do
          # exec the new einhorn with the same environment:
          reexec_cmdline = "env VAR=b OINK=b bundle exec --keep-file-descriptors einhorn"

          cmd = %W[einhorn -m manual -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR]

          with_running_einhorn(cmd,
            env: ENV.to_hash.merge({"VAR" => "a"})) do |process|
            wait_for_open_port
            einhornsh(%W[-d #{@socket_path} -e upgrade])
            assert_equal("b", read_from_port, "Should report the upgraded version")

            process.terminate
          end
        end
      end

      describe "with preloading" do
        it "can update environment variables on preloaded code when the reexec command line says to" do
          # exec the new einhorn with the same environment:
          reexec_cmdline = "env VAR=b OINK=b bundle exec --keep-file-descriptors einhorn"

          with_running_einhorn(%W[einhorn -m manual -p #{@server_program} -b 127.0.0.1:#{@port} --reexec-as=#{reexec_cmdline} -d #{@socket_path} -- ruby #{@server_program} VAR],
            env: ENV.to_hash.merge({"VAR" => "a"})) do |process|
            wait_for_open_port
            einhornsh(%W[-d #{@socket_path} -e upgrade])
            assert_equal("b", read_from_port, "Should report the upgraded version")

            process.terminate
          end
        end
      end
    end
  end

  describe "when invoked with --drop-env-var" do
    before do
      @dir = prepare_fixture_directory("env_printer")
      @port = find_free_port
      @server_program = File.join(@dir, "env_printer.rb")
      @socket_path = File.join(@dir, "einhorn.sock")
    end
    after { cleanup_fixtured_directories }

    it %(removes the variable from its children's environment) do
      with_running_einhorn(%W[einhorn -m manual -b 127.0.0.1:#{@port} --drop-env-var=VAR -d #{@socket_path} -- ruby #{@server_program} VAR],
        env: ENV.to_hash.merge({"VAR" => "a"})) do |process|
        wait_for_open_port
        assert_equal("a", read_from_port, "Should report $VAR initially")

        einhornsh(%W[-d #{@socket_path} -e upgrade])
        assert_equal("", read_from_port, "Should have dropped the variable post-upgrade")

        process.terminate
      end
    end

    it %(causes an upgrade with --reexec-as to not clobber the new environment) do
      reexec_cmdline = "env VAR2=b bundle exec --keep-file-descriptors einhorn"
      with_running_einhorn(%W[einhorn -m manual -b 127.0.0.1:#{@port} --drop-env-var=VAR1 --drop-env-var=VAR2 -d #{@socket_path} --reexec-as=#{reexec_cmdline} -- ruby #{@server_program} VAR1 VAR2],
        env: ENV.to_hash.merge({"VAR1" => "a", "VAR2" => "a"})) do |process|
        wait_for_open_port
        assert_equal("aa", read_from_port, "Should report both $VAR1 and $VAR2 initially")

        einhornsh(%W[-d #{@socket_path} -e upgrade])
        assert_equal("b", read_from_port, "Should have dropped $VAR1 post-upgrade and re-set $VAR2")

        process.terminate
      end
    end
  end

  describe "with --signal-timeout" do
    before do
      @dir = prepare_fixture_directory("signal_timeout")
      @port = find_free_port
      @server_program = File.join(@dir, "sleepy_server.rb")
      @socket_path = File.join(@dir, "einhorn.sock")
    end

    after { cleanup_fixtured_directories }

    it "issues a SIGKILL to outdated children when signal-timeout has passed" do
      signal_timeout = 2
      sleep_for = 10
      cmd = %W[
        einhorn
        -b 127.0.0.1:#{@port}
        -d #{@socket_path}
        --signal-timeout #{signal_timeout}
        -- ruby #{@server_program}
      ]

      with_running_einhorn(cmd, env: ENV.to_h.merge({"TRAP_SLEEP" => sleep_for.to_s})) do |process|
        wait_for_open_port
        client = Einhorn::Client.for_path(@socket_path)
        einhornsh(%W[-d #{@socket_path} -e upgrade])

        state = get_state(client)
        assert_equal(2, state[:children].count)
        signaled_children = state[:children].select { |_, c| c[:signaled].length > 0 }
        assert_equal(1, signaled_children.length)

        sleep(signal_timeout * 2)

        state = get_state(client)
        assert_equal(1, state[:children].count)
        signaled_children = state[:children].select { |_, c| c[:signaled].length > 0 }
        assert_equal(0, signaled_children.length)

        process.terminate
      end
    end
  end
end
