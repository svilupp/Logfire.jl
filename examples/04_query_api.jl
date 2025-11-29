# Query API Example - Download data from Logfire
#
# Prerequisites:
# 1. Set LOGFIRE_READ_TOKEN in your .env file or environment
# 2. Have some data in your Logfire project
#
# Run: julia --project examples/query_api_example.jl

using Pkg
Pkg.activate(dirname(@__DIR__))

using Logfire
using DotEnv
using Dates

# Load environment variables from .env
DotEnv.load!(joinpath(dirname(@__DIR__), ".env"))

println("=" ^ 60)
println("Logfire Query API Example")
println("=" ^ 60)

# Create query client (uses LOGFIRE_READ_TOKEN from environment)
client = LogfireQueryClient()
println("\nQuery client created successfully\n")

# =============================================================================
# Example 1: Simple query - get recent spans (row-oriented)
# =============================================================================
println("-" ^ 60)
println("Example 1: Recent Spans (row-oriented)")
println("-" ^ 60)

rows = query_json(client, """
    SELECT span_name, duration, start_timestamp
    FROM records
    ORDER BY start_timestamp DESC
    LIMIT 5
""")

println("Found $(length(rows)) rows:\n")
for (i, row) in enumerate(rows)
    println("  $i. $(row["span_name"]) (duration: $(row["duration"]))")
end

# =============================================================================
# Example 2: Aggregation query - most common operations
# =============================================================================
println("\n" * "-" ^ 60)
println("Example 2: Most Common Operations")
println("-" ^ 60)

ops = query_json(client, """
    SELECT COUNT() AS count, span_name
    FROM records
    GROUP BY span_name
    ORDER BY count DESC
    LIMIT 10
""")

println("Top operations by count:\n")
for op in ops
    println("  - $(op["span_name"]): $(op["count"]) occurrences")
end

# =============================================================================
# Example 3: Column-oriented query
# =============================================================================
println("\n" * "-" ^ 60)
println("Example 3: Column-Oriented Data")
println("-" ^ 60)

cols = query_json(client, """
    SELECT span_name, duration
    FROM records
    WHERE duration IS NOT NULL
    ORDER BY duration DESC
    LIMIT 5
"""; row_oriented = false)

println("Column-oriented result structure:")
println("  Keys: $(collect(keys(cols)))")

# Access columns directly
span_names = cols["span_name"]
durations = cols["duration"]
println("\n  Slowest spans:")
for (name, dur) in zip(span_names, durations)
    println("    - $name: $(dur)s")
end

# =============================================================================
# Example 4: Exception analysis
# =============================================================================
println("\n" * "-" ^ 60)
println("Example 4: Exception Analysis")
println("-" ^ 60)

errors = query_json(client, """
    SELECT exception_type, exception_message, trace_id
    FROM records
    WHERE is_exception
    ORDER BY start_timestamp DESC
    LIMIT 5
""")

if isempty(errors)
    println("No exceptions found (good news!)")
else
    println("Recent exceptions:\n")
    for err in errors
        exc_type = err["exception_type"]
        exc_msg = something(err["exception_message"], "")
        # Truncate long messages
        msg_display = length(exc_msg) > 50 ? exc_msg[1:50] * "..." : exc_msg
        println("  - [$exc_type] $msg_display")
    end
end

# =============================================================================
# Example 5: CSV export
# =============================================================================
println("\n" * "-" ^ 60)
println("Example 5: CSV Export")
println("-" ^ 60)

csv_data = query_csv(client, """
    SELECT span_name, duration, start_timestamp
    FROM records
    ORDER BY start_timestamp DESC
    LIMIT 10
""")

# Show first few lines of CSV
lines = split(csv_data, "\n")
println("CSV preview (first 5 lines):\n")
for line in lines[1:min(5, length(lines))]
    println("  $line")
end

# Optionally save to file
csv_file = joinpath(dirname(@__DIR__), "examples", "export.csv")
open(csv_file, "w") do f
    write(f, csv_data)
end
println("\nFull CSV saved to: $csv_file")

# =============================================================================
# Example 6: Time-filtered query
# =============================================================================
println("\n" * "-" ^ 60)
println("Example 6: Time-Filtered Query (last 24 hours)")
println("-" ^ 60)

now_utc = now(UTC)
yesterday = now_utc - Hour(24)
min_ts = Dates.format(yesterday, "yyyy-mm-ddTHH:MM:SSZ")

recent = query_json(client, """
    SELECT COUNT() as count, span_name
    FROM records
    GROUP BY span_name
    ORDER BY count DESC
    LIMIT 5
"""; min_timestamp = min_ts)

println("Operations in the last 24 hours:\n")
for r in recent
    println("  - $(r["span_name"]): $(r["count"])")
end

println("\n" * "=" ^ 60)
println("Query API Example Complete!")
println("=" ^ 60)
