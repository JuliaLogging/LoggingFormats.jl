using Test: @test, @testset, @test_throws
using LoggingExtras, LoggingFormats

@testset "Truncating" begin
    @test LoggingFormats.shorten_str("αβγαβγ", 3) == "αβ…"
    @test LoggingFormats.shorten_str("αβγαβγ", 4) == "αβγ…"
    @test LoggingFormats.shorten_str("julia", 3) == "ju…"
    @test LoggingFormats.shorten_str("julia", 4) == "jul…"
    @test LoggingFormats.shorten_str("julia", 5) == "julia"

    @test_throws ErrorException Truncated(0)
    @test_throws ErrorException Truncated(-5)

    trunc_fun = Truncated(30)
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

    @test occursin("│   long_var = aaaaaaaaaaaaaa…", str)

    io = IOBuffer()
    truncating_logger = FormatLogger(trunc_fun, io)
    with_logger(truncating_logger) do
        long_var = "a"^50
        short_var = "a"
        @info "a_message" long_var short_var
    end
    str = String(take!(io))
    @test occursin("│   long_var = aaaaaaaaaaaaaa…", str)
    @test occursin("│   short_var = a", str)
end
