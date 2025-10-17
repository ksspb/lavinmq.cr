module Lavinmq
  # Manages AMQP connection with automatic reconnection using atomic operations
  # Provides thread-safe state management without mutex overhead
  class ConnectionManager
    Log = ::Log.for(self)

    @state : Atomic(Int32) # Use Int32 for atomic enum representation
    @connection : Atomic(AMQP::Client::Connection?)
    @amqp_url : String
    @config : Config
    @state_channel : Channel(Config::ConnectionState)
    @reconnect_fiber : Fiber?
    @closed : Atomic(Bool)

    # Callbacks
    @on_connect : Proc(Nil)?
    @on_disconnect : Proc(Nil)?
    @on_error : Proc(Exception, Nil)?
    @on_state_change : Proc(Config::ConnectionState, Nil)?
    @on_reconnect_attempt : Proc(Int32, Float64, Nil)?

    def initialize(@amqp_url : String, @config : Config = Config.new)
      # Initialize atomics with enum values converted to Int32
      @state = Atomic(Int32).new(Config::ConnectionState::Connecting.value)
      @connection = Atomic(AMQP::Client::Connection?).new(nil)
      @closed = Atomic(Bool).new(false)
      @state_channel = Channel(Config::ConnectionState).new
    end

    def state : Config::ConnectionState
      # Convert atomic Int32 back to enum
      Config::ConnectionState.from_value(@state.get)
    end

    # Start connection and return when connected
    def connect : Nil
      return if @closed.get

      # Atomically set state to Connecting
      @state.set(Config::ConnectionState::Connecting.value)

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
      # Atomically set closed flag using compare-and-set to prevent TOCTOU bug
      return unless @closed.compare_and_set(false, true)

      # Atomically set state to Closed
      @state.set(Config::ConnectionState::Closed.value)

      @reconnect_fiber.try do |fiber|
        # Signal fiber to stop (it will check @closed)
      end

      # Atomically swap connection to nil and close if exists
      if conn = @connection.swap(nil)
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
      # Atomic load of connection
      if conn = @connection.get
        return conn
      end

      # Wait for connection to be established
      sleep 100.milliseconds
      if conn = @connection.get
        return conn
      end

      raise ClosedError.new("Connection not available")
    end

    # Get current connection without blocking (returns nil if not connected)
    def connection? : AMQP::Client::Connection?
      @connection.get
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
        break if @closed.get

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

          # Atomically set connection and state
          old_conn = @connection.swap(connection)
          old_conn.try &.close rescue nil # Close old connection if exists
          @state.set(Config::ConnectionState::Connected.value)

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
            break if @closed.get
            break if connection.closed?
            sleep 100.milliseconds
          end

          break if @closed.get # Exit if intentionally closed

          # Connection lost, prepare to reconnect
          # Only clear if it's still our connection (CAS to prevent race)
          @connection.compare_and_set(connection, nil)
          @state.set(Config::ConnectionState::Reconnecting.value)

          # Notify state change
          @on_state_change.try &.call(Config::ConnectionState::Reconnecting)

          @on_disconnect.try &.call

          # Small delay before first reconnection attempt after connection loss
          sleep 100.milliseconds
          attempt = 1 # Start with attempt 1 after disconnect
        rescue ex
          Log.error(exception: ex) { "Connection failed: #{ex.message}" }

          @on_error.try &.call(ex)

          # Atomically set state to Reconnecting
          @state.set(Config::ConnectionState::Reconnecting.value)

          # Notify state change
          @on_state_change.try &.call(Config::ConnectionState::Reconnecting)

          # Increment attempt for next retry
          attempt += 1
        end
      end
    end
  end
end
