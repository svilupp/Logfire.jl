using Test
using Logfire

@testset "Configuration" begin
    @testset "should_send_to_logfire" begin
        # Save original state
        original_token = Logfire.GLOBAL_CONFIG.token
        original_send = Logfire.GLOBAL_CONFIG.send_to_logfire

        try
            # Test :never
            Logfire.GLOBAL_CONFIG.send_to_logfire = :never
            Logfire.GLOBAL_CONFIG.token = "test-token"
            @test Logfire.should_send_to_logfire() == false

            # Test :always
            Logfire.GLOBAL_CONFIG.send_to_logfire = :always
            Logfire.GLOBAL_CONFIG.token = nothing
            @test Logfire.should_send_to_logfire() == true

            # Test :if_token_present with token
            Logfire.GLOBAL_CONFIG.send_to_logfire = :if_token_present
            Logfire.GLOBAL_CONFIG.token = "test-token"
            @test Logfire.should_send_to_logfire() == true

            # Test :if_token_present without token
            Logfire.GLOBAL_CONFIG.send_to_logfire = :if_token_present
            Logfire.GLOBAL_CONFIG.token = nothing
            @test Logfire.should_send_to_logfire() == false

            # Test :if_token_present with empty token
            Logfire.GLOBAL_CONFIG.send_to_logfire = :if_token_present
            Logfire.GLOBAL_CONFIG.token = ""
            @test Logfire.should_send_to_logfire() == false
        finally
            # Restore original state
            Logfire.GLOBAL_CONFIG.token = original_token
            Logfire.GLOBAL_CONFIG.send_to_logfire = original_send
        end
    end

    @testset "is_configured and get_config" begin
        cfg = get_config()
        @test cfg isa Logfire.LogfireConfig
        @test is_configured() isa Bool
    end

    @testset "LogfireConfig defaults" begin
        cfg = Logfire.LogfireConfig()
        @test cfg.service_name == "julia-app"
        @test cfg.environment == "development"
        @test cfg.send_to_logfire == :if_token_present
        @test cfg.endpoint == "https://logfire-us.pydantic.dev"
        @test cfg.console == false
        @test cfg.scrubbing == false
        @test cfg.auto_record_exceptions == true
        @test cfg._configured == false
    end
end
