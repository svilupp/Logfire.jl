# Query API client for downloading data from Logfire

"""
    LogfireQueryClient

Client for querying Logfire data via the Query API.

# Fields
- `read_token::String`: Logfire read token for authentication
- `endpoint::String`: Query API endpoint URL

# Example
```julia
using Logfire

# Create client (uses LOGFIRE_READ_TOKEN from environment)
client = LogfireQueryClient()

# Or with explicit token
client = LogfireQueryClient(read_token="pylf_v1_us_...")
```
"""
struct LogfireQueryClient
    read_token::String
    endpoint::String
end

"""
    LogfireQueryClient(; read_token=nothing, endpoint=QUERY_ENDPOINT_US)

Create a query client for downloading data from Logfire.

# Keywords
- `read_token::String`: Read token (or uses `LOGFIRE_READ_TOKEN` env var)
- `endpoint::String`: Query API endpoint (default: US region)

# Endpoints
- US: `https://logfire-us.pydantic.dev/v1/query`
- EU: `https://logfire-eu.pydantic.dev/v1/query`
"""
function LogfireQueryClient(;
        read_token::Union{String, Nothing} = nothing,
        endpoint::String = QUERY_ENDPOINT_US
)
    # Try to load .env if present
    try
        DotEnv.load!()
    catch
    end

    token = something(
        read_token,
        get(ENV, "LOGFIRE_READ_TOKEN", nothing)
    )

    if isnothing(token) || isempty(token)
        error("read_token is required. Provide it directly or set LOGFIRE_READ_TOKEN environment variable.")
    end

    return LogfireQueryClient(token, endpoint)
end

"""
    query_json(client, sql; row_oriented=true, kwargs...) -> Vector{Dict} or Dict

Execute a SQL query and return JSON data.

# Arguments
- `client::LogfireQueryClient`: Query client instance
- `sql::String`: SQL query to execute

# Keywords
- `row_oriented::Bool=true`: If true, returns `Vector{Dict}` (each row is a dict). If false, returns `Dict{String,Vector}` (column-oriented)
- `min_timestamp::String`: ISO-8601 lower bound for filtering (e.g., "2024-01-01T00:00:00Z")
- `max_timestamp::String`: ISO-8601 upper bound for filtering
- `limit::Int`: Maximum rows to return (default: 500, max: 10000)

# Returns
- Row-oriented (`row_oriented=true`): `Vector{Dict}` where each element is a row
- Column-oriented (`row_oriented=false`): `Dict{String,Vector}` with column names as keys

# Example
```julia
client = LogfireQueryClient()

# Get recent spans (row-oriented)
rows = query_json(client, "SELECT span_name, duration FROM records LIMIT 10")
for row in rows
    println("\$(row["span_name"]): \$(row["duration"])s")
end

# Get column-oriented data
cols = query_json(client, "SELECT span_name, duration FROM records LIMIT 10"; row_oriented=false)
println("Span names: ", cols["span_name"])
```
"""
function query_json(client::LogfireQueryClient, sql::String;
        row_oriented::Bool = true,
        min_timestamp::Union{String, Nothing} = nothing,
        max_timestamp::Union{String, Nothing} = nothing,
        limit::Union{Int, Nothing} = nothing
)
    params = Dict{String, Any}("sql" => sql)

    if !isnothing(min_timestamp)
        params["min_timestamp"] = min_timestamp
    end
    if !isnothing(max_timestamp)
        params["max_timestamp"] = max_timestamp
    end
    if !isnothing(limit)
        params["limit"] = string(limit)
    end

    headers = [
        "Authorization" => "Bearer $(client.read_token)",
        "Accept" => "application/json"
    ]

    response = HTTP.get(client.endpoint, headers; query = params)

    if response.status != 200
        error("Query failed with status $(response.status): $(String(response.body))")
    end

    raw = JSON3.read(String(response.body))

    # Parse the column-oriented response format from Logfire API
    # Format: {"columns": [{"name": "col1", "values": [...]}, ...]}
    return _parse_query_response(raw, row_oriented)
end

"""
    _parse_query_response(raw, row_oriented) -> Vector{Dict} or Dict

Parse the Logfire API response format into user-friendly data structures.
"""
function _parse_query_response(raw, row_oriented::Bool)
    columns = raw[:columns]

    if isempty(columns)
        return row_oriented ? Vector{Dict{String, Any}}() : Dict{String, Vector}()
    end

    # Extract column names and values
    col_names = [String(col[:name]) for col in columns]
    col_values = [collect(col[:values]) for col in columns]

    if row_oriented
        # Convert to row-oriented: Vector of Dicts
        n_rows = length(col_values[1])
        rows = Vector{Dict{String, Any}}(undef, n_rows)
        for i in 1:n_rows
            row = Dict{String, Any}()
            for (j, name) in enumerate(col_names)
                row[name] = col_values[j][i]
            end
            rows[i] = row
        end
        return rows
    else
        # Column-oriented: Dict of column name => values
        result = Dict{String, Vector}()
        for (name, values) in zip(col_names, col_values)
            result[name] = values
        end
        return result
    end
end

"""
    query_csv(client, sql; kwargs...) -> String

Execute a SQL query and return CSV data as a string.

# Arguments
- `client::LogfireQueryClient`: Query client instance
- `sql::String`: SQL query to execute

# Keywords
- `min_timestamp::String`: ISO-8601 lower bound for filtering
- `max_timestamp::String`: ISO-8601 upper bound for filtering
- `limit::Int`: Maximum rows to return (default: 500, max: 10000)

# Returns
- `String`: CSV-formatted data

# Example
```julia
client = LogfireQueryClient()
csv_data = query_csv(client, "SELECT span_name, duration FROM records LIMIT 100")
println(csv_data)

# Or write to file
open("export.csv", "w") do f
    write(f, csv_data)
end
```
"""
function query_csv(client::LogfireQueryClient, sql::String;
        min_timestamp::Union{String, Nothing} = nothing,
        max_timestamp::Union{String, Nothing} = nothing,
        limit::Union{Int, Nothing} = nothing
)
    params = Dict{String, Any}("sql" => sql)

    if !isnothing(min_timestamp)
        params["min_timestamp"] = min_timestamp
    end
    if !isnothing(max_timestamp)
        params["max_timestamp"] = max_timestamp
    end
    if !isnothing(limit)
        params["limit"] = string(limit)
    end

    headers = [
        "Authorization" => "Bearer $(client.read_token)",
        "Accept" => "text/csv"
    ]

    response = HTTP.get(client.endpoint, headers; query = params)

    if response.status != 200
        error("Query failed with status $(response.status): $(String(response.body))")
    end

    return String(response.body)
end
