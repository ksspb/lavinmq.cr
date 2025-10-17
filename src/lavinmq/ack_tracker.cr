module Lavinmq
  # Tracks acknowledgments for consumed messages
  class AckTracker
    @unacked : Set(UInt64)
    @mutex : Mutex

    def initialize
      @unacked = Set(UInt64).new
      @mutex = Mutex.new
    end

    # Track a delivery tag as unacked
    def track(delivery_tag : UInt64) : Nil
      @mutex.synchronize do
        @unacked.add(delivery_tag)
      end
    end

    # Mark a delivery tag as acked
    def ack(delivery_tag : UInt64, multiple : Bool = false) : Nil
      @mutex.synchronize do
        if multiple
          # Ack all tags up to and including delivery_tag
          @unacked = @unacked.reject { |tag| tag <= delivery_tag }.to_set
        else
          @unacked.delete(delivery_tag)
        end
      end
    end

    # Mark a delivery tag as nacked
    def nack(delivery_tag : UInt64, multiple : Bool = false) : Nil
      @mutex.synchronize do
        if multiple
          # Nack all tags up to and including delivery_tag
          @unacked = @unacked.reject { |tag| tag <= delivery_tag }.to_set
        else
          @unacked.delete(delivery_tag)
        end
      end
    end

    # Get all unacked delivery tags
    def unacked_tags : Array(UInt64)
      @mutex.synchronize { @unacked.to_a }
    end

    # Clear all tracked tags
    def clear : Nil
      @mutex.synchronize { @unacked.clear }
    end

    # Count of unacked messages
    def count : Int32
      @mutex.synchronize { @unacked.size }
    end
  end
end
