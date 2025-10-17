module Lavinmq
  # Base exception for all Lavinmq errors
  class Error < Exception
  end

  # Raised when buffer is full and cannot accept more messages
  class BufferFullError < Error
  end

  # Raised when connection fails and cannot reconnect
  class ConnectionError < Error
  end

  # Raised when operation is attempted on closed client/connection
  class ClosedError < Error
  end

  # Raised when configuration is invalid
  class ConfigError < Error
  end
end
