module Lavinmq
  # Producer for publishing messages with buffering and confirmation support
  class Producer
    Log = ::Log.for(self)

    # Maximum number of flush retry attempts before dropping a message
    MAX_FLUSH_RETRIES = 3

    @mode : Config::PublishMode
    @buffer_policy : Config::BufferPolicy
    @buffer : MessageBuffer
    @connection_manager : ConnectionManager
    @queue_name : String
    @channel : Atomic(AMQP::Client::Channel?)
    @closed : Atomic(Bool)
    @mutex : Mutex # Still needed for flush_buffered_messages
    @flush_fiber : Fiber?
    @retry_counts : Hash(String, Int32) = Hash(String, Int32).new

    # Observability callbacks
    @on_drop : Proc(String, String, Config::DropReason, Nil)?
    @on_confirm : Proc(String, String, Nil)?
    @on_nack : Proc(String, String, Nil)?
    @on_error : Proc(String, String, Exception, Nil)?

    def initialize(
      @connection_manager : ConnectionManager,
      @queue_name : String,
      @mode : Config::PublishMode = Config::PublishMode::Confirm,
      @buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = Config::DEFAULT_BUFFER_SIZE,
    )
      @buffer = MessageBuffer.new(buffer_size)
      @mutex = Mutex.new
      @channel = Atomic(AMQP::Client::Channel?).new(nil)
      @closed = Atomic(Bool).new(false)

      # Start flush fiber to send buffered messages
      @flush_fiber = spawn { flush_loop }

      # Listen for reconnections to flush buffer
      @connection_manager.on_connect do
        spawn { flush_buffered_messages }
      end
    end

    # Publish a message (non-blocking, zero latency)
    def publish(message : String) : Nil
      return if @closed.get

      # Optimistic fast path: try cached channel if available (lock-free atomic load)
      if ch = @channel.get
        if ch.closed?
          # Channel is closed, atomically clear it
          @channel.compare_and_set(ch, nil)
        else
          begin
            # Fast path: use cached channel without connection retrieval
            send_message_fast(ch, message)
            return
          rescue ex
            # Channel failed, atomically clear cache and fall through to queue
            Log.debug(exception: ex) { "Fast path failed, queuing message" }
            # Use compare_and_set to only clear if it's still the same channel
            @channel.compare_and_set(ch, nil)
          end
        end
      end

      # Queue for background sending (non-blocking)
      handle_buffering(message)
    end

    # Close producer
    def close : Nil
      # Atomically set closed flag - prevents TOCTOU bug
      return unless @closed.compare_and_set(false, true)

      # Flush remaining messages
      flush_buffered_messages

      # Atomically clear and close channel
      if ch = @channel.swap(nil)
        ch.close rescue nil
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
      @connection_manager.state == Config::ConnectionState::Connected
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
      # Check if we have a cached channel and if it's still open (atomic load)
      if ch = @channel.get
        unless ch.closed?
          return ch
        end
        # Channel is closed, atomically clear cache
        Log.debug { "Cached channel is closed, creating new channel" }
        @channel.compare_and_set(ch, nil)
      end

      # Try non-blocking connection first
      if conn = @connection_manager.connection?
        new_channel = conn.channel
        Log.debug { "Created new channel for queue: #{@queue_name}" }

        # Atomically set the new channel only if it's still nil
        # This prevents multiple fibers from creating duplicate channels
        if @channel.compare_and_set(nil, new_channel)
          return new_channel
        else
          # Another fiber already created a channel, close ours and use theirs
          new_channel.close rescue nil
          return @channel.get.not_nil!
        end
      end

      # Fallback to blocking connection (only used by background flush)
      conn = @connection_manager.connection
      new_channel = conn.channel
      Log.debug { "Created new channel for queue: #{@queue_name}" }

      # Same atomic set logic for blocking path
      if @channel.compare_and_set(nil, new_channel)
        new_channel
      else
        # Another fiber already created a channel
        new_channel.close rescue nil
        @channel.get.not_nil!
      end
    end

    private def flush_loop : Nil
      loop do
        break if @closed.get
        sleep 100.milliseconds # Fast flush for low latency
        flush_buffered_messages if has_connection?
      end
    end

    private def flush_buffered_messages : Nil
      return if @buffer.empty?

      @mutex.synchronize do
        messages = @buffer.drain
        messages.each do |msg|
          begin
            send_message(msg)
            # Success - clear retry count for this message
            @retry_counts.delete(msg)
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

            # Atomically clear and close the cached channel to force recreation on next attempt
            if old_ch = @channel.swap(nil)
              old_ch.close rescue nil
            end
          end
        end
      end
    end
  end
end
