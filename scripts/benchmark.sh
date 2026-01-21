#!/bin/bash
# Test Suite Benchmark Script
# Usage: ./scripts/benchmark.sh [runs]
# Default: 3 runs

set -e

RUNS=${1:-3}
OUTPUT_DIR="test/benchmark_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "============================================"
echo "Test Suite Benchmark"
echo "Started: $(date)"
echo "Runs: $RUNS"
echo "============================================"

# System info
echo ""
echo "System Information:"
echo "  Elixir: $(elixir --version | head -1)"
echo "  CPUs: $(sysctl -n hw.ncpu 2>/dev/null || nproc)"
echo "  Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024/1024}')"

# Arrays to store results
declare -a TOTAL_TIMES
declare -a ASYNC_TIMES
declare -a SYNC_TIMES
declare -a WALL_TIMES

for i in $(seq 1 $RUNS); do
    echo ""
    echo ">>> Run $i/$RUNS"

    # Run tests and capture output
    START=$(date +%s.%N)
    OUTPUT=$(mix test --color 2>&1) || true
    END=$(date +%s.%N)

    WALL_TIME=$(echo "$END - $START" | bc)

    # Parse timing from output: "Finished in 342.7 seconds (271.9s async, 70.8s sync)"
    TIMING=$(echo "$OUTPUT" | grep -E "Finished in [0-9.]+ seconds")

    TOTAL=$(echo "$TIMING" | sed -E 's/.*Finished in ([0-9.]+) seconds.*/\1/')
    ASYNC=$(echo "$TIMING" | sed -E 's/.*\(([0-9.]+)s async.*/\1/')
    SYNC=$(echo "$TIMING" | sed -E 's/.*async, ([0-9.]+)s sync.*/\1/')

    # Store results
    TOTAL_TIMES+=($TOTAL)
    ASYNC_TIMES+=($ASYNC)
    SYNC_TIMES+=($SYNC)
    WALL_TIMES+=($WALL_TIME)

    # Get test count
    COUNTS=$(echo "$OUTPUT" | grep -E "[0-9]+ tests?,")

    echo "    Total: ${TOTAL}s | Async: ${ASYNC}s | Sync: ${SYNC}s | Wall: ${WALL_TIME}s"
    echo "    $COUNTS"
done

# Calculate averages
avg() {
    local sum=0
    local count=0
    for val in "$@"; do
        sum=$(echo "$sum + $val" | bc)
        ((count++))
    done
    echo "scale=2; $sum / $count" | bc
}

AVG_TOTAL=$(avg "${TOTAL_TIMES[@]}")
AVG_ASYNC=$(avg "${ASYNC_TIMES[@]}")
AVG_SYNC=$(avg "${SYNC_TIMES[@]}")
AVG_WALL=$(avg "${WALL_TIMES[@]}")

# Find min/max
MIN_TOTAL=$(printf '%s\n' "${TOTAL_TIMES[@]}" | sort -n | head -1)
MAX_TOTAL=$(printf '%s\n' "${TOTAL_TIMES[@]}" | sort -n | tail -1)

echo ""
echo "============================================"
echo "Summary"
echo "============================================"
echo "  Average Total: ${AVG_TOTAL}s"
echo "  Average Async: ${AVG_ASYNC}s"
echo "  Average Sync:  ${AVG_SYNC}s"
echo "  Average Wall:  ${AVG_WALL}s"
echo "  Min Total:     ${MIN_TOTAL}s"
echo "  Max Total:     ${MAX_TOTAL}s"

# Save results
RESULT_FILE="$OUTPUT_DIR/benchmark_$TIMESTAMP.txt"
cat > "$RESULT_FILE" << EOF
Test Suite Benchmark Results
============================
Date: $(date)
Runs: $RUNS

Individual Runs:
$(for i in $(seq 0 $((RUNS-1))); do
    echo "  Run $((i+1)): Total=${TOTAL_TIMES[$i]}s, Async=${ASYNC_TIMES[$i]}s, Sync=${SYNC_TIMES[$i]}s, Wall=${WALL_TIMES[$i]}s"
done)

Summary:
  Average Total: ${AVG_TOTAL}s
  Average Async: ${AVG_ASYNC}s
  Average Sync:  ${AVG_SYNC}s
  Average Wall:  ${AVG_WALL}s
  Min Total:     ${MIN_TOTAL}s
  Max Total:     ${MAX_TOTAL}s
EOF

echo ""
echo "Results saved to: $RESULT_FILE"

# Also get slowest tests
echo ""
echo "Getting slowest 20 tests..."
mix test --slowest 20 2>&1 | grep -E "^\s+[0-9]+\." | head -20 > "$OUTPUT_DIR/slowest_$TIMESTAMP.txt"
echo "Slowest tests saved to: $OUTPUT_DIR/slowest_$TIMESTAMP.txt"
