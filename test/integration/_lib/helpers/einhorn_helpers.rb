require "subprocess"
require "timeout"
require "tmpdir"

module Helpers
  module EinhornHelpers
    def einhorn_code_dir
      File.expand_path("../../../../", File.dirname(__FILE__))
    end

    def default_einhorn_command
      cmd = ["bundle", "exec"]
      cmd << "--keep-file-descriptors"
      cmd << File.expand_path("bin/einhorn", einhorn_code_dir)

      cmd
    end

    def with_running_einhorn(cmdline, options = {})
      options = options.dup
      einhorn_command = options.delete(:einhorn_command) { default_einhorn_command }
      _expected_exit_code = options.delete(:expected_exit_code) { nil }
      output_callback = options.delete(:output_callback) { nil }

      stdout, stderr = "", ""
      communicator = nil
      process = Bundler.with_original_env do
        default_options = {
          stdout: Subprocess::PIPE,
          stderr: Subprocess::PIPE,
          stdin: "/dev/null",
          cwd: einhorn_code_dir
        }
        Subprocess::Process.new(Array(einhorn_command) + cmdline, default_options.merge(options))
      end

      status = nil
      begin
        communicator = Thread.new do
          stdout, stderr = process.communicate
        rescue Errno::ECHILD
          # It's dead, and we're not getting anything. This is peaceful.
        end
        yield(process) if block_given?
      rescue
        unless (status = process.poll) && status.exited?
          process.terminate
        end
        raise
      ensure
        unless (status = process.poll) && status.exited?
          100.times do
            status = process.poll
            if status&.exited?
              break
            end
            sleep(0.1)
          end
          unless status&.exited?
            warn "Could not get Einhorn to quit within 10 seconds, killing it forcefully..."
            process.send_signal("KILL")
            status = process.wait
          end
        end
        communicator.join
        output_callback&.call(stdout, stderr)
      end
    end

    def einhornsh(commandline, options = {})
      Subprocess.check_call(%W[bundle exec #{File.expand_path("bin/einhornsh")}] + commandline,
        {
          stdin: "/dev/null",
          stdout: "/dev/null",
          stderr: "/dev/null"
        }.merge(options))
    end

    def fixture_path(name)
      File.expand_path(File.join("../fixtures", name), File.dirname(__FILE__))
    end

    # Creates a new temporary directory with the initial contents from
    # test/integration/_lib/fixtures/{name} and returns the path to
    # it.  The contents of this directory are temporary and can be
    # safely overwritten.
    def prepare_fixture_directory(name)
      @fixtured_dirs ||= Set.new
      new_dir = Dir.mktmpdir(name)
      @fixtured_dirs << new_dir
      FileUtils.cp_r(File.join(fixture_path(name), "."), new_dir, preserve: true)

      new_dir
    end

    def cleanup_fixtured_directories
      (@fixtured_dirs || []).each { |dir| FileUtils.rm_rf(dir) }
      FileUtils.rm_rf(@unix_listener_socket_path)
    end

    def find_free_port(host = "127.0.0.1")
      open_port = TCPServer.new(host, 0)
      open_port.addr[1]
    ensure
      open_port.close
    end

    def get_state(client)
      client.send_command("command" => "state")
      Einhorn::SafeYAML.load(client.receive_message["message"])[:state]
    end


    def mash_retry(&block)
      max_retries = 50
      begin
        yield
      rescue Errno::ECONNREFUSED, Errno::ENOENT
        max_retries -= 1
        if max_retries <= 0
          raise
        else
          sleep 0.1
          retry
        end
      end
    end

    def wait_for_open_socket
      mash_retry do
        read_from_socket
      end
    end

    def wait_for_open_port
      mash_retry do
        read_from_port
      end
    end

    def read_from_socket
      begin
        socket = UNIXSocket.new(@unix_listener_socket_path)
        socket.read.chomp
      ensure
        socket&.close
      end
    end

    def read_from_port
      ewouldblock = IO::WaitWritable
      socket = Socket.new(Socket::PF_INET, Socket::SOCK_STREAM, 0)
      sockaddr = Socket.pack_sockaddr_in(@port, "127.0.0.1")
      begin
        socket.connect_nonblock(sockaddr)
      rescue ewouldblock
        socket.wait_writable(5)
        begin
          socket.connect_nonblock(sockaddr)
        rescue Errno::EISCONN
        end
      end
      socket.read.chomp
    ensure
      socket&.close
    end
  end
end
