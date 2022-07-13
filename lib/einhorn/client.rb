require "set"
require "yaml"
require "einhorn/safe_yaml"

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
        escaped = serialized.gsub(/%|\n/, "%" => "%25", "\n" => "%0A")
        escaped + "\n"
      end

      def self.deserialize_message(line)
        serialized = line.gsub(/%(25|0A)/, "%25" => "%", "%0A" => "\n")
        SafeYAML.load(serialized)
      end
    end

    def self.for_path(path_to_socket)
      socket = UNIXSocket.open(path_to_socket)
      new(socket)
    end

    def self.for_fd(fileno)
      socket = UNIXSocket.for_fd(fileno)
      new(socket)
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
