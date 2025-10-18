module Lavinmq
  # Main client API for LavinMQ - Simplified event-driven architecture
  #
  # ## Example
  # ```
  # client = Lavinmq::Client.new("amqp://localhost")
  #
  # # Create producer
  # producer = client.producer("orders", mode: :confirm)
  # producer.publish("order data")
  #
  # # Create consumer
  # consumer = client.consumer("orders")
  # consumer.subscribe do |msg|
  #   process(msg)
  #   msg.ack
  # end
  # ```
  class Client
    Log = ::Log.for(self)

    getter connection : AMQP::Client::Connection
    @amqp_url : String
    @config : Config
    @producers : Array(Producer)
    @consumers : Array(Consumer)
    @closed : Atomic(Bool)
    @reconnecting : Atomic(Bool)
    @mutex : Mutex # Only for producer/consumer arrays
    @health_check_fiber : Fiber?

    # Initialize client with hybrid event-driven + polling reconnection
    # @param amqp_url AMQP connection URL
    # @param config Configuration options
    def initialize(@amqp_url : String, @config : Config = Config.new)
      @producers = [] of Producer
      @consumers = [] of Consumer
      @mutex = Mutex.new
      @closed = Atomic(Bool).new(false)
      @reconnecting = Atomic(Bool).new(false)
      @connection = uninitialized AMQP::Client::Connection

      connect

      # Start health check polling as fallback for on_close
      # With lock-free operations, on_close is now reliable, so we can use slower polling
      @health_check_fiber = spawn { health_check_loop }

      Log.info { "Client initialized with event-driven reconnection (lock-free atomic operations)" }
    end

    # Create a producer for a queue
    def producer(
      queue_name : String,
      mode : Config::PublishMode = Config::PublishMode::Confirm,
      buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = @config.buffer_size,
    ) : Producer
      raise ClosedError.new("Client is closed") if @closed.get

      @mutex.synchronize do
        prod = Producer.new(
          self,
          queue_name,
          mode: mode,
          buffer_policy: buffer_policy,
          buffer_size: buffer_size
        )

        @producers << prod

        Log.info { "Created producer for queue: #{queue_name}" }
        prod
      end
    end

    # Create a consumer for a queue
    def consumer(
      queue_name : String,
      prefetch : Int32 = 100,
    ) : Consumer
      raise ClosedError.new("Client is closed") if @closed.get

      @mutex.synchronize do
        cons = Consumer.new(
          self,
          queue_name,
          prefetch: prefetch
        )

        @consumers << cons

        Log.info { "Created consumer for queue: #{queue_name}" }
        cons
      end
    end

    # Close client and all producers/consumers
    def close : Nil
      # Atomically set closed flag
      return unless @closed.compare_and_set(false, true)

      Log.info { "Closing client..." }

      # Close all producers
      @producers.each do |prod|
        begin
          prod.close
        rescue ex
          Log.error(exception: ex) { "Error closing producer" }
        end
      end

      # Close all consumers
      @consumers.each do |cons|
        begin
          cons.close
        rescue ex
          Log.error(exception: ex) { "Error closing consumer" }
        end
      end

      # Close connection
      begin
        @connection.close
      rescue ex
        Log.error(exception: ex) { "Error closing connection" }
      end

      @producers.clear
      @consumers.clear

      Log.info { "Client closed" }
    end

    # Check if connected
    def connected? : Bool
      !@connection.closed?
    end

    # Internal: resubscribe all consumers (called after reconnection)
    protected def resubscribe_all
      @consumers.each do |cons|
        spawn { cons.resubscribe }
      end
    end

    # Connect to AMQP server with event-driven reconnection + timeout
    private def connect
      Log.info { "Connecting to #{@amqp_url}..." }

      # Add timeout to prevent hanging
      timeout_channel = Channel(Bool).new
      spawn do
        begin
          client = AMQP::Client.new(@amqp_url)
          @connection = client.connect

          # Event-driven reconnection using on_close callback
          # This fires INSTANTLY when connection closes
          # IMPORTANT: Don't block on mutex to avoid deadlock under high load
          @connection.on_close do |code, message|
            Log.warn { "Connection closed: #{code} - #{message}" }

            # Spawn immediately without grabbing mutex - prevents deadlock
            spawn { trigger_reconnect }
          end

          timeout_channel.send(true)
        rescue ex
          Log.error(exception: ex) { "Connection failed: #{ex.message}" }
          timeout_channel.send(false)
        end
      end

      # Wait for connection with timeout
      select
      when success = timeout_channel.receive
        if success
          Log.info { "Connected successfully" }
          # Resubscribe all consumers if this is a reconnection
          resubscribe_all
        else
          raise ConnectionError.new("Connection failed")
        end
      when timeout(10.seconds)
        raise ConnectionError.new("Connection timeout after 10 seconds")
      end
    end

    # Trigger reconnection (lock-free atomic operations)
    private def trigger_reconnect
      # Atomically check if we should reconnect (not already reconnecting and not closed)
      # This prevents multiple reconnection attempts from running simultaneously
      loop do
        reconnecting = @reconnecting.get
        closed = @closed.get

        # Don't reconnect if already reconnecting or closed
        return if reconnecting || closed

        # Try to atomically set reconnecting flag
        break if @reconnecting.compare_and_set(false, true)

        # CAS failed, retry (another fiber might have set it)
      end

      spawn do
        delay = @config.reconnect_initial_delay
        attempt = 0

        loop do
          # Check closed flag (fast atomic read)
          break if @closed.get

          attempt += 1
          Log.info { "Reconnecting in #{delay}s... (attempt #{attempt})" }
          sleep delay.seconds

          break if @closed.get

          begin
            connect

            # Successfully reconnected - atomically clear flag
            @reconnecting.set(false)

            Log.info { "Reconnected successfully after #{attempt} attempts" }
            break
          rescue ex
            Log.error(exception: ex) { "Reconnect failed (attempt #{attempt}): #{ex.message}" }

            # Exponential backoff
            delay = [delay * @config.reconnect_multiplier, @config.reconnect_max_delay].min
          end
        end

        # If loop exits due to @closed, clear reconnecting flag
        if @closed.get
          @reconnecting.set(false)
        end
      end
    end

    # Health check loop - polling fallback for when on_close doesn't fire
    # With lock-free atomic operations, on_close is now reliable under high load
    # So we use 1s polling interval (vs 100ms) to minimize overhead
    private def health_check_loop
      loop do
        break if @closed.get

        sleep 1.second

        next if @closed.get

        # Check if connection is closed
        if @connection.closed?
          Log.debug { "Health check detected closed connection" }
          trigger_reconnect
        end
      end
    rescue ex
      Log.error(exception: ex) { "Health check loop error: #{ex.message}" }
    end
  end
end
