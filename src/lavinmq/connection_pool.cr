module Lavinmq
  # High-performance connection pool with atomic operations for thread safety
  # Provides multiple AMQP connections to handle high throughput across multiple pods
  class ConnectionPool
    Log = ::Log.for(self)

    @connections : Array(ConnectionManager)
    @pool_size : Int32
    @round_robin_index : Atomic(Int32)
    @healthy_connections : Atomic(Int32)
    @closed : Atomic(Bool)
    @health_check_fiber : Fiber?
    @amqp_url : String
    @config : Config

    # Callbacks
    @on_pool_connect : Proc(Int32, Nil)?
    @on_pool_disconnect : Proc(Int32, Nil)?
    @on_pool_error : Proc(Int32, Exception, Nil)?

    def initialize(@amqp_url : String, @pool_size : Int32 = 5, @config : Config = Config.new)
      raise ArgumentError.new("Pool size must be positive") unless @pool_size > 0

      @connections = Array(ConnectionManager).new(@pool_size)
      @round_robin_index = Atomic(Int32).new(0)
      @healthy_connections = Atomic(Int32).new(0)
      @closed = Atomic(Bool).new(false)

      # Initialize connections
      @pool_size.times do |i|
        conn_mgr = ConnectionManager.new(@amqp_url, @config)

        # Set up callbacks for monitoring
        conn_mgr.on_connect do
          @healthy_connections.add(1)
          @on_pool_connect.try &.call(i)
          Log.info { "Pool connection ##{i} connected (healthy: #{@healthy_connections.get}/#{@pool_size})" }
        end

        conn_mgr.on_disconnect do
          @healthy_connections.add(-1)
          @on_pool_disconnect.try &.call(i)
          Log.warn { "Pool connection ##{i} disconnected (healthy: #{@healthy_connections.get}/#{@pool_size})" }
        end

        conn_mgr.on_error do |ex|
          @on_pool_error.try &.call(i, ex)
          Log.error(exception: ex) { "Pool connection ##{i} error" }
        end

        @connections << conn_mgr
      end

      # Start health monitoring
      @health_check_fiber = spawn { monitor_health }
    end

    # Connect all connections in the pool
    def connect : Nil
      return if @closed.get

      Log.info { "Connecting pool with #{@pool_size} connections..." }

      # Connect all in parallel for faster startup
      done = Channel(Nil).new
      @connections.each_with_index do |conn, i|
        spawn do
          begin
            conn.connect
            Log.debug { "Pool connection ##{i} established" }
          rescue ex
            Log.error(exception: ex) { "Failed to connect pool connection ##{i}" }
          end
          done.send(nil)
        end
      end

      # Wait for all connections to attempt
      @pool_size.times { done.receive }

      healthy = @healthy_connections.get
      if healthy == 0
        raise ConnectionError.new("No connections could be established in pool")
      elsif healthy < @pool_size
        Log.warn { "Pool partially connected: #{healthy}/#{@pool_size} healthy connections" }
      else
        Log.info { "Pool fully connected: #{healthy}/#{@pool_size} connections" }
      end
    end

    # Get a connection from the pool (round-robin with atomic operations)
    def connection : AMQP::Client::Connection
      raise ClosedError.new("Pool is closed") if @closed.get

      # Try multiple times to get a healthy connection
      @pool_size.times do
        # Atomic round-robin index increment
        index = @round_robin_index.add(1) % @pool_size
        conn_mgr = @connections[index]

        # Try to get connection from this manager
        if conn = conn_mgr.connection?
          return conn unless conn.closed?
        end
      end

      # Fallback: wait for any connection to become available
      @connections.sample.connection
    end

    # Get a connection without blocking (returns nil if none available)
    def connection? : AMQP::Client::Connection?
      return nil if @closed.get

      # Try all connections once
      @pool_size.times do
        index = @round_robin_index.add(1) % @pool_size
        conn_mgr = @connections[index]

        if conn = conn_mgr.connection?
          return conn unless conn.closed?
        end
      end

      nil
    end

    # Get a specific connection manager (for testing/debugging)
    def connection_manager(index : Int32) : ConnectionManager
      raise ArgumentError.new("Index out of bounds") unless 0 <= index < @pool_size
      @connections[index]
    end

    # Close all connections in the pool
    def close : Nil
      return unless @closed.compare_and_set(false, true)

      Log.info { "Closing connection pool..." }

      # Close all connections in parallel
      done = Channel(Nil).new
      @connections.each_with_index do |conn, i|
        spawn do
          begin
            conn.close
            Log.debug { "Pool connection ##{i} closed" }
          rescue ex
            Log.error(exception: ex) { "Error closing pool connection ##{i}" }
          end
          done.send(nil)
        end
      end

      # Wait for all to close
      @pool_size.times { done.receive }

      Log.info { "Connection pool closed" }
    end

    # Get current number of healthy connections
    def healthy_count : Int32
      @healthy_connections.get
    end

    # Get pool size
    def size : Int32
      @pool_size
    end

    # Check if pool is healthy (at least half connections working)
    def healthy? : Bool
      @healthy_connections.get >= (@pool_size // 2)
    end

    # Set pool connection callback
    def on_pool_connect(&block : Int32 ->)
      @on_pool_connect = block
    end

    # Set pool disconnection callback
    def on_pool_disconnect(&block : Int32 ->)
      @on_pool_disconnect = block
    end

    # Set pool error callback
    def on_pool_error(&block : Int32, Exception ->)
      @on_pool_error = block
    end

    private def monitor_health
      loop do
        break if @closed.get

        # Check health every 5 seconds
        sleep 5.seconds

        unhealthy_count = 0
        @connections.each_with_index do |conn_mgr, i|
          if conn_mgr.state != Config::ConnectionState::Connected
            unhealthy_count += 1
            Log.debug { "Pool connection ##{i} unhealthy: #{conn_mgr.state}" }
          end
        end

        if unhealthy_count > 0
          Log.warn { "Pool health check: #{@pool_size - unhealthy_count}/#{@pool_size} healthy" }

          # Trigger reconnection for disconnected connections
          @connections.each do |conn_mgr|
            if conn_mgr.state == Config::ConnectionState::Closed
              spawn { conn_mgr.connect rescue nil }
            end
          end
        end
      end
    end
  end
end