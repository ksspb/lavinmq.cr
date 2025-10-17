module Lavinmq
  # Manages AMQP connection with automatic reconnection
  class ConnectionManager
    Log = ::Log.for(self)

    @state : Config::ConnectionState = Config::ConnectionState::Connecting
    @connection : AMQP::Client::Connection?
    @amqp_url : String
    @config : Config
    @mutex : Mutex
    @state_channel : Channel(Config::ConnectionState)
    @reconnect_fiber : Fiber?
    @closed = false

    # Callbacks
    @on_connect : Proc(Nil)?
    @on_disconnect : Proc(Nil)?
    @on_error : Proc(Exception, Nil)?
    @on_state_change : Proc(Config::ConnectionState, Nil)?
    @on_reconnect_attempt : Proc(Int32, Float64, Nil)?

    def initialize(@amqp_url : String, @config : Config = Config.new)
      @mutex = Mutex.new
      @state_channel = Channel(Config::ConnectionState).new
    end

    def state : Config::ConnectionState
      @mutex.synchronize { @state }
    end

    # Start connection and return when connected
    def connect : Nil
      return if @closed

      @mutex.synchronize { @state = Config::ConnectionState::Connecting }

      spawn do
        reconnect_loop
      end

      # Wait for connection
      timeout = 30.seconds
      select
      when st = @state_channel.receive
        if st == Config::ConnectionState::Connected
          Log.info { "Connection established" }
        end
      when timeout(timeout)
        raise ConnectionError.new("Connection timeout after #{timeout}")
      end
    end

    # Close connection
    def close : Nil
      return if @closed

      @mutex.synchronize do
        @closed = true
        @state = Config::ConnectionState::Closed
      end

      @reconnect_fiber.try do |fiber|
        # Signal fiber to stop (it will check @closed)
      end

      if conn = @connection
        @connection = nil
        begin
          conn.close
        rescue
          # Ignore close errors
        end
      end

      @state_channel.close
      Log.info { "Connection closed" }
    end

    # Get current connection (or wait for reconnection)
    def connection : AMQP::Client::Connection
      if conn = @connection
        return conn
      end

      # Wait for connection to be established
      sleep 100.milliseconds
      if conn = @connection
        return conn
      end

      raise ClosedError.new("Connection not available")
    end

    # Get current connection without blocking (returns nil if not connected)
    def connection? : AMQP::Client::Connection?
      @connection
    end

    # Set connection callback
    def on_connect(&block : ->)
      @on_connect = block
    end

    # Set disconnection callback
    def on_disconnect(&block : ->)
      @on_disconnect = block
    end

    # Set error callback
    def on_error(&block : Exception ->)
      @on_error = block
    end

    # Set state change callback
    def on_state_change(&block : Config::ConnectionState ->)
      @on_state_change = block
    end

    # Set reconnect attempt callback
    def on_reconnect_attempt(&block : Int32, Float64 ->)
      @on_reconnect_attempt = block
    end

    private def reconnect_loop
      attempt = 0
      delay = @config.reconnect_initial_delay

      loop do
        break if @closed

        # Calculate backoff delay before this attempt (except for initial connection)
        if attempt > 0
          delay = [@config.reconnect_initial_delay * (@config.reconnect_multiplier ** (attempt - 1)),
                   @config.reconnect_max_delay].min
        else
          delay = 0.0 # No delay for initial connection
        end

        begin
          # Notify reconnect attempt
          @on_reconnect_attempt.try &.call(attempt, delay)

          # Sleep if needed (backoff delay)
          if delay > 0
            Log.info { "Reconnecting in #{delay}s..." }
            sleep delay.seconds
          end

          # Attempt connection
          Log.info { "Connecting to #{@amqp_url} (attempt #{attempt + 1})" }

          # Create client and connect - this returns a Connection
          client = AMQP::Client.new(@amqp_url)
          connection = client.connect

          @mutex.synchronize do
            @connection = connection
            @state = Config::ConnectionState::Connected
          end

          # Notify state change
          @on_state_change.try &.call(Config::ConnectionState::Connected)

          # Notify waiters
          @state_channel.send(Config::ConnectionState::Connected) rescue nil

          # Fire callback
          @on_connect.try &.call

          Log.info { "Connected successfully" }

          # Reset attempt counter after successful connection
          attempt = 0
          delay = @config.reconnect_initial_delay

          # Monitor connection - wait until it closes (check every 100ms for fast detection)
          loop do
            break if @closed
            break if connection.closed?
            sleep 100.milliseconds
          end

          break if @closed # Exit if intentionally closed

          # Connection lost, prepare to reconnect
          @mutex.synchronize do
            @connection = nil
            @state = Config::ConnectionState::Reconnecting
          end

          # Notify state change
          @on_state_change.try &.call(Config::ConnectionState::Reconnecting)

          @on_disconnect.try &.call

          # Small delay before first reconnection attempt after connection loss
          sleep 100.milliseconds
          attempt = 1 # Start with attempt 1 after disconnect
        rescue ex
          Log.error(exception: ex) { "Connection failed: #{ex.message}" }

          @on_error.try &.call(ex)

          @mutex.synchronize do
            @state = Config::ConnectionState::Reconnecting
          end

          # Notify state change
          @on_state_change.try &.call(Config::ConnectionState::Reconnecting)

          # Increment attempt for next retry
          attempt += 1
        end
      end
    end
  end
end
