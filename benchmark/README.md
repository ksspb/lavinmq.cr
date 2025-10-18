# LavinMQ Benchmarks

Comprehensive benchmark suite for testing LavinMQ client library performance (v0.4.2).

## Prerequisites

- LavinMQ or RabbitMQ running on `localhost:5672`
- Crystal compiler installed

## Quick Start

Run all benchmarks (except manual reconnection test):
```bash
crystal run benchmark/run_all.cr --release
```

## Individual Benchmarks

### 1. Buffer Performance
Tests lock-free ring buffer enqueue/dequeue performance.

```bash
crystal run benchmark/buffer_performance.cr --release
```

**Measures:**
- Sequential enqueue throughput
- Sequential drain throughput
- Concurrent enqueue from 100 fibers
- Latency per operation

**Expected Results:**
- Enqueue: >1M ops/sec
- Drain: >10M ops/sec
- Latency: <1μs average

### 2. Publish Throughput
Tests single-threaded publish throughput.

```bash
crystal run benchmark/publish_throughput.cr --release
```

**Measures:**
- Throughput for 1k, 10k, 100k messages
- Average latency per message
- Buffer utilization

**Expected Results:**
- Throughput: 1M+ msg/sec
- Latency: <1μs average

### 3. Concurrent Publishers
Tests multi-fiber concurrent publishing.

```bash
crystal run benchmark/concurrent_publishers.cr --release
```

**Measures:**
- Performance with 1, 10, 50, 100 concurrent fibers
- Total throughput under contention
- Buffer efficiency

**Expected Results:**
- Scales linearly with fiber count
- Maintains low latency under contention

### 4. Latency Distribution
Measures latency percentiles (p50, p95, p99, p99.9).

```bash
crystal run benchmark/latency_distribution.cr --release
```

**Measures:**
- 10,000 individual message latencies
- Min, max, avg, p50, p95, p99, p99.9
- Percentage under 1ms

**Expected Results:**
- p50: <1μs
- p95: <5μs
- p99: <10μs
- p99.9: <100μs

### 5. Reconnection Performance (Manual)
Tests reconnection detection and recovery time.

```bash
crystal run benchmark/reconnection_performance.cr --release
```

**Requires manual intervention:**
1. Start with LavinMQ running
2. Stop LavinMQ when prompted (simulate connection loss)
3. Restart LavinMQ to test reconnection

**Measures:**
- Time to detect disconnection
- Time to complete reconnection
- Message buffering during downtime
- Zero message loss

**Expected Results:**
- Detection: 0-100ms (event-driven with polling fallback)
- Reconnection: 100ms-30s (exponential backoff)
- Message buffering: All messages queued during downtime

## Architecture Being Tested

**v0.4.2 Features:**
- Simplified single-connection architecture
- Hybrid event+poll reconnection (0ms event + 100ms polling failsafe)
- Lock-free ring buffer (LockFree::RingBuffer)
- Zero-latency publish path
- Mutex-based synchronization (optimized for minimal contention)
- Connection retry with 5ms delays

## Performance Targets

Based on production requirements and previous benchmarks:

| Metric | Target | v0.4.2 Expected |
|--------|--------|-----------------|
| Peak Throughput | 1M+ msg/sec | 1.68M msg/sec |
| Sustained Load | 10k-100k msg/sec | ✅ Tested |
| Average Latency | <1ms | <1μs (1000x better) |
| p99 Latency | <10ms | <10μs (1000x better) |
| Reconnection Detection | <200ms | 0-100ms |
| Message Loss | 0 | 0 (with buffering) |

## Comparison with Previous Versions

### v0.4.2 (Current)
- Removed rate-limiting for maximum throughput
- 5ms retry delays (vs 50ms in v0.4.1)

### v0.4.1
- Fixed silent reconnection failures under high load
- Added hybrid event+poll detection

### v0.4.0
- Simplified architecture (removed ConnectionPool)
- Event-driven reconnection

### v0.2.5 (Baseline)
- ConnectionPool with atomic operations
- 1.68M msg/sec achieved

## Notes

- Run benchmarks with `--release` flag for accurate performance measurement
- Ensure LavinMQ/RabbitMQ has sufficient resources (CPU, memory, connections)
- Results may vary based on system hardware and LavinMQ configuration
- Benchmarks use fire-and-forget mode for maximum throughput testing
- For confirm mode benchmarks, expect ~30-50% throughput reduction due to confirmations
