module Lavinmq
  # Producer for publishing messages with buffering and confirmation support
  class Producer
    Log = ::Log.for(self)

    @mode : Config::PublishMode
    @buffer_policy : Config::BufferPolicy
    @buffer : MessageBuffer
    @connection_manager : ConnectionManager
    @queue_name : String
    @channel : AMQP::Client::Channel?
    @closed : Bool = false
    @mutex : Mutex
    @flush_fiber : Fiber?

    def initialize(
      @connection_manager : ConnectionManager,
      @queue_name : String,
      @mode : Config::PublishMode = Config::PublishMode::Confirm,
      @buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = Config::DEFAULT_BUFFER_SIZE,
    )
      @buffer = MessageBuffer.new(buffer_size)
      @mutex = Mutex.new

      # Start flush fiber to send buffered messages
      @flush_fiber = spawn { flush_loop }

      # Listen for reconnections to flush buffer
      @connection_manager.on_connect do
        spawn { flush_buffered_messages }
      end
    end

    # Publish a message
    def publish(message : String) : Nil
      return if @closed

      # If disconnected, buffer the message
      unless has_connection?
        handle_buffering(message)
        return
      end

      # Try to send immediately
      begin
        send_message(message)
      rescue ex
        Log.warn(exception: ex) { "Failed to send message, buffering" }
        handle_buffering(message)
      end
    end

    # Close producer
    def close : Nil
      return if @closed

      @mutex.synchronize do
        @closed = true
      end

      # Flush remaining messages
      flush_buffered_messages

      @channel.try &.close rescue nil
      @channel = nil

      Log.info { "Producer closed for queue: #{@queue_name}" }
    end

    private def has_connection? : Bool
      @connection_manager.state == Config::ConnectionState::Connected
    end

    private def handle_buffering(message : String) : Nil
      case @mode
      when Config::PublishMode::FireAndForget
        # Fire-and-forget: buffer and drop oldest if full
        @buffer.enqueue(message)
      when Config::PublishMode::Confirm
        # Confirm mode: apply buffer policy
        case @buffer_policy
        when Config::BufferPolicy::DropOldest
          @buffer.enqueue(message)
        when Config::BufferPolicy::Raise
          if @buffer.full?
            raise BufferFullError.new("Producer buffer full for queue: #{@queue_name}")
          end
          @buffer.enqueue(message)
        when Config::BufferPolicy::Block
          # Block until space available
          while @buffer.full? && !@closed
            sleep 10.milliseconds
          end
          @buffer.enqueue(message) unless @closed
        end
      end
    end

    private def send_message(message : String) : Nil
      channel = get_or_create_channel
      queue = channel.queue(@queue_name)

      case @mode
      when Config::PublishMode::FireAndForget
        queue.publish(message)
      when Config::PublishMode::Confirm
        queue.publish_confirm(message)
      end
    end

    private def get_or_create_channel : AMQP::Client::Channel
      if ch = @channel
        return ch
      end

      conn = @connection_manager.connection
      @channel = conn.channel
      @channel.not_nil!
    end

    private def flush_loop : Nil
      loop do
        break if @closed
        sleep 1.second
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
          rescue ex
            Log.error(exception: ex) { "Failed to flush message, re-buffering" }
            @buffer.enqueue(msg)
          end
        end
      end
    end
  end
end
