require "../spec_helper"
require "../../src/lavinmq"

describe "Lavinmq::ConnectionPool Integration" do
  describe "high throughput with connection pool" do
    it "handles 1000+ msg/sec across multiple producers" do
      config = Lavinmq::Config.new
      pool = Lavinmq::ConnectionPool.new("amqp://guest:guest@localhost", pool_size: 5, config: config)

      # Track metrics
      messages_sent = Atomic(Int32).new(0)
      errors = Atomic(Int32).new(0)
      start_time = Time.monotonic

      # Create multiple producers using the pool
      producers = 10.times.map do |i|
        # Each producer gets a connection from pool
        Lavinmq::Producer.new(
          pool.connection_manager(i % pool.size),
          "test_queue_#{i}",
          Lavinmq::Config::PublishMode::FireAndForget,
          Lavinmq::Config::BufferPolicy::DropOldest,
          buffer_size: 1000
        )
      end.to_a

      # Simulate high throughput publishing
      done = Channel(Nil).new
      message_count = 10000
      producer_count = producers.size

      producer_count.times do |i|
        spawn do
          producer = producers[i]
          (message_count // producer_count).times do |j|
            begin
              producer.publish("High throughput message #{i}-#{j}")
              messages_sent.add(1)
            rescue ex
              errors.add(1)
            end
            Fiber.yield if j % 100 == 0 # Yield periodically
          end
          done.send(nil)
        end
      end

      # Wait for all producers
      producer_count.times { done.receive }

      elapsed = Time.monotonic - start_time
      throughput = messages_sent.get / elapsed.total_seconds

      puts "=" * 60
      puts "CONNECTION POOL PERFORMANCE TEST"
      puts "=" * 60
      puts "Pool size: #{pool.size} connections"
      puts "Healthy connections: #{pool.healthy_count}"
      puts "Messages sent: #{messages_sent.get}/#{message_count}"
      puts "Errors: #{errors.get}"
      puts "Time elapsed: #{elapsed.total_milliseconds.round(2)}ms"
      puts "Throughput: #{throughput.round(2)} msg/sec"
      puts "=" * 60

      # Should achieve target throughput of 1000+ msg/sec
      throughput.should be > 1000

      # Cleanup
      producers.each { |p| p.close rescue nil }
      pool.close
    end

    it "maintains performance under pod failure simulation" do
      config = Lavinmq::Config.new
      pool = Lavinmq::ConnectionPool.new("amqp://guest:guest@localhost", pool_size: 8, config: config)

      messages_before_failure = Atomic(Int32).new(0)
      messages_during_failure = Atomic(Int32).new(0)
      messages_after_recovery = Atomic(Int32).new(0)
      phase = Atomic(Int32).new(0) # 0=before, 1=during, 2=after

      # Create producers
      producers = 5.times.map do |i|
        Lavinmq::Producer.new(
          pool.connection_manager(i % pool.size),
          "resilience_queue_#{i}",
          Lavinmq::Config::PublishMode::FireAndForget,
          Lavinmq::Config::BufferPolicy::DropOldest,
          buffer_size: 500
        )
      end.to_a

      # Publishing fiber
      done = Channel(Nil).new
      spawn do
        1000.times do |i|
          producers.sample.publish("Resilience test #{i}")

          case phase.get
          when 0
            messages_before_failure.add(1)
          when 1
            messages_during_failure.add(1)
          when 2
            messages_after_recovery.add(1)
          end

          sleep 1.millisecond # Controlled rate
        end
        done.send(nil)
      end

      # Simulate pod failures
      spawn do
        sleep 200.milliseconds
        phase.set(1) # During failure phase

        # "Kill" some connections (simulate pod failure)
        3.times do |i|
          pool.connection_manager(i).close rescue nil
        end

        sleep 300.milliseconds
        phase.set(2) # After recovery phase

        # Pool should auto-recover
        sleep 300.milliseconds
        done.send(nil)
      end

      # Wait for completion
      2.times { done.receive }

      puts "=" * 60
      puts "RESILIENCE TEST (POD FAILURE SIMULATION)"
      puts "=" * 60
      puts "Messages before failure: #{messages_before_failure.get}"
      puts "Messages during failure: #{messages_during_failure.get}"
      puts "Messages after recovery: #{messages_after_recovery.get}"
      puts "Healthy connections at end: #{pool.healthy_count}/#{pool.size}"
      puts "=" * 60

      # Should continue sending even during failures
      messages_during_failure.get.should be > 0
      messages_after_recovery.get.should be > 0

      # Cleanup
      producers.each { |p| p.close rescue nil }
      pool.close
    end
  end

  describe "connection distribution" do
    it "distributes load evenly across pool connections" do
      config = Lavinmq::Config.new
      pool_size = 5
      pool = Lavinmq::ConnectionPool.new("amqp://guest:guest@localhost", pool_size: pool_size, config: config)

      connection_usage = Hash(Int32, Int32).new(0)
      mutex = Mutex.new

      # Track which connections are used
      requests = 10000
      done = Channel(Nil).new

      10.times do
        spawn do
          (requests // 10).times do
            # Get connection and track which pool index is used
            if conn = pool.connection?
              # Find which connection this is (simplified tracking)
              pool_size.times do |i|
                if pool.connection_manager(i).connection? == conn
                  mutex.synchronize { connection_usage[i] = connection_usage[i] + 1 }
                  break
                end
              end
            end
          end
          done.send(nil)
        end
      end

      10.times { done.receive }

      # Calculate distribution statistics
      total = connection_usage.values.sum
      avg = total // pool_size
      max_deviation = connection_usage.values.map { |v| (v - avg).abs }.max

      puts "=" * 60
      puts "LOAD DISTRIBUTION TEST"
      puts "=" * 60
      puts "Connection usage distribution:"
      connection_usage.each do |idx, count|
        percentage = (count * 100.0 / total).round(2)
        puts "  Connection ##{idx}: #{count} requests (#{percentage}%)"
      end
      puts "Average per connection: #{avg}"
      puts "Max deviation from average: #{max_deviation}"
      puts "=" * 60

      # Should have relatively even distribution (within 20% of average)
      max_deviation.should be < (avg * 0.2)

      pool.close
    end
  end
end