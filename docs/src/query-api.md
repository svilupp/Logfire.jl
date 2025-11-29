# Query API

Download your telemetry data from Logfire using SQL queries.

## Setup

### 1. Create a Read Token

1. Go to [logfire.pydantic.dev](https://logfire.pydantic.dev)
2. Select your project
3. Click Settings (gear icon) → Read tokens tab
4. Click "Create read token"
5. Copy the token immediately (it won't be shown again)

### 2. Configure Environment

Add to your `.env` file:
```
LOGFIRE_READ_TOKEN=pylf_v1_us_...
```

Or set in Julia:
```julia
ENV["LOGFIRE_READ_TOKEN"] = "pylf_v1_us_..."
```

## Basic Usage

```julia
using DotEnv
DotEnv.load!()  # Load .env file (must call explicitly)

using Logfire

# Create client (uses LOGFIRE_READ_TOKEN from environment)
client = LogfireQueryClient()

# Or provide token directly:
# client = LogfireQueryClient(read_token="pylf_v1_us_...")

# Query with row-oriented results (default)
rows = query_json(client, "SELECT span_name, duration FROM records LIMIT 10")

for row in rows
    println("$(row["span_name"]): $(row["duration"])s")
end
```

## Response Formats

### Row-Oriented (Default)

Returns a `Vector{Dict{String,Any}}` where each element is a row:

```julia
rows = query_json(client, "SELECT span_name, duration FROM records LIMIT 3")
# [
#   Dict("span_name" => "api-request", "duration" => 0.123),
#   Dict("span_name" => "db-query", "duration" => 0.045),
#   Dict("span_name" => "cache-hit", "duration" => 0.002)
# ]
```

### Column-Oriented

Returns a `Dict{String,Vector}` with column names as keys:

```julia
cols = query_json(client, "SELECT span_name, duration FROM records LIMIT 3"; row_oriented=false)
# Dict(
#   "span_name" => ["api-request", "db-query", "cache-hit"],
#   "duration" => [0.123, 0.045, 0.002]
# )
```

### CSV Export

Returns raw CSV as a string:

```julia
csv_data = query_csv(client, "SELECT span_name, duration FROM records LIMIT 100")

# Save to file
open("export.csv", "w") do f
    write(f, csv_data)
end
```

## Query Parameters

```julia
query_json(client, sql;
    row_oriented = true,      # true for Vector{Dict}, false for Dict{String,Vector}
    min_timestamp = nothing,  # ISO-8601 lower bound, e.g., "2024-01-01T00:00:00Z"
    max_timestamp = nothing,  # ISO-8601 upper bound
    limit = nothing           # Max rows (default: 500, max: 10000)
)
```

### Time-Filtered Query

```julia
using Dates

# Last 24 hours
yesterday = now(UTC) - Hour(24)
min_ts = Dates.format(yesterday, "yyyy-mm-ddTHH:MM:SSZ")

rows = query_json(client, """
    SELECT span_name, duration
    FROM records
    ORDER BY start_timestamp DESC
"""; min_timestamp=min_ts, limit=100)
```

## EU Region

For EU-hosted projects, use the EU endpoint:

```julia
client = LogfireQueryClient(endpoint=QUERY_ENDPOINT_EU)
```

## Example Queries

### Most Common Operations

```sql
SELECT COUNT() AS count, span_name
FROM records
GROUP BY span_name
ORDER BY count DESC
LIMIT 10
```

### Recent Exceptions

```sql
SELECT exception_type, exception_message, trace_id
FROM records
WHERE is_exception
ORDER BY start_timestamp DESC
LIMIT 20
```

### P95 Latency by Operation

```sql
SELECT
    span_name,
    approx_percentile_cont(0.95) WITHIN GROUP (ORDER BY duration) as P95
FROM records
WHERE duration IS NOT NULL
GROUP BY span_name
ORDER BY P95 DESC
```

### Total Duration by Operation

```sql
SELECT SUM(duration) AS total_duration, span_name
FROM records
WHERE duration IS NOT NULL
GROUP BY span_name
ORDER BY total_duration DESC
```

### Slowest Traces

```sql
SELECT trace_id, duration, message
FROM records
ORDER BY duration DESC
LIMIT 10
```

### Time Series - Requests per Minute

```sql
SELECT
    date_trunc('minute', start_timestamp) AS minute,
    COUNT() as count
FROM records
GROUP BY minute
ORDER BY minute DESC
LIMIT 60
```

### LLM Token Usage

```sql
SELECT
    span_name,
    SUM(CAST(attributes['gen_ai.usage.input_tokens'] AS INTEGER)) as input_tokens,
    SUM(CAST(attributes['gen_ai.usage.output_tokens'] AS INTEGER)) as output_tokens
FROM records
WHERE span_name LIKE 'gen_ai%'
GROUP BY span_name
```

## Full Example

See [`examples/query_api_example.jl`](https://github.com/your-repo/Logfire.jl/blob/main/examples/query_api_example.jl) for a complete working example.

```julia
using Logfire
using DotEnv
using Dates

DotEnv.load!()

client = LogfireQueryClient()

# Get recent operations
rows = query_json(client, """
    SELECT span_name, duration, start_timestamp
    FROM records
    ORDER BY start_timestamp DESC
    LIMIT 5
""")

println("Recent operations:")
for row in rows
    println("  $(row["span_name"]): $(row["duration"])s")
end

# Aggregate stats
stats = query_json(client, """
    SELECT COUNT() AS count, span_name
    FROM records
    GROUP BY span_name
    ORDER BY count DESC
    LIMIT 5
""")

println("\nTop operations:")
for s in stats
    println("  $(s["span_name"]): $(s["count"]) occurrences")
end

# Export to CSV
csv = query_csv(client, "SELECT * FROM records LIMIT 1000")
open("telemetry_export.csv", "w") do f
    write(f, csv)
end
println("\nExported to telemetry_export.csv")
```
