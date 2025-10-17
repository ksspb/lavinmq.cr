module Lavinmq
  # Configuration for LavinMQ client
  class Config
    # Buffer policy for confirm mode producers
    enum BufferPolicy
      # Block when buffer is full
      Block
      # Raise BufferFullError when buffer is full
      Raise
      # Drop oldest message when buffer is full
      DropOldest
    end

    # Publishing mode
    enum PublishMode
      # Fire-and-forget with buffering (drops oldest at limit)
      FireAndForget
      # Confirm mode with configurable buffer policy
      Confirm
    end

    # Connection state
    enum ConnectionState
      Connecting
      Connected
      Reconnecting
      Closed
    end

    # Reason for message drop
    enum DropReason
      # Connection lost, message buffered then dropped
      Disconnected
      # Buffer at capacity, oldest message dropped
      BufferFull
      # Producer/client closed, message dropped
      Closed
      # Message TTL expired
      TTLExpired
      # Message failed to flush after max retries
      FlushRetryExceeded
    end

    # Default buffer size for both modes (10k messages)
    DEFAULT_BUFFER_SIZE = 10_000

    # Aggressive reconnection timing (100ms → 200ms → 400ms ... max 30s)
    RECONNECT_INITIAL_DELAY =  0.1 # 100ms
    RECONNECT_MAX_DELAY     = 30.0 # 30s
    RECONNECT_MULTIPLIER    =  2.0

    property buffer_size : Int32 = DEFAULT_BUFFER_SIZE
    property reconnect_initial_delay : Float64 = RECONNECT_INITIAL_DELAY
    property reconnect_max_delay : Float64 = RECONNECT_MAX_DELAY
    property reconnect_multiplier : Float64 = RECONNECT_MULTIPLIER

    def initialize(
      @buffer_size = DEFAULT_BUFFER_SIZE,
      @reconnect_initial_delay = RECONNECT_INITIAL_DELAY,
      @reconnect_max_delay = RECONNECT_MAX_DELAY,
      @reconnect_multiplier = RECONNECT_MULTIPLIER,
    )
    end
  end
end
