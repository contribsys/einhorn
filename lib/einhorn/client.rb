require 'json'
require 'set'

module Einhorn
  class Client
    @@responseless_commands = Set.new(['worker:ack'])

    def self.for_path(path_to_socket)
      socket = UNIXSocket.open(path_to_socket)
      self.new(socket)
    end

    def self.for_fd(fileno)
      socket = UNIXSocket.for_fd(fileno)
      self.new(socket)
    end

    def initialize(socket)
      @socket = socket
    end

    def command(command_hash)
      command = JSON.generate(command_hash) + "\n"
      write(command)
      recvmessage if expect_response?(command_hash)
    end

    def expect_response?(command_hash)
      !@@responseless_commands.include?(command_hash['command'])
    end

    def close
      @socket.close
    end

    private

    def write(bytes)
      @socket.write(bytes)
    end

    # TODO: use a streaming JSON parser instead?
    def recvmessage
      line = @socket.readline
      JSON.parse(line)
    end
  end
end
