require "../src/lavinmq"
require "benchmark"

# Benchmark to compare atomic vs mutex performance

class AtomicProducerBenchmark
  def run
    config = Lavinmq::Config.new
    conn_mgr = Lavinmq::ConnectionManager.new("amqp://guest:guest@localhost", config)

    puts "LavinMQ Atomic Performance Benchmark"
    puts "=" * 50
    puts

    # Test different concurrency levels
    [1, 10, 100, 1000].each do |fiber_count|
      messages_per_fiber = 1000
      total_messages = fiber_count * messages_per_fiber

      producer = Lavinmq::Producer.new(
        conn_mgr,
        "benchmark_queue",
        Lavinmq::Config::PublishMode::FireAndForget,
        Lavinmq::Config::BufferPolicy::DropOldest,
        buffer_size: total_messages
      )

      puts "Testing with #{fiber_count} concurrent publishers (#{total_messages} total messages):"

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
      latency_per_msg = (elapsed.total_seconds / total_messages) * 1_000_000 # in microseconds

      puts "  Time: #{(elapsed.total_milliseconds).round(2)}ms"
      puts "  Throughput: #{throughput.round(0)} msg/sec"
      puts "  Latency per message: #{latency_per_msg.round(2)}μs"
      puts "  Messages buffered: #{producer.buffer_size}"
      puts

      producer.close
    end

    conn_mgr.close
  rescue ex
    puts "Note: Benchmark requires RabbitMQ/LavinMQ running locally"
    puts "Error: #{ex.message}"
  end
end

# Compare mutex vs atomic performance directly
class MutexVsAtomicBenchmark
  def run
    puts "Direct Mutex vs Atomic Comparison"
    puts "=" * 50
    puts

    iterations = 1_000_000
    fiber_count = 100

    # Test mutex
    mutex_counter = 0
    mutex = Mutex.new

    mutex_time = Benchmark.realtime do
      done = Channel(Nil).new

      fiber_count.times do
        spawn do
          (iterations // fiber_count).times do
            mutex.synchronize { mutex_counter += 1 }
          end
          done.send(nil)
        end
      end

      fiber_count.times { done.receive }
    end

    # Test atomic
    atomic_counter = Atomic(Int32).new(0)

    atomic_time = Benchmark.realtime do
      done = Channel(Nil).new

      fiber_count.times do
        spawn do
          (iterations // fiber_count).times do
            atomic_counter.add(1)
          end
          done.send(nil)
        end
      end

      fiber_count.times { done.receive }
    end

    puts "Results for #{iterations} operations with #{fiber_count} fibers:"
    puts
    puts "Mutex:"
    puts "  Time: #{(mutex_time.total_milliseconds).round(2)}ms"
    puts "  Ops/sec: #{(iterations / mutex_time.total_seconds).round(0)}"
    puts "  Final value: #{mutex_counter}"
    puts
    puts "Atomic:"
    puts "  Time: #{(atomic_time.total_milliseconds).round(2)}ms"
    puts "  Ops/sec: #{(iterations / atomic_time.total_seconds).round(0)}"
    puts "  Final value: #{atomic_counter.get}"
    puts
    puts "Speedup: #{(mutex_time.total_seconds / atomic_time.total_seconds).round(2)}x faster with atomics"
  end
end

# Run benchmarks
puts "Starting benchmarks..."
puts

MutexVsAtomicBenchmark.new.run
puts
AtomicProducerBenchmark.new.run
