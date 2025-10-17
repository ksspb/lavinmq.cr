require "../spec_helper"

describe Lavinmq::AckTracker do
  it "tracks unacked messages" do
    tracker = Lavinmq::AckTracker.new

    tracker.track(1_u64)
    tracker.track(2_u64)
    tracker.track(3_u64)

    tracker.count.should eq(3)
    tracker.unacked_tags.should eq([1_u64, 2_u64, 3_u64])
  end

  it "removes single ack" do
    tracker = Lavinmq::AckTracker.new

    tracker.track(1_u64)
    tracker.track(2_u64)
    tracker.track(3_u64)

    tracker.ack(2_u64, multiple: false)

    tracker.count.should eq(2)
    tracker.unacked_tags.should contain(1_u64)
    tracker.unacked_tags.should contain(3_u64)
    tracker.unacked_tags.should_not contain(2_u64)
  end

  it "removes multiple acks" do
    tracker = Lavinmq::AckTracker.new

    tracker.track(1_u64)
    tracker.track(2_u64)
    tracker.track(3_u64)
    tracker.track(4_u64)
    tracker.track(5_u64)

    # Ack all up to and including 3
    tracker.ack(3_u64, multiple: true)

    tracker.count.should eq(2)
    tracker.unacked_tags.should eq([4_u64, 5_u64])
  end

  it "removes single nack" do
    tracker = Lavinmq::AckTracker.new

    tracker.track(1_u64)
    tracker.track(2_u64)
    tracker.track(3_u64)

    tracker.nack(2_u64, multiple: false)

    tracker.count.should eq(2)
    tracker.unacked_tags.should contain(1_u64)
    tracker.unacked_tags.should contain(3_u64)
  end

  it "removes multiple nacks" do
    tracker = Lavinmq::AckTracker.new

    tracker.track(1_u64)
    tracker.track(2_u64)
    tracker.track(3_u64)
    tracker.track(4_u64)

    # Nack all up to and including 3
    tracker.nack(3_u64, multiple: true)

    tracker.count.should eq(1)
    tracker.unacked_tags.should eq([4_u64])
  end

  it "clears all tags" do
    tracker = Lavinmq::AckTracker.new

    tracker.track(1_u64)
    tracker.track(2_u64)
    tracker.track(3_u64)

    tracker.clear

    tracker.count.should eq(0)
    tracker.unacked_tags.should be_empty
  end

  it "is fiber-safe" do
    tracker = Lavinmq::AckTracker.new

    # Track messages from multiple fibers
    10.times do |i|
      spawn do
        100.times do |j|
          tag = (i * 100 + j).to_u64
          tracker.track(tag)
        end
      end
    end

    # Wait for all fibers
    sleep 100.milliseconds

    # Should have 1000 tracked messages
    tracker.count.should eq(1000)

    # Ack from multiple fibers
    5.times do |i|
      spawn do
        tracker.ack((i * 200 + 199).to_u64, multiple: true)
      end
    end

    # Wait for acks
    sleep 100.milliseconds

    # Should have removed all up to 999
    tracker.count.should eq(0)
  end
end
