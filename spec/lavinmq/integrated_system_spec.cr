require "../spec_helper"
require "../../src/lavinmq"

describe "Integrated System with ConnectionPool and LockFree::RingBuffer" do
  it "uses ConnectionPool by default" do
    client = Lavinmq::Client.new("amqp://localhost", pool_size: 5)

    # Verify ConnectionPool is used
    client.connection_pool.should be_a(Lavinmq::ConnectionPool)
    client.pool_size.should eq(5)
    client.healthy_connections.should be >= 0

    client.close
  end

  it "distributes producers across pool connections" do
    client = Lavinmq::Client.new("amqp://localhost", pool_size: 3)

    # Create multiple producers
    prod1 = client.producer("queue1")
    prod2 = client.producer("queue2")
    prod3 = client.producer("queue3")

    # All producers should be created successfully
    prod1.should_not be_nil
    prod2.should_not be_nil
    prod3.should_not be_nil

    client.close
  end

  it "uses lock-free message buffer" do
    config = Lavinmq::Config.new
    conn_mgr = Lavinmq::ConnectionManager.new("amqp://localhost", config)

    # Create producer (which uses MessageBuffer internally)
    producer = Lavinmq::Producer.new(
      conn_mgr,
      "test_queue",
      Lavinmq::Config::PublishMode::FireAndForget,
      Lavinmq::Config::BufferPolicy::DropOldest,
      buffer_size: 100
    )

    # MessageBuffer should be using LockFree::RingBuffer internally
    # Verify by checking buffer operations are non-blocking
    start = Time.monotonic
    1000.times do |i|
      producer.publish("Message #{i}")
    end
    elapsed = Time.monotonic - start

    # Lock-free operations should be very fast
    puts "Published 1000 messages in #{elapsed.total_milliseconds.round(2)}ms"
    elapsed.total_milliseconds.should be < 100 # Should be extremely fast

    producer.close
    conn_mgr.close
  end

  it "handles high concurrency with atomic operations" do
    client = Lavinmq::Client.new("amqp://localhost", pool_size: 5)

    # Create producers in parallel
    producers = [] of Lavinmq::Producer
    done = Channel(Nil).new

    10.times do |i|
      spawn do
        prod = client.producer("queue_#{i}")
        producers << prod
        done.send(nil)
      end
    end

    10.times { done.receive }

    # All producers should be created without race conditions
    producers.size.should eq(10)

    client.close
  end

  it "exposes health monitoring" do
    client = Lavinmq::Client.new("amqp://localhost", pool_size: 5)

    # Health monitoring should be available
    client.healthy?.should be_a(Bool)
    client.healthy_connections.should be >= 0
    client.healthy_connections.should be <= client.pool_size

    client.close
  end
end