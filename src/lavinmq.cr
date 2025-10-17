require "amqp-client"
require "./lavinmq/**"

# Robust LavinMQ client library with automatic reconnection,
# message buffering, and multi-fiber support.
#
# ## Features
# - Automatic reconnection with exponential backoff
# - Message buffering to prevent message loss
# - Fire-and-forget and confirm publishing modes
# - Multi-fiber safe operations
# - Independent ack tracking per consumer
#
# ## Example
# ```
# client = Lavinmq::Client.new("amqp://localhost")
#
# # Producer with confirm mode
# producer = client.producer("orders", mode: :confirm)
# producer.publish("order data")
#
# # Consumer with auto-recovery
# consumer = client.consumer("orders")
# consumer.subscribe do |msg|
#   process(msg)
#   msg.ack
# end
# ```
module Lavinmq
  VERSION = "0.2.1"
end
