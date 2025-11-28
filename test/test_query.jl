using Test
using Logfire
using JSON3

@testset "Query API" begin
    @testset "LogfireQueryClient construction" begin
        # With explicit token
        client = LogfireQueryClient(read_token = "test-token")
        @test client.read_token == "test-token"
        @test client.endpoint == QUERY_ENDPOINT_US

        # With custom endpoint
        client_eu = LogfireQueryClient(read_token = "test-token", endpoint = QUERY_ENDPOINT_EU)
        @test client_eu.endpoint == QUERY_ENDPOINT_EU

        # Without token should error
        @test_throws ErrorException LogfireQueryClient(read_token = "")
    end

    @testset "Query endpoints" begin
        @test QUERY_ENDPOINT_US == "https://logfire-us.pydantic.dev/v1/query"
        @test QUERY_ENDPOINT_EU == "https://logfire-eu.pydantic.dev/v1/query"
    end

    @testset "_parse_query_response - row oriented" begin
        # Simulate API response format
        raw = JSON3.read("""
        {
            "columns": [
                {"name": "span_name", "values": ["span1", "span2", "span3"]},
                {"name": "duration", "values": [1.5, 2.3, 0.8]}
            ]
        }
        """)

        result = Logfire._parse_query_response(raw, true)

        @test result isa Vector
        @test length(result) == 3
        @test result[1]["span_name"] == "span1"
        @test result[1]["duration"] == 1.5
        @test result[2]["span_name"] == "span2"
        @test result[3]["duration"] == 0.8
    end

    @testset "_parse_query_response - column oriented" begin
        raw = JSON3.read("""
        {
            "columns": [
                {"name": "span_name", "values": ["span1", "span2"]},
                {"name": "duration", "values": [1.0, 2.0]}
            ]
        }
        """)

        result = Logfire._parse_query_response(raw, false)

        @test result isa Dict
        @test haskey(result, "span_name")
        @test haskey(result, "duration")
        @test result["span_name"] == ["span1", "span2"]
        @test result["duration"] == [1.0, 2.0]
    end

    @testset "_parse_query_response - empty" begin
        raw = JSON3.read("""{"columns": []}""")

        # Row oriented empty
        result_row = Logfire._parse_query_response(raw, true)
        @test result_row isa Vector
        @test isempty(result_row)

        # Column oriented empty
        result_col = Logfire._parse_query_response(raw, false)
        @test result_col isa Dict
        @test isempty(result_col)
    end

    @testset "_parse_query_response - single column" begin
        raw = JSON3.read("""
        {
            "columns": [
                {"name": "count", "values": [42]}
            ]
        }
        """)

        result = Logfire._parse_query_response(raw, true)
        @test length(result) == 1
        @test result[1]["count"] == 42
    end
end
