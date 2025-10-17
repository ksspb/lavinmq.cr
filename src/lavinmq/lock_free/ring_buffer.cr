module Lavinmq
  module LockFree
    # Lock-free ring buffer implementation using atomic operations
    # Provides thread-safe FIFO queue without mutex locks
    #
    # This implementation uses:
    # - Atomic head/tail indices for lock-free operation
    # - Pre-allocated array to avoid allocations in hot path
    # - Compare-and-swap (CAS) for thread safety
    # - Separate head/tail for producer/consumer separation
    class RingBuffer(T)
      @buffer : Array(T?)
      @capacity : Int32
      @buffer_size : Int32 # Actual buffer size (power of 2)
      @mask : Int32
      @head : Atomic(Int32) # Producer index (write position)
      @tail : Atomic(Int32) # Consumer index (read position)
      @size : Atomic(Int32) # Current number of elements

      def initialize(@capacity : Int32)
        raise ArgumentError.new("Capacity must be positive") unless @capacity > 0

        # Use power of 2 for efficient modulo, but track requested capacity
        # Add 1 to capacity to distinguish between full and empty
        @buffer_size = next_power_of_2(@capacity + 1)
        @mask = @buffer_size - 1

        @buffer = Array(T?).new(@buffer_size, nil)
        @head = Atomic(Int32).new(0)
        @tail = Atomic(Int32).new(0)
        @size = Atomic(Int32).new(0)
      end

      # Enqueue an item (producer operation)
      # Returns true if successful, false if buffer is full
      def enqueue(item : T) : Bool
        # Check size first to respect original capacity
        current_size = @size.get
        return false if current_size >= @capacity

        loop do
          current_head = @head.get
          current_tail = @tail.get

          # Calculate next position
          next_head = (current_head + 1) & @mask

          # Double check with ring buffer full condition
          if next_head == current_tail
            return false # Buffer is full
          end

          # Try to claim the slot atomically
          if @head.compare_and_set(current_head, next_head)
            # Successfully claimed the slot, write the data
            @buffer[current_head] = item
            @size.add(1)
            return true
          end

          # CAS failed, another producer got the slot, retry
          Fiber.yield
        end
      end

      # Dequeue an item (consumer operation)
      # Returns nil if buffer is empty
      def dequeue : T?
        loop do
          current_tail = @tail.get
          current_head = @head.get

          # Check if buffer is empty
          if current_tail == current_head
            return nil # Buffer is empty
          end

          # Read the item
          item = @buffer[current_tail]

          # Try to advance tail atomically
          next_tail = (current_tail + 1) & @mask
          if @tail.compare_and_set(current_tail, next_tail)
            # Successfully consumed the item
            @buffer[current_tail] = nil # Clear reference for GC
            @size.add(-1)
            return item
          end

          # CAS failed, another consumer got this item, retry
          Fiber.yield
        end
      end

      # Get current number of items in the buffer
      def size : Int32
        @size.get
      end

      # Get the capacity of the buffer
      def capacity : Int32
        @capacity
      end

      # Check if buffer is empty
      def empty? : Bool
        @head.get == @tail.get
      end

      # Check if buffer is full
      def full? : Bool
        @size.get >= @capacity
      end

      # Clear all items from the buffer
      def clear : Nil
        while dequeue
          # Keep dequeuing until empty
        end
      end

      private def next_power_of_2(n : Int32) : Int32
        return 1 if n <= 1

        # Find the next power of 2
        power = 1
        while power < n
          power <<= 1
        end
        power
      end
    end
  end
end
