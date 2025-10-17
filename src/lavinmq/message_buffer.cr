module Lavinmq
  # Ring buffer for message buffering during connection outages
  # Thread-safe/fiber-safe implementation
  class MessageBuffer
    getter max_size : Int32
    getter dropped_count : Int64 = 0_i64

    @buffer : Deque(String)
    @mutex : Mutex

    def initialize(@max_size : Int32 = Config::DEFAULT_BUFFER_SIZE)
      @buffer = Deque(String).new
      @mutex = Mutex.new
    end

    # Add message to buffer
    # If buffer is full, drops the oldest message
    def enqueue(message : String) : Bool
      @mutex.synchronize do
        if @buffer.size >= @max_size
          # Ring buffer: drop oldest, accept new
          @dropped_count += 1
          @buffer.shift # Remove oldest
        end

        @buffer << message
        true
      end
    end

    # Remove and return oldest message
    def dequeue : String?
      @mutex.synchronize do
        @buffer.shift?
      end
    end

    # Remove all messages and return them
    def drain : Array(String)
      @mutex.synchronize do
        messages = @buffer.to_a
        @buffer.clear
        messages
      end
    end

    # Check if buffer is empty
    def empty? : Bool
      @mutex.synchronize { @buffer.empty? }
    end

    # Check if buffer is full
    def full? : Bool
      @mutex.synchronize { @buffer.size >= @max_size }
    end

    # Get current buffer count
    def count : Int32
      @mutex.synchronize { @buffer.size }
    end

    # Clear all messages
    def clear
      @mutex.synchronize do
        @buffer.clear
      end
    end
  end
end
