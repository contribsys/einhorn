require File.expand_path(File.join(File.dirname(__FILE__), '../../_lib'))

require 'einhorn'

class ClientTest < EinhornTestCase
  def unserialized_message
    {:foo => ['%bar', '%baz']}
  end

  def serialized_1_8
    "--- %0A:foo: %0A- \"%25bar\"%0A- \"%25baz\"%0A\n"
  end

  def serialized_1_9
    "---%0A:foo:%0A- ! '%25bar'%0A- ! '%25baz'%0A\n"
  end

  def serialized_2_0
    "---%0A:foo:%0A- '%25bar'%0A- '%25baz'%0A\n"
  end

  def serialized_2_1
    "---%0A:foo:%0A- \"%25bar\"%0A- \"%25baz\"%0A\n"
  end

  def serialized_options
    [serialized_1_8, serialized_1_9, serialized_2_0, serialized_2_1]
  end

  describe "when sending a message" do
    it "writes a serialized line" do
      socket = mock
      socket.expects(:write).with {|write| serialized_options.include?(write)}
      Einhorn::Client::Transport.send_message(socket, unserialized_message)
    end
  end

  describe "when receiving a message" do
    it "deserializes a single 1.8-style line" do
      socket = mock
      socket.expects(:readline).returns(serialized_1_8)
      result = Einhorn::Client::Transport.receive_message(socket)
      assert_equal(result, unserialized_message)
    end

    it "deserializes a single 1.9-style line" do
      socket = mock
      socket.expects(:readline).returns(serialized_1_9)
      result = Einhorn::Client::Transport.receive_message(socket)
      assert_equal(result, unserialized_message)
    end
  end

  describe "when {de,}serializing a message" do
    it "serializes and escape a message as expected" do
      actual = Einhorn::Client::Transport.serialize_message(unserialized_message)
      assert(serialized_options.include?(actual), "Actual message is #{actual.inspect}")
    end

    it "deserializes and unescape a 1.8-style message as expected" do
      actual = Einhorn::Client::Transport.deserialize_message(serialized_1_8)
      assert_equal(unserialized_message, actual)
    end

    it "deserializes and unescape a 1.9-style message as expected" do
      actual = Einhorn::Client::Transport.deserialize_message(serialized_1_9)
      assert_equal(unserialized_message, actual)
    end

    it "deserializes and unescapes a 2.0-style message as expected" do
      actual = Einhorn::Client::Transport.deserialize_message(serialized_2_0)
      assert_equal(unserialized_message, actual)
    end

    it "deserializes and unescapes a 2.1-style message as expected" do
      actual = Einhorn::Client::Transport.deserialize_message(serialized_2_1)
      assert_equal(unserialized_message, actual)
    end

    it "raises an error when deserializing invalid YAML" do
      invalid_serialized = "-%0A\t-"
      begin
        Einhorn::Client::Transport.deserialize_message(invalid_serialized)
      rescue Einhorn::Client::Transport::ParseError
      end
    end
  end
end
