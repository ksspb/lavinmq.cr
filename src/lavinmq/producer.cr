module Lavinmq
  # Producer for publishing messages with buffering and confirmation support
  class Producer
    Log = ::Log.for(self)

    # Maximum number of flush retry attempts before dropping a message
    MAX_FLUSH_RETRIES = 3

    @mode : Config::PublishMode
    @buffer_policy : Config::BufferPolicy
    @buffer : MessageBuffer
    @client : Client
    @queue_name : String
    @channel : AMQP::Client::Channel?
    @closed : Bool = false
    @mutex : Mutex
    @flush_fiber : Fiber?
    @retry_counts : Hash(String, Int32) = Hash(String, Int32).new

    # Observability callbacks
    @on_drop : Proc(String, String, Config::DropReason, Nil)?
    @on_confirm : Proc(String, String, Nil)?
    @on_nack : Proc(String, String, Nil)?
    @on_error : Proc(String, String, Exception, Nil)?

    def initialize(
      @client : Client,
      @queue_name : String,
      @mode : Config::PublishMode = Config::PublishMode::Confirm,
      @buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = Config::DEFAULT_BUFFER_SIZE,
    )
      @buffer = MessageBuffer.new(buffer_size)
      @mutex = Mutex.new
      @channel = nil

      # Start flush fiber to send buffered messages
      @flush_fiber = spawn { flush_loop }
    end

    # Publish a message (non-blocking, zero latency)
    def publish(message : String) : Nil
      return if @closed

      # Try fast path with cached channel
      @mutex.synchronize do
        if ch = @channel
          unless ch.closed?
            begin
              send_message_fast(ch, message)
              return
            rescue ex
              Log.debug(exception: ex) { "Fast path failed, queuing message" }
              @channel = nil
            end
          else
            @channel = nil
          end
        end
      end

      # Queue for background sending (non-blocking)
      handle_buffering(message)
    end

    # Close producer
    def close : Nil
      @mutex.synchronize do
        return if @closed
        @closed = true
      end

      # Flush remaining messages
      flush_buffered_messages

      # Close channel
      @mutex.synchronize do
        @channel.try &.close rescue nil
        @channel = nil
      end

      Log.info { "Producer closed for queue: #{@queue_name}" }
    end

    # Set callback for message drops
    def on_drop(&block : String, String, Config::DropReason ->)
      @on_drop = block
    end

    # Set callback for confirmed messages
    def on_confirm(&block : String, String ->)
      @on_confirm = block
    end

    # Set callback for nacked messages
    def on_nack(&block : String, String ->)
      @on_nack = block
    end

    # Set callback for publish errors
    def on_error(&block : String, String, Exception ->)
      @on_error = block
    end

    # Get current buffer size
    def buffer_size : Int32
      @buffer.size
    end

    # Get buffer capacity
    def buffer_capacity : Int32
      @buffer.capacity
    end

    private def has_connection? : Bool
      @client.connected?
    end

    private def handle_buffering(message : String) : Nil
      case @mode
      when Config::PublishMode::FireAndForget
        # Fire-and-forget: buffer and drop oldest if full
        if dropped = @buffer.enqueue(message)
          @on_drop.try &.call(dropped, @queue_name, Config::DropReason::BufferFull)
        end
      when Config::PublishMode::Confirm
        # Confirm mode: apply buffer policy
        case @buffer_policy
        when Config::BufferPolicy::DropOldest
          if dropped = @buffer.enqueue(message)
            @on_drop.try &.call(dropped, @queue_name, Config::DropReason::BufferFull)
          end
        when Config::BufferPolicy::Raise
          if @buffer.full?
            @on_drop.try &.call(message, @queue_name, Config::DropReason::BufferFull)
            raise BufferFullError.new("Producer buffer full for queue: #{@queue_name}")
          end
          @buffer.enqueue(message)
        when Config::BufferPolicy::Block
          # Non-blocking: drop oldest to make space (maintains zero-latency guarantee)
          # Note: "Block" policy now drops oldest rather than blocking to prevent latency
          if dropped = @buffer.enqueue(message)
            @on_drop.try &.call(dropped, @queue_name, Config::DropReason::BufferFull)
          end
        end
      end
    end

    # Send message using provided channel (fast path, no connection retrieval)
    private def send_message_fast(channel : AMQP::Client::Channel, message : String) : Nil
      queue = channel.queue(@queue_name)

      case @mode
      when Config::PublishMode::FireAndForget
        queue.publish(message)
        # Fire-and-forget doesn't have confirmation
      when Config::PublishMode::Confirm
        confirmed = queue.publish_confirm(message)
        if confirmed
          @on_confirm.try &.call(message, @queue_name)
        else
          @on_nack.try &.call(message, @queue_name)
          # Raise to trigger re-queue on nack
          raise AMQP::Client::Error.new("Message nacked by server")
        end
      end
    end

    # Send message (used by background flush, can block)
    private def send_message(message : String) : Nil
      channel = get_or_create_channel
      send_message_fast(channel, message)
    end

    private def get_or_create_channel : AMQP::Client::Channel
      # Try with retry to handle reconnection under high load
      retries = 0
      max_retries = 3

      loop do
        @mutex.synchronize do
          # Check if we have a cached channel
          if ch = @channel
            unless ch.closed?
              return ch
            end
            Log.debug { "Cached channel is closed, creating new channel" }
            @channel = nil
          end
        end

        begin
          # Create new channel from client connection (outside mutex to reduce contention)
          conn = @client.connection
          new_channel = conn.channel

          @mutex.synchronize do
            # Double-check no one else created a channel while we were waiting
            if existing = @channel
              unless existing.closed?
                new_channel.close rescue nil
                return existing
              end
            end

            @channel = new_channel
            Log.debug { "Created new channel for queue: #{@queue_name}" }
            return new_channel
          end
        rescue ex
          retries += 1

          if retries >= max_retries
            # Out of retries - let caller handle (will buffer message)
            Log.debug(exception: ex) { "Failed to create channel after #{retries} retries" }
            raise ex
          end

          # Connection might be reconnecting - wait briefly and retry
          Log.debug { "Retry #{retries}/#{max_retries} creating channel (connection may be reconnecting)" }
          sleep 50.milliseconds
        end
      end
    end

    private def flush_loop : Nil
      loop do
        break if @closed
        sleep 100.milliseconds # Fast flush for low latency
        flush_buffered_messages if has_connection?
      end
    end

    private def flush_buffered_messages : Nil
      return if @buffer.empty?

      messages = @buffer.drain

      # Rate-limit flush to prevent overwhelming recovering connection
      # Send in batches with small delays
      batch_size = 100
      batch_delay = 10.milliseconds

      messages.each_with_index do |msg, idx|
        begin
          send_message(msg)
          # Success - clear retry count for this message
          @retry_counts.delete(msg)

          # Add small delay between batches to prevent overwhelming connection
          if (idx + 1) % batch_size == 0 && idx + 1 < messages.size
            sleep batch_delay
          end
        rescue ex
          # Increment retry count for this message
          retry_count = @retry_counts.fetch(msg, 0) + 1
          @retry_counts[msg] = retry_count

          if retry_count >= MAX_FLUSH_RETRIES
            # Exceeded max retries - drop the message
            Log.error(exception: ex) { "Message failed after #{retry_count} flush attempts, dropping" }
            @retry_counts.delete(msg)
            @on_drop.try &.call(msg, @queue_name, Config::DropReason::FlushRetryExceeded)
          else
            # Re-buffer for another attempt
            Log.warn(exception: ex) { "Failed to flush message (attempt #{retry_count}/#{MAX_FLUSH_RETRIES}), re-buffering" }
            @buffer.enqueue(msg)
          end

          # Clear and close the cached channel to force recreation on next attempt
          @mutex.synchronize do
            @channel.try &.close rescue nil
            @channel = nil
          end
        end
      end
    end
  end
end
