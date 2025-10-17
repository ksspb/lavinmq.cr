require "../spec_helper"

describe Lavinmq::Consumer do
  describe "initialization" do
    it "creates consumer with queue name" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue")
      consumer.should_not be_nil
    end
  end

  describe "subscription" do
    it "stores message handler on subscribe" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue")

      handler_called = false
      consumer.subscribe do |msg|
        handler_called = true
      end

      # Handler is stored but not called until messages arrive
      handler_called.should be_false
    end
  end

  describe "acknowledgments" do
    it "tracks and acks messages" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue", prefetch: 50)

      # This is a unit test - we can't actually ack without a real connection
      # The ack method should handle missing channel gracefully
      consumer.ack(1_u64)
      consumer.ack(2_u64, multiple: true)
    end

    it "handles nacks with requeue" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue")

      # Unit test - should handle gracefully without connection
      consumer.nack(1_u64, requeue: true)
      consumer.nack(2_u64, multiple: true, requeue: false)
    end
  end

  describe "close" do
    it "closes gracefully" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue")

      consumer.close
      # Should not raise
    end

    it "ignores operations after close" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue")

      consumer.close

      # These should be no-ops
      consumer.ack(1_u64)
      consumer.nack(2_u64)
    end
  end

  describe "no_ack mode" do
    it "accepts no_ack parameter in subscribe" do
      config = Lavinmq::Config.new
      conn_manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)
      consumer = Lavinmq::Consumer.new(conn_manager, "test_queue")

      consumer.subscribe(no_ack: true) do |msg|
        # In no_ack mode, messages are auto-acked
      end

      # Acks should be ignored in no_ack mode
      consumer.ack(1_u64)
    end
  end

  # Integration tests (require actual AMQP server)
  pending "subscribes to queue and receives messages" do
    # Requires LavinMQ/RabbitMQ server
  end

  pending "resubscribes on reconnection" do
    # Requires connection simulation
  end

  pending "tracks unacked messages correctly" do
    # Requires message delivery
  end

  pending "handles channel errors gracefully" do
    # Requires error simulation
  end
end
