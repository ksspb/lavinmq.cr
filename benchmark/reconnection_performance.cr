require "../src/lavinmq"
require "benchmark"

# Benchmark reconnection performance and detection time
class ReconnectionPerformanceBenchmark
  def run
    puts "LavinMQ Reconnection Performance Benchmark (v0.4.2)"
    puts "=" * 60
    puts "Testing hybrid event+poll reconnection strategy"
    puts

    puts "This benchmark requires manual intervention:"
    puts "1. Start with LavinMQ running"
    puts "2. Stop LavinMQ when prompted"
    puts "3. Restart LavinMQ when prompted"
    puts

    config = Lavinmq::Config.new
    client = Lavinmq::Client.new("amqp://localhost", config)

    producer = client.producer(
      "benchmark_queue",
      mode: Lavinmq::Config::PublishMode::FireAndForget,
      buffer_size: 10_000
    )

    # Track connection state
    connected = true
    reconnect_detected = Time::Span.zero
    reconnect_completed = Time::Span.zero

    # Monitor connection in background
    spawn do
      loop do
        current_state = client.connected?
        if connected && !current_state
          # Disconnection detected
          puts "\n⚠️  Disconnection detected!"
          reconnect_detected = Time.monotonic
          connected = false
        elsif !connected && current_state
          # Reconnection detected
          reconnect_completed = Time.monotonic
          detection_time = (reconnect_completed - reconnect_detected).total_milliseconds
          puts "✅ Reconnection completed in #{detection_time.round(2)}ms"
          connected = true
        end
        sleep 0.01.seconds
      end
    end

    # Publish continuously
    messages_published = 0
    messages_buffered = 0

    puts "Publishing messages continuously..."
    puts "(Stop LavinMQ now to test reconnection)"
    puts

    100.times do
      10.times do
        producer.publish("Test message #{messages_published}")
        messages_published += 1
      end

      current_buffer = producer.buffer_size
      if current_buffer > messages_buffered
        messages_buffered = current_buffer
        puts "  Buffered: #{current_buffer} messages (connection down)"
      end

      sleep 0.1.seconds
    end

    puts
    puts "Final Statistics:"
    puts "  Total messages published: #{messages_published}"
    puts "  Peak buffer size: #{messages_buffered}"
    puts "  Final buffer size: #{producer.buffer_size}"

    producer.close
    client.close

    puts
    puts "✅ Reconnection benchmark complete"
  rescue ex
    puts "❌ Error: #{ex.message}"
    puts "   (Requires LavinMQ/RabbitMQ running on localhost:5672)"
  end
end

# Run benchmark
puts "⚠️  Manual reconnection test - requires user interaction"
puts
ReconnectionPerformanceBenchmark.new.run
