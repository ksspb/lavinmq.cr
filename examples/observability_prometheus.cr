require "../src/lavinmq"

# Example: Using Observability Hooks for Prometheus Metrics
#
# This example demonstrates how to use the LavinMQ observability hooks
# to track metrics for Prometheus or other monitoring systems.

# Simulate Prometheus metrics (in real code, use crometheus shard)
module PrometheusMetrics
  @@messages_total = Hash(String, Int64).new(0_i64)
  @@messages_dropped_total = Hash(String, Int64).new(0_i64)
  @@buffer_depth_gauge = Hash(String, Int32).new(0)
  @@connection_state_gauge = 0

  def self.increment(metric : String, labels : Hash(String, String) = {} of String => String)
    key = "#{metric}:#{labels.to_s}"
    @@messages_total[key] += 1
    puts "📊 #{metric}{#{labels.map { |k, v| "#{k}=\"#{v}\"" }.join(", ")}} = #{@@messages_total[key]}"
  end

  def self.increment_dropped(reason : String, queue : String)
    key = "dropped:#{queue}:#{reason}"
    @@messages_dropped_total[key] += 1
    puts "📉 amqp_messages_dropped_total{queue=\"#{queue}\", reason=\"#{reason}\"} = #{@@messages_dropped_total[key]}"
  end

  def self.set_buffer_depth(queue : String, depth : Int32)
    @@buffer_depth_gauge[queue] = depth
    puts "📏 amqp_buffer_depth{queue=\"#{queue}\"} = #{depth}"
  end

  def self.set_connection_state(state : Int32)
    @@connection_state_gauge = state
    puts "🔌 amqp_connection_state = #{state} (0=disconnected, 1=connected)"
  end
end

# Setup client
client = Lavinmq::Client.new("amqp://localhost")

# Setup producer with observability hooks
producer = client.producer(
  "orders",
  mode: :confirm,
  buffer_policy: :drop_oldest
)

# 1. Track message confirmations
producer.on_confirm do |message, queue|
  PrometheusMetrics.increment("amqp_messages_total", {
    "queue"  => queue,
    "result" => "confirmed",
  })
end

# 2. Track message nacks
producer.on_nack do |message, queue|
  PrometheusMetrics.increment("amqp_messages_total", {
    "queue"  => queue,
    "result" => "nack",
  })
end

# 3. Track publish errors
producer.on_error do |message, queue, exception|
  PrometheusMetrics.increment("amqp_messages_total", {
    "queue"  => queue,
    "result" => "error",
  })
  puts "❌ Error publishing to #{queue}: #{exception.message}"
end

# 4. Track message drops with reasons
producer.on_drop do |message, queue, reason|
  reason_str = case reason
               when Lavinmq::Config::DropReason::BufferFull
                 "buffer_full"
               when Lavinmq::Config::DropReason::Disconnected
                 "disconnected"
               when Lavinmq::Config::DropReason::Closed
                 "closed"
               when Lavinmq::Config::DropReason::TTLExpired
                 "ttl_expired"
               else
                 "unknown"
               end
  PrometheusMetrics.increment_dropped(reason_str, queue)
end

# 5. Track real-time buffer depth
# In production, you'd expose this via a Prometheus endpoint
spawn do
  loop do
    depth = producer.buffer_size
    capacity = producer.buffer_capacity
    PrometheusMetrics.set_buffer_depth("orders", depth)
    sleep 5.seconds
  end
end

# 6. Track connection state changes
client.connection_manager.on_state_change do |state|
  state_value = case state
                when Lavinmq::Config::ConnectionState::Connected
                  1
                when Lavinmq::Config::ConnectionState::Connecting,
                     Lavinmq::Config::ConnectionState::Reconnecting
                  0
                when Lavinmq::Config::ConnectionState::Closed
                  -1
                else
                  0
                end
  PrometheusMetrics.set_connection_state(state_value)
end

# 7. Track reconnection attempts for alerting
client.connection_manager.on_reconnect_attempt do |attempt, delay|
  puts "🔄 Reconnection attempt #{attempt + 1}, delay: #{delay}s"
  PrometheusMetrics.increment("amqp_reconnection_attempts_total", {
    "attempt" => attempt.to_s,
  })
end

# Connect and publish some test messages
begin
  client.connect

  puts "\n📤 Publishing test messages..."

  10.times do |i|
    producer.publish("Order #{i}")
    sleep 100.milliseconds
  end

  puts "\n✅ All messages published"
  puts "📊 Current buffer state:"
  puts "   Size: #{producer.buffer_size}"
  puts "   Capacity: #{producer.buffer_capacity}"

  sleep 2.seconds
ensure
  client.close
end
