require "../src/lavinmq"
require "benchmark"

# Benchmark latency distribution to find p50, p95, p99
class LatencyDistributionBenchmark
  def run
    puts "LavinMQ Latency Distribution Benchmark (v0.4.2)"
    puts "=" * 60
    puts

    config = Lavinmq::Config.new
    client = Lavinmq::Client.new("amqp://localhost", config)

    producer = client.producer(
      "benchmark_queue",
      mode: Lavinmq::Config::PublishMode::FireAndForget,
      buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest
    )

    # Warmup
    100.times { producer.publish("warmup") }
    sleep 0.1

    # Measure individual publish latencies
    message_count = 10_000
    latencies = Array(Float64).new(message_count)

    puts "Measuring #{message_count} individual publish latencies..."

    message_count.times do |i|
      start = Time.monotonic
      producer.publish("Message #{i}")
      finish = Time.monotonic
      latencies << (finish - start).total_microseconds
    end

    # Sort for percentile calculation
    latencies.sort!

    # Calculate statistics
    min = latencies.first
    max = latencies.last
    avg = latencies.sum / latencies.size
    p50 = latencies[latencies.size // 2]
    p95 = latencies[(latencies.size * 95) // 100]
    p99 = latencies[(latencies.size * 99) // 100]
    p999 = latencies[(latencies.size * 999) // 1000]

    puts
    puts "Latency Distribution (in microseconds):"
    puts "  Min:    #{min.round(3)}μs"
    puts "  Avg:    #{avg.round(3)}μs"
    puts "  p50:    #{p50.round(3)}μs"
    puts "  p95:    #{p95.round(3)}μs"
    puts "  p99:    #{p99.round(3)}μs"
    puts "  p99.9:  #{p999.round(3)}μs"
    puts "  Max:    #{max.round(3)}μs"
    puts

    # Calculate percentage under 1ms
    under_1ms = latencies.count { |l| l < 1000 }
    percentage = (under_1ms.to_f / latencies.size * 100)
    puts "Messages under 1ms: #{percentage.round(2)}% (#{under_1ms}/#{message_count})"

    producer.close
    client.close

    puts
    puts "✅ Latency distribution benchmark complete"
  rescue ex
    puts "❌ Error: #{ex.message}"
    puts "   (Requires LavinMQ/RabbitMQ running on localhost:5672)"
  end
end

# Run benchmark
LatencyDistributionBenchmark.new.run
