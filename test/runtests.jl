using Test: @test, @testset
using LoggingExtras, LoggingFormats

@testset "Truncating" begin
    trunc_fun = make_log_truncated(30)
    io = IOBuffer()
    truncating_logger = FormatLogger(trunc_fun, io)
    with_logger(truncating_logger) do
        @info "a"^50
    end
    str = String(take!(io))

    @test occursin("Info: aaaaaaaaaaaaaaaaaaaaaaaaaaaaa…", str)

    io = IOBuffer()
    truncating_logger = FormatLogger(trunc_fun, io)
    with_logger(truncating_logger) do
        long_var = "a"^50
        @info "a_message" long_var
    end
    str = String(take!(io))

    @test occursin("│   long_var = aaaaaaaaaaaa…", str)

    io = IOBuffer()
    truncating_logger = FormatLogger(trunc_fun, io)
    with_logger(truncating_logger) do
        long_var = "a"^50
        short_var = "a"
        @info "a_message" long_var short_var
    end
    str = String(take!(io))

    @test occursin("│   long_var = aaaaaaaaaaaa…", str)
    @test occursin("│   short_var = a", str)
end
