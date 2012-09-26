require File.expand_path(File.join(File.dirname(__FILE__), '../../test_helper'))

require 'einhorn'

class ClientTest < Test::Unit::TestCase
  def message
    {:foo => ['%bar', '%baz']}
  end

  def serialized
    "--- %0A:foo: %0A- \"%25bar\"%0A- \"%25baz\"%0A\n"
  end

  context "when sending a message" do
    should "write a serialized line" do
      socket = mock
      socket.expects(:write).with(serialized)
      Einhorn::Client::Transport.send_message(socket, message)
    end
  end

  context "when receiving a message" do
    should "deserialize a single line" do
      socket = mock
      socket.expects(:readline).returns(serialized)
      result = Einhorn::Client::Transport.receive_message(socket)
      assert_equal(result, message)
    end
  end

  context "when {de,}serializing a message" do
    should "serialize and escape a message as expected" do
      actual = Einhorn::Client::Transport.serialize_message(message)
      assert_equal(serialized, actual)
    end

    should "deserialize and unescape a message as expected" do
      actual = Einhorn::Client::Transport.deserialize_message(serialized)
      assert_equal(message, actual)
    end

    should "raise an error when deserializing invalid YAML" do
      invalid_serialized = "-%0A\t-"
      assert_raises(ArgumentError) do
        Einhorn::Client::Transport.deserialize_message(invalid_serialized)
      end
    end
  end
end
