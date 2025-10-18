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
    @closed : Bool = false
    @reconnecting : Bool = false
    @mutex : Mutex

    # Initialize client with event-driven auto-reconnection
    # @param amqp_url AMQP connection URL
    # @param config Configuration options
    def initialize(@amqp_url : String, @config : Config = Config.new)
      @producers = [] of Producer
      @consumers = [] of Consumer
      @mutex = Mutex.new
      @connection = uninitialized AMQP::Client::Connection

      connect

      Log.info { "Client initialized with event-driven reconnection" }
    end

    # Create a producer for a queue
    def producer(
      queue_name : String,
      mode : Config::PublishMode = Config::PublishMode::Confirm,
      buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = @config.buffer_size,
    ) : Producer
      @mutex.synchronize do
        raise ClosedError.new("Client is closed") if @closed

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
      @mutex.synchronize do
        raise ClosedError.new("Client is closed") if @closed

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
      @mutex.synchronize do
        return if @closed
        @closed = true
      end

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

    # Connect to AMQP server with event-driven reconnection
    private def connect
      Log.info { "Connecting to #{@amqp_url}..." }

      client = AMQP::Client.new(@amqp_url)
      @connection = client.connect

      # Event-driven reconnection using on_close callback
      # This fires INSTANTLY when connection closes (not polling-based)
      @connection.on_close do |code, message|
        Log.warn { "Connection closed: #{code} - #{message}" }

        # Trigger reconnection unless intentionally closed
        @mutex.synchronize do
          reconnect unless @closed
        end
      end

      Log.info { "Connected successfully" }

      # Resubscribe all consumers if this is a reconnection
      resubscribe_all
    end

    # Reconnect with exponential backoff
    private def reconnect
      return if @reconnecting || @closed
      @reconnecting = true

      spawn do
        delay = @config.reconnect_initial_delay
        attempt = 0

        loop do
          break if @closed

          attempt += 1
          Log.info { "Reconnecting in #{delay}s... (attempt #{attempt})" }
          sleep delay.seconds

          begin
            connect
            @reconnecting = false
            Log.info { "Reconnected successfully" }
            break
          rescue ex
            Log.error(exception: ex) { "Reconnect failed: #{ex.message}" }

            # Exponential backoff
            delay = [delay * @config.reconnect_multiplier, @config.reconnect_max_delay].min
          end
        end
      end
    end
  end
end
