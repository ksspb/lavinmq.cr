#!/usr/bin/env crystal

# Run all benchmarks
puts "LavinMQ Benchmark Suite (v0.4.2)"
puts "=" * 60
puts "Architecture: Simplified with hybrid event+poll reconnection"
puts "Features: Lock-free buffer, zero-latency publish, mutex-based sync"
puts
puts "Prerequisites: LavinMQ/RabbitMQ running on localhost:5672"
puts "=" * 60
puts

benchmarks = [
  {"Buffer Performance", "./buffer_performance.cr"},
  {"Publish Throughput", "./publish_throughput.cr"},
  {"Concurrent Publishers", "./concurrent_publishers.cr"},
  {"Latency Distribution", "./latency_distribution.cr"},
]

benchmarks.each_with_index do |(name, file), index|
  puts
  puts "=" * 60
  puts "Benchmark #{index + 1}/#{benchmarks.size}: #{name}"
  puts "=" * 60
  puts

  result = `crystal run #{file} --release 2>&1`
  puts result

  if result.includes?("Error")
    puts
    puts "⚠️  Benchmark failed - continuing with next benchmark..."
  end

  sleep 1 if index < benchmarks.size - 1
end

puts
puts "=" * 60
puts "All benchmarks complete!"
puts "=" * 60
puts
puts "Note: Reconnection benchmark requires manual intervention"
puts "      Run separately: crystal run benchmark/reconnection_performance.cr --release"
puts
