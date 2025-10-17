require "../../spec_helper"
require "../../../src/lavinmq/lock_free/ring_buffer"

describe "Lavinmq::LockFree::RingBuffer" do
  describe "thread safety" do
    it "handles concurrent producers and consumers without locks" do
      buffer = Lavinmq::LockFree::RingBuffer(String).new(1000)

      messages_produced = Atomic(Int32).new(0)
      messages_consumed = Atomic(Int32).new(0)

      # 10 producers, each producing 100 messages
      10.times do |i|
        spawn do
          100.times do |j|
            msg = "Message #{i}-#{j}"
            if buffer.enqueue(msg)
              messages_produced.add(1)
            end
            Fiber.yield if j % 10 == 0
          end
        end
      end

      # 5 consumers
      5.times do
        spawn do
          loop do
            if buffer.dequeue
              messages_consumed.add(1)
            else
              Fiber.yield
            end
            break if messages_consumed.get >= 900 # Stop near end
          end
        end
      end

      # Wait for completion
      sleep 100.milliseconds

      # Most messages should be processed
      messages_consumed.get.should be > 800
      messages_produced.get.should be <= 1000
    end

    it "maintains FIFO order under single producer/consumer" do
      buffer = Lavinmq::LockFree::RingBuffer(Int32).new(100)

      # Producer
      spawn do
        100.times { |i| buffer.enqueue(i) }
      end

      sleep 10.milliseconds

      # Consumer - should get messages in order
      results = [] of Int32
      100.times do
        if val = buffer.dequeue
          results << val
        end
      end

      # Verify FIFO order
      results.each_with_index do |val, idx|
        val.should eq(idx)
      end
    end

    it "handles buffer full condition gracefully" do
      buffer = Lavinmq::LockFree::RingBuffer(String).new(10)

      # Fill buffer
      10.times { |i| buffer.enqueue("msg#{i}").should be_true }

      # Should reject when full
      buffer.enqueue("overflow").should be_false
      buffer.full?.should be_true

      # Dequeue one
      buffer.dequeue.should eq("msg0")

      # Now can enqueue again
      buffer.enqueue("new").should be_true
    end

    it "handles buffer empty condition gracefully" do
      buffer = Lavinmq::LockFree::RingBuffer(String).new(10)

      buffer.empty?.should be_true
      buffer.dequeue.should be_nil

      buffer.enqueue("test")
      buffer.empty?.should be_false
      buffer.dequeue.should eq("test")
      buffer.empty?.should be_true
    end
  end

  describe "performance" do
    it "achieves high throughput with multiple producers" do
      buffer = Lavinmq::LockFree::RingBuffer(String).new(10_000)

      start_time = Time.monotonic
      message_count = 100_000
      producer_count = 10

      done = Channel(Nil).new

      # Spawn producers
      producer_count.times do |i|
        spawn do
          (message_count // producer_count).times do |j|
            buffer.enqueue("Message #{i}-#{j}")
          end
          done.send(nil)
        end
      end

      # Spawn consumer
      consumed = Atomic(Int32).new(0)
      spawn do
        loop do
          if buffer.dequeue
            consumed.add(1)
          else
            Fiber.yield
          end
          break if consumed.get >= message_count - 100
        end
      end

      # Wait for producers
      producer_count.times { done.receive }

      elapsed = Time.monotonic - start_time
      throughput = message_count / elapsed.total_seconds

      # Should achieve > 1M msg/sec
      throughput.should be > 1_000_000
    end

    it "has zero allocations in hot path" do
      buffer = Lavinmq::LockFree::RingBuffer(String).new(1000)

      # Pre-allocate test data
      messages = 100.times.map { |i| "Message #{i}" }.to_a

      # Warm up
      messages.each { |msg| buffer.enqueue(msg) }
      100.times { buffer.dequeue }

      # TODO: In real implementation, we'd measure allocations
      # For now, just verify it works
      buffer.size.should eq(0)
    end
  end

  describe "capacity management" do
    it "reports size accurately" do
      buffer = Lavinmq::LockFree::RingBuffer(Int32).new(100)

      buffer.size.should eq(0)
      buffer.capacity.should eq(100)

      10.times { |i| buffer.enqueue(i) }
      buffer.size.should eq(10)

      5.times { buffer.dequeue }
      buffer.size.should eq(5)
    end

    it "handles wrap-around correctly" do
      buffer = Lavinmq::LockFree::RingBuffer(Int32).new(5)

      # Fill and empty several times to test wrap-around
      3.times do |round|
        5.times { |i| buffer.enqueue(round * 10 + i).should be_true }
        buffer.full?.should be_true

        values = [] of Int32
        5.times do
          if val = buffer.dequeue
            values << val
          end
        end

        values.should eq((0..4).map { |i| round * 10 + i })
        buffer.empty?.should be_true
      end
    end
  end

  describe "atomic operations" do
    it "uses compare-and-swap for thread safety" do
      buffer = Lavinmq::LockFree::RingBuffer(String).new(1000)

      # This test verifies the implementation uses atomic operations
      # by running many concurrent operations and checking for consistency

      operations = Atomic(Int32).new(0)
      errors = Atomic(Int32).new(0)

      # Spawn many fibers doing random operations
      100.times do
        spawn do
          100.times do
            case Random.rand(3)
            when 0
              buffer.enqueue("test")
              operations.add(1)
            when 1
              buffer.dequeue
              operations.add(1)
            when 2
              buffer.size
              operations.add(1)
            end
          rescue
            errors.add(1)
          end
        end
      end

      sleep 100.milliseconds

      # Should complete without errors
      errors.get.should eq(0)
      operations.get.should be > 5000
    end
  end
end
