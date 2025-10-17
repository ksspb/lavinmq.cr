require "../spec_helper"

describe Lavinmq::Producer do
  describe "fire-and-forget mode" do
    it "buffers messages during disconnect" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::FireAndForget,
        buffer_size: 100
      )

      # Producer should initialize with buffer
      producer.@buffer.should_not be_nil
      producer.@buffer.max_size.should eq 100
    end

    pending "sends buffered messages on reconnection" do
      # TODO: Integration test with real AMQP
    end

    pending "drops oldest message when buffer exceeds 10k" do
      # TODO: Test buffer overflow behavior
    end
  end

  describe "confirm mode" do
    it "can be configured with block policy" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::Block
      )

      producer.@buffer_policy.should eq Lavinmq::Config::BufferPolicy::Block
    end

    it "can be configured with raise policy" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::Raise
      )

      producer.@buffer_policy.should eq Lavinmq::Config::BufferPolicy::Raise
    end

    it "can be configured with drop oldest policy" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest
      )

      producer.@buffer_policy.should eq Lavinmq::Config::BufferPolicy::DropOldest
    end

    pending "blocks when buffer is full (block policy)" do
      # TODO: Integration test
    end

    pending "raises when buffer is full (raise policy)" do
      # TODO: Integration test
    end
  end

  describe "#close" do
    it "can be closed" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(manager, "test_queue")

      producer.close
      producer.@closed.should be_true
    end
  end
end
