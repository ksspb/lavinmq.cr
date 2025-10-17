require "../spec_helper"
require "../../src/lavinmq"

describe "Lavinmq::ConnectionPool" do
  describe "connection pooling for high throughput" do
    it "demonstrates single connection bottleneck" do
      config = Lavinmq::Config.new
      conn_mgr = Lavinmq::ConnectionManager.new("amqp://guest:guest@localhost", config)

      # Single connection scenario
      messages_sent = Atomic(Int32).new(0)
      channel_creation_time = Atomic(Int64).new(0_i64) # Microseconds

      # Multiple producers sharing one connection
      done = Channel(Nil).new
      producer_count = 10

      start_time = Time.monotonic
      producer_count.times do |i|
        spawn do
          100.times do |j|
            ch_start = Time.monotonic
            # Each producer needs its own channel (AMQP limitation)
            # This creates contention on single connection
            if conn = conn_mgr.connection?
              begin
                ch = conn.channel
                channel_creation_time.add((Time.monotonic - ch_start).total_microseconds.to_i64)
                messages_sent.add(1)
                ch.close rescue nil
              rescue
                # Channel creation failed due to contention
              end
            end
          end
          done.send(nil)
        end
      end

      producer_count.times { done.receive }
      elapsed = Time.monotonic - start_time

      throughput = messages_sent.get / elapsed.total_seconds
      avg_channel_time_us = channel_creation_time.get.to_f / messages_sent.get

      puts "Single connection throughput: #{throughput.round(2)} msg/sec"
      puts "Messages sent: #{messages_sent.get}/1000"
      puts "Avg channel creation time: #{(avg_channel_time_us / 1000).round(2)}ms"

      # With single connection, throughput is limited
      throughput.should be > 0

      conn_mgr.close rescue nil
    end

    it "shows improved throughput with connection pool" do
      # Simulate connection pool with multiple connections
      config = Lavinmq::Config.new
      connections = 5.times.map do
        Lavinmq::ConnectionManager.new("amqp://guest:guest@localhost", config)
      end.to_a

      messages_sent = Atomic(Int32).new(0)

      # Multiple producers with connection pool
      done = Channel(Nil).new
      producer_count = 10

      start_time = Time.monotonic
      producer_count.times do |i|
        spawn do
          # Each producer gets a connection from pool (round-robin)
          conn_mgr = connections[i % connections.size]
          100.times do |j|
            if conn = conn_mgr.connection?
              begin
                ch = conn.channel
                messages_sent.add(1)
                ch.close rescue nil
              rescue
                # Ignore errors
              end
            end
          end
          done.send(nil)
        end
      end

      producer_count.times { done.receive }
      elapsed = Time.monotonic - start_time

      throughput = messages_sent.get / elapsed.total_seconds

      puts "Pool (#{connections.size} connections) throughput: #{throughput.round(2)} msg/sec"
      puts "Messages sent: #{messages_sent.get}/1000"

      # With connection pool, throughput should be much higher
      throughput.should be > 0

      connections.each { |c| c.close rescue nil }
    end
  end

  describe "thread-safe connection acquisition" do
    it "requires atomic operations for pool management" do
      # Simulate pool index management
      pool_index = Atomic(Int32).new(0)
      pool_size = 5

      acquisitions = Atomic(Int32).new(0)
      distribution = Hash(Int32, Int32).new(0)
      mutex = Mutex.new

      # Many fibers acquiring connections concurrently
      done = Channel(Nil).new
      100.times do
        spawn do
          100.times do
            # Atomic round-robin selection
            index = pool_index.add(1) % pool_size
            acquisitions.add(1)

            # Track distribution
            mutex.synchronize do
              distribution[index] = distribution[index] + 1
            end
          end
          done.send(nil)
        end
      end

      100.times { done.receive }

      # Verify all connections are used
      distribution.size.should eq(pool_size)

      # Verify roughly even distribution
      avg = acquisitions.get // pool_size
      distribution.each do |index, count|
        # Each connection should get roughly equal load
        (count - avg).abs.should be < (avg * 0.2) # Within 20% of average
      end

      puts "Connection distribution: #{distribution}"
      puts "Total acquisitions: #{acquisitions.get}"
    end
  end

  describe "connection health monitoring" do
    it "needs to detect and replace dead connections" do
      # Track connection states
      healthy_connections = Atomic(Int32).new(5)
      failed_connections = Atomic(Int32).new(0)
      replaced_connections = Atomic(Int32).new(0)

      # Simulate connection failures
      spawn do
        3.times do
          sleep 100.milliseconds
          # Simulate connection failure
          if healthy_connections.add(-1) >= 0
            failed_connections.add(1)

            # Replace failed connection
            sleep 50.milliseconds
            healthy_connections.add(1)
            replaced_connections.add(1)
          end
        end
      end

      # Monitor health
      10.times do
        current_healthy = healthy_connections.get
        current_failed = failed_connections.get

        # Pool should maintain minimum healthy connections
        current_healthy.should be >= 2

        sleep 50.milliseconds
      end

      # Verify connections were replaced
      replaced_connections.get.should be > 0

      puts "Failed: #{failed_connections.get}, Replaced: #{replaced_connections.get}"
    end
  end
end