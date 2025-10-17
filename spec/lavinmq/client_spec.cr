require "../spec_helper"

describe Lavinmq::Client do
  describe "initialization" do
    it "creates client with AMQP URL" do
      client = Lavinmq::Client.new("amqp://localhost")
      client.should_not be_nil
      client.close
    end

    it "creates client with config" do
      config = Lavinmq::Config.new
      config.buffer_size = 5000
      client = Lavinmq::Client.new("amqp://localhost", config)
      client.should_not be_nil
      client.close
    end
  end

  describe "producer creation" do
    it "creates fire-and-forget producer" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer = client.producer(
        "test_queue",
        mode: Lavinmq::Config::PublishMode::FireAndForget
      )

      producer.should_not be_nil
      client.close
    end

    it "creates confirm producer with block policy" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer = client.producer(
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::Block
      )

      producer.should_not be_nil
      client.close
    end

    it "creates confirm producer with raise policy" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer = client.producer(
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::Raise
      )

      producer.should_not be_nil
      client.close
    end

    it "creates confirm producer with drop oldest policy" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer = client.producer(
        "test_queue",
        mode: Lavinmq::Config::PublishMode::Confirm,
        buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest
      )

      producer.should_not be_nil
      client.close
    end

    it "creates producer with custom buffer size" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer = client.producer(
        "test_queue",
        buffer_size: 1000
      )

      producer.should_not be_nil
      client.close
    end

    it "raises error when creating producer on closed client" do
      client = Lavinmq::Client.new("amqp://localhost")
      client.close

      expect_raises(Lavinmq::ClosedError) do
        client.producer("test_queue")
      end
    end
  end

  describe "consumer creation" do
    it "creates consumer with default prefetch" do
      client = Lavinmq::Client.new("amqp://localhost")

      consumer = client.consumer("test_queue")

      consumer.should_not be_nil
      client.close
    end

    it "creates consumer with custom prefetch" do
      client = Lavinmq::Client.new("amqp://localhost")

      consumer = client.consumer("test_queue", prefetch: 50)

      consumer.should_not be_nil
      client.close
    end

    it "raises error when creating consumer on closed client" do
      client = Lavinmq::Client.new("amqp://localhost")
      client.close

      expect_raises(Lavinmq::ClosedError) do
        client.consumer("test_queue")
      end
    end
  end

  describe "multiple producers and consumers" do
    it "creates multiple producers for different queues" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer1 = client.producer("queue1")
      producer2 = client.producer("queue2")
      producer3 = client.producer("queue3")

      producer1.should_not be_nil
      producer2.should_not be_nil
      producer3.should_not be_nil

      client.close
    end

    it "creates multiple consumers for different queues" do
      client = Lavinmq::Client.new("amqp://localhost")

      consumer1 = client.consumer("queue1")
      consumer2 = client.consumer("queue2")
      consumer3 = client.consumer("queue3")

      consumer1.should_not be_nil
      consumer2.should_not be_nil
      consumer3.should_not be_nil

      client.close
    end

    it "creates producers and consumers for same queue" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer = client.producer("shared_queue")
      consumer = client.consumer("shared_queue")

      producer.should_not be_nil
      consumer.should_not be_nil

      client.close
    end
  end

  describe "close" do
    it "closes all resources gracefully" do
      client = Lavinmq::Client.new("amqp://localhost")

      producer1 = client.producer("queue1")
      producer2 = client.producer("queue2")
      consumer1 = client.consumer("queue1")
      consumer2 = client.consumer("queue2")

      client.close
      # Should complete without errors
    end

    it "handles double close gracefully" do
      client = Lavinmq::Client.new("amqp://localhost")

      client.close
      client.close # Should be no-op
    end

    it "closes even if producer close fails" do
      client = Lavinmq::Client.new("amqp://localhost")
      producer = client.producer("queue1")

      # Even if individual closes fail, client.close should complete
      client.close
    end
  end

  describe "multi-fiber concurrency" do
    it "handles concurrent producer creation" do
      client = Lavinmq::Client.new("amqp://localhost")
      producers = [] of Lavinmq::Producer

      10.times do |i|
        spawn do
          producer = client.producer("queue_#{i}")
          producers << producer
        end
      end

      sleep 100.milliseconds
      client.close
    end

    it "handles concurrent consumer creation" do
      client = Lavinmq::Client.new("amqp://localhost")
      consumers = [] of Lavinmq::Consumer

      10.times do |i|
        spawn do
          consumer = client.consumer("queue_#{i}")
          consumers << consumer
        end
      end

      sleep 100.milliseconds
      client.close
    end

    it "is fiber-safe when creating mixed producers and consumers" do
      client = Lavinmq::Client.new("amqp://localhost")

      20.times do |i|
        spawn do
          if i.even?
            client.producer("queue_#{i}")
          else
            client.consumer("queue_#{i}")
          end
        end
      end

      sleep 200.milliseconds
      client.close
    end
  end

  # Integration tests (require actual AMQP server)
  pending "publishes and consumes messages end-to-end" do
    # Requires LavinMQ/RabbitMQ server
  end

  pending "handles reconnection with active producers and consumers" do
    # Requires connection simulation
  end

  pending "preserves messages during connection loss" do
    # Requires connection interruption simulation
  end

  pending "handles high-throughput multi-fiber scenario" do
    # Requires performance testing setup
  end
end
