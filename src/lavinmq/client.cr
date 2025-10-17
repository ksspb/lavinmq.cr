module Lavinmq
  # Main client API for LavinMQ
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

    getter connection_pool : ConnectionPool
    @config : Config
    @producers : Array(Producer)
    @consumers : Array(Consumer)
    @closed : Atomic(Bool)
    @pool_size : Int32
    @next_pool_index : Atomic(Int32)

    # Initialize client with connection pool for high throughput and resilience
    # @param amqp_url AMQP connection URL
    # @param config Configuration options
    # @param pool_size Number of connections in pool (default: 5, recommended: 5-10)
    def initialize(amqp_url : String, config : Config = Config.new, @pool_size : Int32 = 5)
      @connection_pool = ConnectionPool.new(amqp_url, @pool_size, config)
      @config = config
      @producers = [] of Producer
      @consumers = [] of Consumer
      @closed = Atomic(Bool).new(false)
      @next_pool_index = Atomic(Int32).new(0)
      @connection_pool.connect

      Log.info { "Client initialized with connection pool (size: #{@pool_size})" }
    end

    # Create a producer for a queue
    # Automatically distributes producers across pool connections for optimal performance
    def producer(
      queue_name : String,
      mode : Config::PublishMode = Config::PublishMode::Confirm,
      buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = @config.buffer_size,
    ) : Producer
      raise ClosedError.new("Client is closed") if @closed.get

      # Get connection manager from pool using round-robin
      pool_index = @next_pool_index.add(1) % @pool_size
      conn_mgr = @connection_pool.connection_manager(pool_index)

      prod = Producer.new(
        conn_mgr,
        queue_name,
        mode: mode,
        buffer_policy: buffer_policy,
        buffer_size: buffer_size
      )

      @producers << prod

      Log.info { "Created producer for queue: #{queue_name} (pool index: #{pool_index})" }
      prod
    end

    # Create a consumer for a queue
    # Each consumer gets its own dedicated channel
    # Automatically distributes consumers across pool connections
    def consumer(
      queue_name : String,
      prefetch : Int32 = 100,
    ) : Consumer
      raise ClosedError.new("Client is closed") if @closed.get

      # Get connection manager from pool using round-robin
      pool_index = @next_pool_index.add(1) % @pool_size
      conn_mgr = @connection_pool.connection_manager(pool_index)

      cons = Consumer.new(
        conn_mgr,
        queue_name,
        prefetch: prefetch
      )

      @consumers << cons

      Log.info { "Created consumer for queue: #{queue_name} (pool index: #{pool_index})" }
      cons
    end

    # Close client and all producers/consumers
    def close : Nil
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

      # Close connection pool
      @connection_pool.close

      @producers.clear
      @consumers.clear

      Log.info { "Client closed" }
    end

    # Get connection pool health status
    # Returns true if at least half of connections are healthy
    def healthy? : Bool
      @connection_pool.healthy?
    end

    # Get number of healthy connections in pool
    def healthy_connections : Int32
      @connection_pool.healthy_count
    end

    # Get total pool size
    def pool_size : Int32
      @pool_size
    end
  end
end
