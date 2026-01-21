# Test Suite Benchmark Script
# Run with: mix run test/support/benchmark.exs
#
# This script runs the test suite multiple times and collects timing data
# to establish a reproducible baseline for optimization comparisons.

defmodule TestBenchmark do
  @moduledoc """
  Benchmark script for the test suite.

  This module runs the test suite multiple times, records timing data, and
  generates reports that can be used as a baseline for performance
  comparisons when optimizing the application or tests.

  ## How to run

    mix run test/support/benchmark.exs

  ## Output

  After running, this script writes JSON and text reports into
  `test/benchmark_results/`:

    * `benchmark_<timestamp>.json` — full benchmark data (timings, stats, system info)
    * `benchmark_<timestamp>.txt` — human-readable text summary
    * `latest.json` — copy of the most recent benchmark JSON report
  """

  @runs 3
  @output_dir "test/benchmark_results"

  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Test Suite Benchmark")
    IO.puts("Started: #{DateTime.utc_now() |> DateTime.to_iso8601()}")
    IO.puts(String.duplicate("=", 60))

    # Ensure output directory exists
    File.mkdir_p!(@output_dir)

    # Record system info
    system_info = collect_system_info()
    IO.puts("\nSystem Info:")
    IO.puts("  Elixir: #{system_info.elixir_version}")
    IO.puts("  OTP: #{system_info.otp_version}")
    IO.puts("  CPUs: #{system_info.schedulers}")
    IO.puts("  Memory: #{format_bytes(system_info.total_memory)}")

    # Run benchmarks
    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts("Running #{@runs} benchmark iterations...")
    IO.puts(String.duplicate("-", 60))

    results =
      Enum.map(1..@runs, fn run_number ->
        IO.puts("\n>>> Run #{run_number}/#{@runs}")
        run_test_suite(run_number)
      end)

    # Calculate statistics
    stats = calculate_stats(results)

    # Get slowest tests (single run with --slowest flag)
    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts("Identifying slowest tests...")
    IO.puts(String.duplicate("-", 60))
    slowest = get_slowest_tests(20)

    # Generate report
    report = generate_report(system_info, results, stats, slowest)

    # Save results
    timestamp =
      DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.replace(~r/[:\.]/, "-")

    json_file = Path.join(@output_dir, "benchmark_#{timestamp}.json")
    text_file = Path.join(@output_dir, "benchmark_#{timestamp}.txt")
    latest_file = Path.join(@output_dir, "latest.json")

    File.write!(json_file, Jason.encode!(report, pretty: true))
    File.write!(text_file, format_text_report(report))
    File.write!(latest_file, Jason.encode!(report, pretty: true))

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Benchmark Complete!")
    IO.puts(String.duplicate("=", 60))
    IO.puts("\nResults saved to:")
    IO.puts("  #{json_file}")
    IO.puts("  #{text_file}")
    IO.puts("  #{latest_file} (symlink to latest)")

    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts("Summary")
    IO.puts(String.duplicate("-", 60))
    IO.puts("  Total tests: #{stats.test_count}")
    IO.puts("  Average runtime: #{format_duration(stats.avg_total_ms)}")
    IO.puts("  Min runtime: #{format_duration(stats.min_total_ms)}")
    IO.puts("  Max runtime: #{format_duration(stats.max_total_ms)}")
    IO.puts("  Std deviation: #{format_duration(stats.std_dev_ms)}")
    IO.puts("  Async time (avg): #{format_duration(stats.avg_async_ms)}")
    IO.puts("  Sync time (avg): #{format_duration(stats.avg_sync_ms)}")

    report
  end

  defp collect_system_info do
    %{
      elixir_version: System.version(),
      otp_version: :erlang.system_info(:otp_release) |> to_string(),
      schedulers: System.schedulers_online(),
      total_memory: :erlang.memory(:total),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp run_test_suite(run_number) do
    IO.puts("    Starting test run...")

    # Record memory before
    memory_before = :erlang.memory(:total)

    # Run mix test and capture output
    start_time = System.monotonic_time(:millisecond)

    {output, exit_code} =
      System.cmd("mix", ["test", "--color"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    end_time = System.monotonic_time(:millisecond)
    wall_clock_ms = end_time - start_time

    # Record memory after
    memory_after = :erlang.memory(:total)

    # Parse the output for timing info
    timing = parse_test_output(output)

    result = %{
      run_number: run_number,
      exit_code: exit_code,
      wall_clock_ms: wall_clock_ms,
      total_ms: timing.total_ms,
      async_ms: timing.async_ms,
      sync_ms: timing.sync_ms,
      test_count: timing.test_count,
      failures: timing.failures,
      skipped: timing.skipped,
      memory_before: memory_before,
      memory_after: memory_after,
      memory_delta: memory_after - memory_before
    }

    IO.puts(
      "    Completed in #{format_duration(wall_clock_ms)} (#{timing.test_count} tests, #{timing.failures} failures)"
    )

    result
  end

  defp parse_test_output(output) do
    # Parse: "Finished in 342.7 seconds (271.9s async, 70.8s sync)"
    timing_regex = ~r/Finished in ([\d.]+) seconds \(([\d.]+)s async, ([\d.]+)s sync\)/

    # Parse: "1638 tests, 0 failures, 2 skipped"
    count_regex = ~r/(\d+) tests?, (\d+) failures?(?:, (\d+) skipped)?/

    timing_match = Regex.run(timing_regex, output)
    count_match = Regex.run(count_regex, output)

    # Use pattern matching for safer extraction with fallback to defaults
    {total_ms, async_ms, sync_ms} =
      case timing_match do
        [_, total_s, async_s, sync_s] ->
          {
            parse_float(total_s) * 1000,
            parse_float(async_s) * 1000,
            parse_float(sync_s) * 1000
          }

        _ ->
          {0, 0, 0}
      end

    {test_count, failures, skipped} =
      case count_match do
        [_, tests_s, failures_s, skipped_s] ->
          skipped_count =
            case skipped_s do
              nil -> 0
              _ -> String.to_integer(skipped_s)
            end

          {
            String.to_integer(tests_s),
            String.to_integer(failures_s),
            skipped_count
          }

        [_, tests_s, failures_s] ->
          {
            String.to_integer(tests_s),
            String.to_integer(failures_s),
            0
          }

        _ ->
          {0, 0, 0}
      end

    %{
      total_ms: total_ms,
      async_ms: async_ms,
      sync_ms: sync_ms,
      test_count: test_count,
      failures: failures,
      skipped: skipped
    }
  end

  defp get_slowest_tests(count) do
    IO.puts("    Running mix test --slowest #{count}...")

    {output, _exit_code} =
      System.cmd("mix", ["test", "--slowest", "#{count}"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    # Parse slowest tests output
    # Format: "  * test name (123.4ms) (test/path_test.exs:42)"
    slowest_regex = ~r/^\s+\d+\.\s+(.+?)\s+\((\d+(?:\.\d+)?)(ms|s)\)/m

    Regex.scan(slowest_regex, output)
    |> Enum.map(fn [_full, name, time_str, unit] ->
      time = parse_float(time_str)
      time_ms = if unit == "s", do: time * 1000, else: time

      %{
        name: String.trim(name),
        time_ms: time_ms
      }
    end)
    |> Enum.take(count)
  end

  defp calculate_stats(results) do
    totals = Enum.map(results, & &1.total_ms)
    asyncs = Enum.map(results, & &1.async_ms)
    syncs = Enum.map(results, & &1.sync_ms)

    %{
      test_count: List.first(results).test_count,
      run_count: length(results),
      avg_total_ms: average(totals),
      min_total_ms: Enum.min(totals),
      max_total_ms: Enum.max(totals),
      std_dev_ms: std_dev(totals),
      avg_async_ms: average(asyncs),
      avg_sync_ms: average(syncs),
      total_failures: Enum.sum(Enum.map(results, & &1.failures))
    }
  end

  defp average([]), do: 0
  defp average(list), do: Enum.sum(list) / length(list)

  # Safely parse a string to float, handling both "123" and "123.4" formats
  defp parse_float(str) do
    {value, ""} = Float.parse(str)
    value
  end

  defp std_dev([]), do: 0

  defp std_dev(list) do
    avg = average(list)
    variance = Enum.map(list, fn x -> :math.pow(x - avg, 2) end) |> average()
    :math.sqrt(variance)
  end

  defp generate_report(system_info, results, stats, slowest) do
    %{
      benchmark_version: "1.0",
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      system: system_info,
      runs: results,
      statistics: stats,
      slowest_tests: slowest
    }
  end

  defp format_text_report(report) do
    """
    ================================================================================
    Test Suite Benchmark Report
    Generated: #{report.generated_at}
    ================================================================================

    SYSTEM INFORMATION
    ------------------
    Elixir Version: #{report.system.elixir_version}
    OTP Version: #{report.system.otp_version}
    Schedulers (CPUs): #{report.system.schedulers}
    Total Memory: #{format_bytes(report.system.total_memory)}

    BENCHMARK RESULTS
    -----------------
    Number of Runs: #{report.statistics.run_count}
    Total Tests: #{report.statistics.test_count}
    Total Failures: #{report.statistics.total_failures}

    Timing Statistics:
      Average Runtime: #{format_duration(report.statistics.avg_total_ms)}
      Minimum Runtime: #{format_duration(report.statistics.min_total_ms)}
      Maximum Runtime: #{format_duration(report.statistics.max_total_ms)}
      Std Deviation: #{format_duration(report.statistics.std_dev_ms)}

    Time Breakdown (Average):
      Async Tests: #{format_duration(report.statistics.avg_async_ms)} (#{percentage(report.statistics.avg_async_ms, report.statistics.avg_total_ms)}%)
      Sync Tests: #{format_duration(report.statistics.avg_sync_ms)} (#{percentage(report.statistics.avg_sync_ms, report.statistics.avg_total_ms)}%)

    INDIVIDUAL RUN RESULTS
    ----------------------
    #{format_run_results(report.runs)}

    SLOWEST TESTS
    -------------
    #{format_slowest_tests(report.slowest_tests)}

    ================================================================================
    """
  end

  defp format_run_results(runs) do
    runs
    |> Enum.map(fn run ->
      "Run #{run.run_number}: #{format_duration(run.total_ms)} (#{run.test_count} tests, #{run.failures} failures)"
    end)
    |> Enum.join("\n")
  end

  defp format_slowest_tests(tests) do
    tests
    |> Enum.with_index(1)
    |> Enum.map(fn {test, idx} ->
      "#{String.pad_leading("#{idx}", 2)}. #{format_duration(test.time_ms)} - #{test.name}"
    end)
    |> Enum.join("\n")
  end

  defp format_duration(ms) when is_float(ms) or is_integer(ms) do
    cond do
      ms >= 60_000 ->
        minutes = trunc(ms / 60_000)
        seconds = Float.round((ms - minutes * 60_000) / 1000, 1)
        "#{minutes}m #{seconds}s"

      ms >= 1000 ->
        "#{Float.round(ms / 1000, 2)}s"

      true ->
        "#{Float.round(ms * 1.0, 1)}ms"
    end
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end

  defp percentage(part, total) when total > 0, do: Float.round(part / total * 100, 1)
  defp percentage(_, _), do: 0.0
end

# Run the benchmark
TestBenchmark.run()
