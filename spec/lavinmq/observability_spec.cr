require "../spec_helper"

describe "Observability: Connection State Callbacks" do
  describe "ConnectionManager" do
    it "has on_state_change callback for state transitions" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      state_changes = [] of Lavinmq::Config::ConnectionState

      manager.on_state_change do |state|
        state_changes << state
      end

      # Verify callback can be set
      manager.@on_state_change.should_not be_nil
    end

    it "has on_reconnect_attempt callback with attempt count and delay" do
      config = Lavinmq::Config.new
      manager = Lavinmq::ConnectionManager.new("amqp://localhost", config)

      attempts = [] of Int32
      delays = [] of Float64

      manager.on_reconnect_attempt do |attempt, delay|
        attempts << attempt
        delays << delay
      end

      # Verify callback can be set
      manager.@on_reconnect_attempt.should_not be_nil
    end
  end
end
