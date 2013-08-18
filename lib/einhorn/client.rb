require 'set'
require 'uri'
require 'yaml'

module Einhorn
  class Client
    # Keep this in this file so client can be loaded entirely
    # standalone by user code.
    module Transport

      ParseError = defined?(Psych::SyntaxError) ? Psych::SyntaxError : ArgumentError

      def self.send_message(socket, message)
        line = serialize_message(message)
        socket.write(line)
      end

      def self.receive_message(socket)
        line = socket.readline
        deserialize_message(line)
      end

      def self.serialize_message(message)
        serialized = YAML.dump(message)
        escaped = URI.escape(serialized, "%\n")
        escaped + "\n"
      end

      def self.deserialize_message(line)
        serialized = URI.unescape(line)
        YAML.load(serialized)
      end
    end

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

    def send_command(command_hash)
      Transport.send_message(@socket, command_hash)
    end

    def receive_message
      Transport.receive_message(@socket)
    end

    def close
      @socket.close
    end
  end
end
