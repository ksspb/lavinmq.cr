require "../src/lavinmq"
require "benchmark"

# Benchmark concurrent publisher performance
class ConcurrentPublishersBenchmark
  def run
    puts "LavinMQ Concurrent Publishers Benchmark (v0.4.2)"
    puts "=" * 60
    puts

    config = Lavinmq::Config.new
    client = Lavinmq::Client.new("amqp://localhost", config)

    # Test different concurrency levels
    [1, 10, 50, 100].each do |fiber_count|
      messages_per_fiber = 1000
      total_messages = fiber_count * messages_per_fiber

      producer = client.producer(
        "benchmark_queue",
        mode: Lavinmq::Config::PublishMode::FireAndForget,
        buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest,
        buffer_size: total_messages
      )

      puts "Testing #{fiber_count} concurrent fibers (#{total_messages} total messages):"

      elapsed = Benchmark.realtime do
        done = Channel(Nil).new

        fiber_count.times do |i|
          spawn do
            messages_per_fiber.times do |j|
              producer.publish("Message #{i}-#{j}")
            end
            done.send(nil)
          end
        end

        # Wait for all fibers
        fiber_count.times { done.receive }
      end

      throughput = total_messages / elapsed.total_seconds
      latency_us = (elapsed.total_seconds / total_messages) * 1_000_000

      puts "  Time: #{elapsed.total_milliseconds.round(2)}ms"
      puts "  Throughput: #{throughput.round(0).format} msg/sec"
      puts "  Avg Latency: #{latency_us.round(3)}μs per message"
      puts "  Buffer size: #{producer.buffer_size}"
      puts

      producer.close
      sleep 0.1
    end

    client.close
    puts "✅ Concurrent publishers benchmark complete"
  rescue ex
    puts "❌ Error: #{ex.message}"
    puts "   (Requires LavinMQ/RabbitMQ running on localhost:5672)"
  end
end

# Run benchmark
ConcurrentPublishersBenchmark.new.run
