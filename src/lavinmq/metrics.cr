module Lavinmq
  # Metrics tracking for LavinMQ client
  class Metrics
    getter messages_sent : Int64 = 0_i64
    getter messages_received : Int64 = 0_i64
    getter messages_dropped : Int64 = 0_i64
    getter messages_buffered : Int32 = 0
    getter connection_count : Int64 = 0_i64
    getter reconnection_count : Int64 = 0_i64

    @mutex : Mutex

    def initialize
      @mutex = Mutex.new
    end

    def increment_sent : Nil
      @mutex.synchronize { @messages_sent += 1 }
    end

    def increment_received : Nil
      @mutex.synchronize { @messages_received += 1 }
    end

    def increment_dropped : Nil
      @mutex.synchronize { @messages_dropped += 1 }
    end

    def update_buffered(count : Int32) : Nil
      @mutex.synchronize { @messages_buffered = count }
    end

    def increment_connections : Nil
      @mutex.synchronize { @connection_count += 1 }
    end

    def increment_reconnections : Nil
      @mutex.synchronize { @reconnection_count += 1 }
    end

    def to_s(io : IO) : Nil
      @mutex.synchronize do
        io << "Messages: sent=#{@messages_sent}, received=#{@messages_received}, "
        io << "dropped=#{@messages_dropped}, buffered=#{@messages_buffered}, "
        io << "Connections: count=#{@connection_count}, reconnections=#{@reconnection_count}"
      end
    end
  end
end
