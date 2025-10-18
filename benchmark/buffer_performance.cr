require "../src/lavinmq"
require "benchmark"

# Benchmark buffer enqueue/dequeue performance
class BufferPerformanceBenchmark
  def run
    puts "LavinMQ Buffer Performance Benchmark (v0.4.2)"
    puts "=" * 60
    puts "Testing lock-free ring buffer performance"
    puts

    # Test different buffer operations
    [1_000, 10_000, 100_000].each do |operation_count|
      buffer = Lavinmq::MessageBuffer.new(operation_count)

      puts "Buffer capacity: #{operation_count} messages"

      # Test enqueue
      enqueue_time = Benchmark.realtime do
        operation_count.times do |i|
          buffer.enqueue("Message #{i}")
        end
      end

      enqueue_throughput = operation_count / enqueue_time.total_seconds
      enqueue_latency = (enqueue_time.total_seconds / operation_count) * 1_000_000

      puts "  Enqueue:"
      puts "    Time: #{enqueue_time.total_milliseconds.round(2)}ms"
      puts "    Throughput: #{enqueue_throughput.round(0).format} ops/sec"
      puts "    Avg Latency: #{enqueue_latency.round(3)}μs per operation"

      # Test drain
      drain_time = Benchmark.realtime do
        messages = buffer.drain
      end

      drain_throughput = operation_count / drain_time.total_seconds
      drain_latency = (drain_time.total_seconds / operation_count) * 1_000_000

      puts "  Drain:"
      puts "    Time: #{drain_time.total_milliseconds.round(2)}ms"
      puts "    Throughput: #{drain_throughput.round(0).format} ops/sec"
      puts "    Avg Latency: #{drain_latency.round(3)}μs per operation"

      puts
    end

    # Test concurrent enqueue
    puts "Concurrent Enqueue Test (100 fibers, 10k messages):"
    fiber_count = 100
    messages_per_fiber = 100
    total_messages = fiber_count * messages_per_fiber

    buffer = Lavinmq::MessageBuffer.new(total_messages)

    concurrent_time = Benchmark.realtime do
      done = Channel(Nil).new

      fiber_count.times do |i|
        spawn do
          messages_per_fiber.times do |j|
            buffer.enqueue("Message #{i}-#{j}")
          end
          done.send(nil)
        end
      end

      fiber_count.times { done.receive }
    end

    concurrent_throughput = total_messages / concurrent_time.total_seconds
    concurrent_latency = (concurrent_time.total_seconds / total_messages) * 1_000_000

    puts "  Time: #{concurrent_time.total_milliseconds.round(2)}ms"
    puts "  Throughput: #{concurrent_throughput.round(0).format} ops/sec"
    puts "  Avg Latency: #{concurrent_latency.round(3)}μs per operation"
    puts "  Buffer size: #{buffer.size}"
    puts

    puts "✅ Buffer performance benchmark complete"
  end
end

# Run benchmark
BufferPerformanceBenchmark.new.run
