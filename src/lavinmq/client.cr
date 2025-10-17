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

    @connection_manager : ConnectionManager
    @config : Config
    @producers : Array(Producer)
    @consumers : Array(Consumer)
    @mutex : Mutex
    @closed : Bool = false

    def initialize(amqp_url : String, config : Config = Config.new)
      @connection_manager = ConnectionManager.new(amqp_url, config)
      @config = config
      @producers = [] of Producer
      @consumers = [] of Consumer
      @mutex = Mutex.new
      @connection_manager.connect
    end

    # Create a producer for a queue
    def producer(
      queue_name : String,
      mode : Config::PublishMode = Config::PublishMode::Confirm,
      buffer_policy : Config::BufferPolicy = Config::BufferPolicy::Block,
      buffer_size : Int32 = @config.buffer_size,
    ) : Producer
      raise ClosedError.new("Client is closed") if @closed

      prod = Producer.new(
        @connection_manager,
        queue_name,
        mode: mode,
        buffer_policy: buffer_policy,
        buffer_size: buffer_size
      )

      @mutex.synchronize do
        @producers << prod
      end

      Log.info { "Created producer for queue: #{queue_name}" }
      prod
    end

    # Create a consumer for a queue
    # Each consumer gets its own dedicated channel
    def consumer(
      queue_name : String,
      prefetch : Int32 = 100,
    ) : Consumer
      raise ClosedError.new("Client is closed") if @closed

      cons = Consumer.new(
        @connection_manager,
        queue_name,
        prefetch: prefetch
      )

      @mutex.synchronize do
        @consumers << cons
      end

      Log.info { "Created consumer for queue: #{queue_name}" }
      cons
    end

    # Close client and all producers/consumers
    def close : Nil
      return if @closed

      @mutex.synchronize do
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
      @connection_manager.close

      @producers.clear
      @consumers.clear

      Log.info { "Client closed" }
    end
  end
end
