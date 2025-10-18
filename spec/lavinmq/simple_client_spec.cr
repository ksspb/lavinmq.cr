require "../spec_helper"

describe "Lavinmq::Client (Simplified Architecture)" do
  pending "connects to LavinMQ and uses on_close event for reconnection (requires server)"
  pending "automatically reconnects on connection loss using on_close callback (requires server)"
  pending "creates producers without ConnectionPool or ConnectionManager (requires server)"
  pending "creates consumers that auto-resubscribe on reconnection (requires server)"
end
