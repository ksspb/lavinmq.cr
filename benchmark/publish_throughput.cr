require "../src/lavinmq"
require "benchmark"

# Benchmark publish throughput with current architecture
class PublishThroughputBenchmark
  def run
    puts "LavinMQ Publish Throughput Benchmark (v0.4.2)"
    puts "=" * 60
    puts

    config = Lavinmq::Config.new
    client = Lavinmq::Client.new("amqp://localhost", config)

    # Test with fire-and-forget mode (maximum throughput)
    producer = client.producer(
      "benchmark_queue",
      mode: Lavinmq::Config::PublishMode::FireAndForget,
      buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest,
      buffer_size: 100_000
    )

    # Warm up
    100.times { producer.publish("warmup") }
    sleep 0.1

    # Test different message counts
    [1_000, 10_000, 100_000].each do |message_count|
      puts "Publishing #{message_count} messages:"

      elapsed = Benchmark.realtime do
        message_count.times do |i|
          producer.publish("Message #{i}")
        end
      end

      throughput = message_count / elapsed.total_seconds
      latency_us = (elapsed.total_seconds / message_count) * 1_000_000

      puts "  Time: #{elapsed.total_milliseconds.round(2)}ms"
      puts "  Throughput: #{throughput.round(0).format} msg/sec"
      puts "  Avg Latency: #{latency_us.round(3)}μs per message"
      puts "  Buffer size: #{producer.buffer_size}"
      puts

      # Small delay between tests
      sleep 0.2
    end

    producer.close
    client.close

    puts "✅ Throughput benchmark complete"
  rescue ex
    puts "❌ Error: #{ex.message}"
    puts "   (Requires LavinMQ/RabbitMQ running on localhost:5672)"
  end
end

# Run benchmark
PublishThroughputBenchmark.new.run
