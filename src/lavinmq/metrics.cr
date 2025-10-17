module Lavinmq
  # Metrics tracking for LavinMQ client using lock-free atomic operations
  # Provides high-performance metric collection without mutex overhead
  class Metrics
    @messages_sent : Atomic(Int64)
    @messages_received : Atomic(Int64)
    @messages_dropped : Atomic(Int64)
    @messages_buffered : Atomic(Int32)
    @connection_count : Atomic(Int64)
    @reconnection_count : Atomic(Int64)

    def initialize
      @messages_sent = Atomic(Int64).new(0_i64)
      @messages_received = Atomic(Int64).new(0_i64)
      @messages_dropped = Atomic(Int64).new(0_i64)
      @messages_buffered = Atomic(Int32).new(0)
      @connection_count = Atomic(Int64).new(0_i64)
      @reconnection_count = Atomic(Int64).new(0_i64)
    end

    def messages_sent : Int64
      @messages_sent.get
    end

    def messages_received : Int64
      @messages_received.get
    end

    def messages_dropped : Int64
      @messages_dropped.get
    end

    def messages_buffered : Int32
      @messages_buffered.get
    end

    def connection_count : Int64
      @connection_count.get
    end

    def reconnection_count : Int64
      @reconnection_count.get
    end

    def increment_sent : Nil
      @messages_sent.add(1_i64)
    end

    def increment_received : Nil
      @messages_received.add(1_i64)
    end

    def increment_dropped : Nil
      @messages_dropped.add(1_i64)
    end

    def update_buffered(count : Int32) : Nil
      @messages_buffered.set(count)
    end

    def increment_connections : Nil
      @connection_count.add(1_i64)
    end

    def increment_reconnections : Nil
      @reconnection_count.add(1_i64)
    end

    def to_s(io : IO) : Nil
      # Atomic reads are naturally consistent
      io << "Messages: sent=#{messages_sent}, received=#{messages_received}, "
      io << "dropped=#{messages_dropped}, buffered=#{messages_buffered}, "
      io << "Connections: count=#{connection_count}, reconnections=#{reconnection_count}"
    end

    # Reset all metrics to zero (useful for testing)
    def reset : Nil
      @messages_sent.set(0_i64)
      @messages_received.set(0_i64)
      @messages_dropped.set(0_i64)
      @messages_buffered.set(0)
      @connection_count.set(0_i64)
      @reconnection_count.set(0_i64)
    end
  end
end
