# LavinMQ Client Library

A robust, production-ready Crystal client library for LavinMQ/RabbitMQ with automatic reconnection, message buffering, and multi-fiber support.

## Features

- 🔄 **Automatic Reconnection** - Exponential backoff reconnection (100ms → 200ms → 400ms... up to 30s)
- 📦 **Message Buffering** - Ring buffer with 10,000 message capacity prevents message loss during outages
- 🔥 **Two Publishing Modes**:
  - **Fire-and-forget**: Maximum throughput with automatic buffering
  - **Confirm**: Publisher confirms for guaranteed delivery
- ⚙️ **Configurable Buffer Policies**:
  - Block: Wait for buffer space (default for confirm mode)
  - Raise: Throw error when buffer full
  - DropOldest: Drop oldest messages when full
- 🧵 **Multi-fiber Safe** - All operations are fiber-safe with proper synchronization
- ✅ **Independent Ack Tracking** - Each consumer gets dedicated channel with separate ack tracking
- 🔌 **Auto-recovery** - Consumers and producers automatically recover after reconnection

## Installation

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  lavinmq:
    github: ksspb/lavinmq.cr
    version: ~> 0.1.0
  amqp-client:
    github: cloudamqp/amqp-client.cr
```

2. Run `shards install`

## Usage

### Basic Example

```crystal
require "lavinmq"

# Create client
client = Lavinmq::Client.new("amqp://localhost")

# Create fire-and-forget producer
producer = client.producer(
  "orders",
  mode: Lavinmq::Config::PublishMode::FireAndForget
)
producer.publish("order data")

# Create confirm mode producer with custom buffer policy
reliable_producer = client.producer(
  "critical-orders",
  mode: Lavinmq::Config::PublishMode::Confirm,
  buffer_policy: Lavinmq::Config::BufferPolicy::Raise
)
reliable_producer.publish("important order")

# Create consumer with auto-recovery
consumer = client.consumer("orders", prefetch: 100)
consumer.subscribe do |msg|
  puts "Processing: #{msg.body_io.to_s}"
  msg.ack  # Acknowledge message
end

# Clean shutdown
client.close
```

### Advanced Configuration

```crystal
# Custom configuration
config = Lavinmq::Config.new
config.buffer_size = 5000  # Custom buffer size
config.reconnect_initial_delay = 0.2  # 200ms initial delay
config.reconnect_max_delay = 60  # Max 60s between retries
config.reconnect_multiplier = 2.0  # Double delay each attempt

client = Lavinmq::Client.new("amqp://localhost", config)
```

### Producer Modes

#### Fire-and-Forget Mode
- Maximum throughput
- Messages buffered during disconnection
- Automatically drops oldest when buffer reaches 10k limit

```crystal
producer = client.producer(
  "queue",
  mode: Lavinmq::Config::PublishMode::FireAndForget
)
```

#### Confirm Mode with Buffer Policies
- Publisher confirmations for guaranteed delivery
- Configurable buffer behavior:

```crystal
# Block until space available (default)
producer = client.producer(
  "queue",
  mode: Lavinmq::Config::PublishMode::Confirm,
  buffer_policy: Lavinmq::Config::BufferPolicy::Block
)

# Raise error when buffer full
producer = client.producer(
  "queue",
  mode: Lavinmq::Config::PublishMode::Confirm,
  buffer_policy: Lavinmq::Config::BufferPolicy::Raise
)

# Drop oldest messages when full
producer = client.producer(
  "queue",
  mode: Lavinmq::Config::PublishMode::Confirm,
  buffer_policy: Lavinmq::Config::BufferPolicy::DropOldest
)
```

### Consumer with Acknowledgments

```crystal
# Manual ack mode (recommended)
consumer = client.consumer("orders", prefetch: 100)
consumer.subscribe(no_ack: false) do |msg|
  begin
    process_order(msg.body_io.to_s)
    msg.ack  # Acknowledge successful processing
  rescue ex
    msg.nack(requeue: true)  # Requeue on error
  end
end

# No-ack mode (auto-ack)
consumer = client.consumer("logs")
consumer.subscribe(no_ack: true) do |msg|
  log(msg.body_io.to_s)
end
```

### Multiple Acknowledgment

```crystal
# Ack multiple messages up to delivery tag
consumer.ack(delivery_tag, multiple: true)

# Nack multiple messages
consumer.nack(delivery_tag, multiple: true, requeue: true)
```

## Architecture

### Core Components

1. **ConnectionManager** - Handles connection lifecycle with automatic reconnection
2. **MessageBuffer** - Ring buffer for message buffering during outages
3. **Producer** - Publishes messages with buffering and confirm support
4. **Consumer** - Consumes messages with auto-recovery and ack tracking
5. **AckTracker** - Tracks unacknowledged messages per consumer
6. **Client** - Main API for creating producers and consumers

### Reconnection Strategy

- **Initial delay**: 100ms
- **Multiplier**: 2.0 (doubles each attempt)
- **Maximum delay**: 30 seconds
- **Behavior**: Exponential backoff with ceiling

Example: 100ms → 200ms → 400ms → 800ms → 1.6s → 3.2s → 6.4s → 12.8s → 25.6s → 30s → 30s...

### Message Buffer

- **Type**: Ring buffer (Deque-based)
- **Default capacity**: 10,000 messages
- **Behavior when full**:
  - Fire-and-forget: Always drops oldest
  - Confirm mode: Respects buffer policy (Block/Raise/DropOldest)
- **Automatic flushing**: Messages flushed on reconnection

### Fiber Safety

All components are fiber-safe using:
- `Mutex` for critical sections
- `Channel` for fiber communication
- Independent channels per consumer for ack isolation

## Testing

Run the test suite:

```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/lavinmq/producer_spec.cr

# Run with line number
crystal spec spec/lavinmq/producer_spec.cr:25
```

**Note**: Integration tests requiring an actual LavinMQ/RabbitMQ server are marked as `pending`. Unit tests verify all core functionality without external dependencies.

## Development

```bash
# Install dependencies
shards install

# Format code
crystal tool format src/ spec/

# Build library
crystal build src/lavinmq.cr
```

## License

MIT License - see LICENSE file for details

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests following TDD (red-green-refactor)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

## Contributors

- [Sergey Konopatov](https://github.com/ksspb) - creator and maintainer

## Support

- Crystal >= 1.17.1
- LavinMQ / RabbitMQ (AMQP 0-9-1 compatible)
