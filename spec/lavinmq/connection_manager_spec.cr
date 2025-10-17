require "../spec_helper"

describe Lavinmq::ConnectionManager do
  describe "#connect and state management" do
    it "starts in Connecting state" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      manager.state.should eq Lavinmq::Config::ConnectionState::Connecting
    end

    pending "establishes connection successfully" do
      # TODO: Requires actual AMQP server for integration test
    end

    pending "transitions to Connected state when connection succeeds" do
      # TODO: Requires actual AMQP server for integration test
    end
  end

  describe "callbacks" do
    it "allows setting connection callback" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      called = false
      manager.on_connect { called = true }

      # Callback is set
      manager.@on_connect.should_not be_nil
    end

    it "allows setting disconnection callback" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      called = false
      manager.on_disconnect { called = true }

      manager.@on_disconnect.should_not be_nil
    end

    it "allows setting error callback" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      error : Exception? = nil
      manager.on_error { |e| error = e }

      manager.@on_error.should_not be_nil
    end
  end

  describe "#close" do
    it "can be closed" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      manager.close
      manager.@closed.should be_true
    end
  end

  describe "reconnection behavior" do
    pending "uses exponential backoff (100ms, 200ms, 400ms...)" do
      # TODO: Test reconnection timing with mock
    end

    pending "respects max reconnection delay (30s)" do
      # TODO: Test max delay cap
    end

    pending "fires callbacks on reconnection" do
      # TODO: Test callback behavior during reconnection
    end
  end
end
