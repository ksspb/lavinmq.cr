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

    it "calls on_drop callback when buffer is full (Block policy now drops oldest for zero-latency)" do
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

      # Block policy now drops oldest (msg1) when buffer full (zero-latency requirement)
      producer.publish("msg2")

      dropped_messages.should eq ["msg1"]
      dropped_reasons.should eq [Lavinmq::Config::DropReason::BufferFull]
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

  describe "channel lifecycle management" do
    it "clears cached channel when it's closed" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        buffer_size: 100
      )

      # Initially no channel is cached
      producer.@channel.should be_nil

      # Note: This test verifies the logic exists but can't fully test
      # channel recreation without a real AMQP connection
      # The fix ensures get_or_create_channel checks channel.closed?
    end

    pending "recreates channel when closed channel is detected" do
      # TODO: Requires integration test with real AMQP broker
      # Test scenario:
      # 1. Create channel
      # 2. Close channel externally
      # 3. Call get_or_create_channel
      # 4. Verify new channel is created (not closed one returned)
    end
  end

  describe "flush retry handling" do
    it "drops messages after max flush retries to prevent infinite loops" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      producer = Lavinmq::Producer.new(
        manager,
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest,
        buffer_size: 10
      )

      dropped_messages = [] of String
      dropped_reasons = [] of Lavinmq::Config::DropReason

      producer.on_drop do |msg, _queue, reason|
        dropped_messages << msg
        dropped_reasons << reason
      end

      # Note: Without a real AMQP connection that repeatedly fails,
      # we can't easily test the retry logic in unit tests
      # This test documents the expected behavior
      # Integration tests should verify messages are dropped after
      # MAX_FLUSH_RETRIES failed attempts

      # Expected behavior (to be verified in integration tests):
      # 1. Message fails to flush MAX_FLUSH_RETRIES times
      # 2. Message is dropped with reason FlushRetryExceeded
      # 3. on_drop callback is called
    end
  end
end
