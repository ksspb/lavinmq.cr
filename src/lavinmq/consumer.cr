module Lavinmq
  # Consumer for receiving messages with auto-recovery
  # Each consumer has its own channel for independent ack tracking
  class Consumer
    Log = ::Log.for(self)

    @client : Client
    @queue_name : String
    @channel : AMQP::Client::Channel?
    @ack_tracker : AckTracker
    @prefetch : Int32
    @consumer_tag : String?
    @no_ack : Bool = false
    @message_handler : Proc(AMQP::Client::DeliverMessage, Nil)?
    @closed : Bool = false
    @mutex : Mutex

    def initialize(
      @client : Client,
      @queue_name : String,
      @prefetch : Int32 = 100,
    )
      @ack_tracker = AckTracker.new
      @mutex = Mutex.new
    end

    # Subscribe to queue and process messages
    def subscribe(no_ack : Bool = false, &block : AMQP::Client::DeliverMessage ->) : Nil
      return if @closed

      @no_ack = no_ack
      @message_handler = block

      # Initial subscription
      do_subscribe
    end

    # Acknowledge a message
    def ack(delivery_tag : UInt64, multiple : Bool = false) : Nil
      return if @closed || @no_ack

      @ack_tracker.ack(delivery_tag, multiple)

      if ch = @channel
        begin
          ch.basic_ack(delivery_tag, multiple: multiple)
        rescue ex
          Log.error(exception: ex) { "Failed to ack message #{delivery_tag}" }
        end
      end
    end

    # Negative acknowledge a message
    def nack(delivery_tag : UInt64, multiple : Bool = false, requeue : Bool = true) : Nil
      return if @closed || @no_ack

      @ack_tracker.nack(delivery_tag, multiple)

      if ch = @channel
        begin
          ch.basic_nack(delivery_tag, multiple: multiple, requeue: requeue)
        rescue ex
          Log.error(exception: ex) { "Failed to nack message #{delivery_tag}" }
        end
      end
    end

    # Check if consumer is subscribed
    def subscribed? : Bool
      @mutex.synchronize do
        !@channel.nil? && !@consumer_tag.nil?
      end
    end

    # Close consumer
    def close : Nil
      @mutex.synchronize do
        return if @closed
        @closed = true
      end

      if ch = @channel
        if tag = @consumer_tag
          begin
            ch.basic_cancel(tag)
          rescue ex
            Log.error(exception: ex) { "Failed to cancel consumer" }
          end
        end

        begin
          ch.close
        rescue ex
          Log.error(exception: ex) { "Failed to close channel" }
        end
      end

      @channel = nil
      @consumer_tag = nil

      Log.info { "Consumer closed for queue: #{@queue_name}" }
    end

    private def do_subscribe : Nil
      return if @closed

      begin
        # Get dedicated channel for this consumer
        conn = @client.connection
        ch = conn.channel
        @channel = ch

        # Set prefetch
        ch.prefetch(@prefetch)

        # Subscribe to queue
        tag = "consumer-#{@queue_name}-#{Random.rand(10000)}"
        @consumer_tag = tag

        ch.basic_consume(
          @queue_name,
          tag: tag,
          no_ack: @no_ack,
          exclusive: false,
          block: false
        ) do |msg|
          # Track unacked messages
          @ack_tracker.track(msg.delivery_tag) unless @no_ack

          # Call handler
          @message_handler.try &.call(msg)
        end

        Log.info { "Subscribed to queue: #{@queue_name}" }
      rescue ex
        Log.error(exception: ex) { "Failed to subscribe: #{ex.message}" }
        @channel = nil
        @consumer_tag = nil
      end
    end

    # Called by Client when connection is restored
    protected def resubscribe : Nil
      return if @closed
      return unless @message_handler

      Log.info { "Resubscribing to queue: #{@queue_name}" }

      # Clear old channel
      @channel = nil
      @consumer_tag = nil

      # Resubscribe
      do_subscribe
    end
  end
end
