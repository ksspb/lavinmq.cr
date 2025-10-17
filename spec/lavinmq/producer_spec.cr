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

  describe "observability: drop tracking" do
    it "calls on_drop callback when buffer is full (DropOldest policy)" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest,
        buffer_size: 2
      )

      dropped_messages = [] of String
      dropped_queues = [] of String
      dropped_reasons = [] of Lavinmq::Config::DropReason

      producer.on_drop do |msg, queue, reason|
        dropped_messages << msg
        dropped_queues << queue
        dropped_reasons << reason
      end

      # Publish messages - they'll be buffered since no connection
      producer.publish("msg1")
      producer.publish("msg2")
      producer.publish("msg3") # Should trigger drop of msg1

      dropped_messages.should eq ["msg1"]
      dropped_queues.should eq ["test_queue"]
      dropped_reasons.should eq [Lavinmq::Config::DropReason::BufferFull]
    end

    it "calls on_drop callback when producer is closed with Block policy" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::Block,
        buffer_size: 1
      )

      dropped_messages = [] of String
      dropped_reasons = [] of Lavinmq::Config::DropReason

      producer.on_drop do |msg, _queue, reason|
        dropped_messages << msg
        dropped_reasons << reason
      end

      # Fill the buffer first
      producer.publish("msg1")

      # Now try to publish while buffer is full and then close
      spawn do
        sleep 10.milliseconds
        producer.close
      end

      # This should block then get dropped due to close
      producer.publish("msg2")

      dropped_messages.should eq ["msg2"]
      dropped_reasons.should eq [Lavinmq::Config::DropReason::Closed]
    end
  end

  describe "observability: publisher outcome callbacks" do
    it "has on_confirm callback for successful publishes" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm
      )

      confirmed_messages = [] of String
      confirmed_queues = [] of String

      producer.on_confirm do |msg, queue|
        confirmed_messages << msg
        confirmed_queues << queue
      end

      # Integration test - requires real AMQP broker
      # For now, just verify callback can be set
      producer.@on_confirm.should_not be_nil
    end

    it "has on_nack callback for nacked messages" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm
      )

      nacked_messages = [] of String
      producer.on_nack do |msg, _queue|
        nacked_messages << msg
      end

      producer.@on_nack.should_not be_nil
    end

    it "has on_error callback for failed publishes" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm
      )

      error_messages = [] of String
      error_exceptions = [] of Exception

      producer.on_error do |msg, _queue, ex|
        error_messages << msg
        error_exceptions << ex
      end

      producer.@on_error.should_not be_nil
    end
  end

  describe "observability: buffer state" do
    it "exposes buffer size and capacity" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        buffer_size: 100
      )

      producer.buffer_size.should eq 0
      producer.buffer_capacity.should eq 100

      # Buffer messages since no connection
      producer.publish("msg1")
      producer.publish("msg2")

      producer.buffer_size.should eq 2
      producer.buffer_capacity.should eq 100
    end
  end
end
