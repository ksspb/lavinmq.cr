require "../spec_helper"

describe Lavinmq::MessageBuffer do
  describe "#enqueue and #dequeue" do
    it "stores and retrieves messages" do
      buffer = Lavinmq::MessageBuffer.new(max_size: 3)
      buffer.enqueue("msg1")
      buffer.enqueue("msg2")

      buffer.dequeue.should eq "msg1"
      buffer.dequeue.should eq "msg2"
      buffer.dequeue.should be_nil
    end

    it "acts as a ring buffer when full" do
      buffer = Lavinmq::MessageBuffer.new(max_size: 2)
      buffer.enqueue("msg1")
      buffer.enqueue("msg2")
      buffer.enqueue("msg3") # Should drop msg1

      buffer.dropped_count.should eq 1
      buffer.dequeue.should eq "msg2"
      buffer.dequeue.should eq "msg3"
    end
  end

  describe "#drain" do
    it "returns all messages and clears buffer" do
      buffer = Lavinmq::MessageBuffer.new
      buffer.enqueue("msg1")
      buffer.enqueue("msg2")

      messages = buffer.drain
      messages.should eq ["msg1", "msg2"]
      buffer.empty?.should be_true
    end
  end

  describe "fiber safety" do
    it "handles concurrent access from multiple fibers" do
      buffer = Lavinmq::MessageBuffer.new(max_size: 100)
      channel = Channel(Nil).new

      10.times do |i|
        spawn do
          10.times do |j|
            buffer.enqueue("fiber-#{i}-msg-#{j}")
          end
          channel.send nil
        end
      end

      10.times { channel.receive }
      buffer.count.should eq 100
    end
  end

  describe "observability: buffer state" do
    it "exposes buffer size and capacity" do
      buffer = Lavinmq::MessageBuffer.new(max_size: 10)

      buffer.size.should eq 0
      buffer.capacity.should eq 10

      buffer.enqueue("msg1")
      buffer.enqueue("msg2")

      buffer.size.should eq 2
      buffer.capacity.should eq 10
    end

    it "reports empty and full states" do
      buffer = Lavinmq::MessageBuffer.new(max_size: 2)

      buffer.empty?.should be_true
      buffer.full?.should be_false

      buffer.enqueue("msg1")
      buffer.empty?.should be_false
      buffer.full?.should be_false

      buffer.enqueue("msg2")
      buffer.empty?.should be_false
      buffer.full?.should be_true
    end
  end
end
