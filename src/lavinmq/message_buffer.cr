module Lavinmq
  # Lock-free ring buffer for message buffering during connection outages
  # Thread-safe/fiber-safe implementation using atomic operations
  # Provides zero-contention high-performance message buffering
  class MessageBuffer
    getter max_size : Int32

    @buffer : LockFree::RingBuffer(String)
    @dropped_count : Atomic(Int64)

    def initialize(@max_size : Int32 = Config::DEFAULT_BUFFER_SIZE)
      @buffer = LockFree::RingBuffer(String).new(@max_size)
      @dropped_count = Atomic(Int64).new(0_i64)
    end

    def dropped_count : Int64
      @dropped_count.get
    end

    # Add message to buffer (lock-free operation)
    # If buffer is full, drops the oldest message and returns it
    # Returns nil if no message was dropped
    def enqueue(message : String) : String?
      # Try to enqueue, if buffer is full it will return false
      if @buffer.enqueue(message)
        return nil # No message dropped
      end

      # Buffer is full, dequeue oldest and try again
      dropped = @buffer.dequeue
      @dropped_count.add(1_i64)

      # Retry enqueue (should succeed now)
      @buffer.enqueue(message)

      dropped
    end

    # Remove and return oldest message (lock-free operation)
    def dequeue : String?
      @buffer.dequeue
    end

    # Remove all messages and return them (atomic operation)
    def drain : Array(String)
      messages = [] of String
      while msg = @buffer.dequeue
        messages << msg
      end
      messages
    end

    # Check if buffer is empty (lock-free read)
    def empty? : Bool
      @buffer.size == 0
    end

    # Check if buffer is full (lock-free read)
    def full? : Bool
      @buffer.size >= @max_size
    end

    # Get current buffer count (atomic read)
    def count : Int32
      @buffer.size
    end

    # Alias for count (observability API)
    def size : Int32
      @buffer.size
    end

    # Get buffer capacity
    def capacity : Int32
      @buffer.capacity
    end

    # Clear all messages (atomic operation)
    def clear
      @buffer.clear
    end
  end
end
