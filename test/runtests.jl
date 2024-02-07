using Test: @test, @testset, @test_throws
using Logging: Logging, with_logger
using LoggingExtras: FormatLogger
using LoggingFormats: LoggingFormats, Truncated, JSON, LogFmt
import JSON3

function my_throwing_function()
    throw(ArgumentError("no"))
end

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

@testset "JSON" begin
    @test LoggingFormats.lvlstr(Logging.Error + 1) == "error"
    @test LoggingFormats.lvlstr(Logging.Error) == "error"
    @test LoggingFormats.lvlstr(Logging.Error - 1) == "warn"
    @test LoggingFormats.lvlstr(Logging.Warn + 1) == "warn"
    @test LoggingFormats.lvlstr(Logging.Warn) == "warn"
    @test LoggingFormats.lvlstr(Logging.Warn - 1) == "info"
    @test LoggingFormats.lvlstr(Logging.Info + 1) == "info"
    @test LoggingFormats.lvlstr(Logging.Info) == "info"
    @test LoggingFormats.lvlstr(Logging.Info - 1) == "debug"
    @test LoggingFormats.lvlstr(Logging.Debug + 1) == "debug"
    @test LoggingFormats.lvlstr(Logging.Debug) == "debug"

    io = IOBuffer()
    with_logger(FormatLogger(JSON(), io)) do
        @debug "debug msg"
        @info "info msg"
        @warn "warn msg"
        @error "error msg"
    end
    json = [JSON3.read(x) for x in eachline(seekstart(io))]
    @test json[1].level == "debug"
    @test json[1].msg == "debug msg"
    @test json[2].level == "info"
    @test json[2].msg == "info msg"
    @test json[3].level == "warn"
    @test json[3].msg == "warn msg"
    @test json[4].level == "error"
    @test json[4].msg == "error msg"
    for i in 1:4
        @test json[i].line isa Int
        @test json[i].module == "Main"
        @test isempty(json[i].kwargs)
    end

    io = IOBuffer()
    with_logger(FormatLogger(JSON(), io)) do
        y = (1, 2)
        @info "info msg" x = [1, 2, 3] y
    end
    json = JSON3.read(seekstart(io))
    @test json.level == "info"
    @test json.msg == "info msg"
    @test json.module == "Main"
    @test json.line isa Int
    @test json.kwargs.x == "[1, 2, 3]"
    @test json.kwargs.y == "(1, 2)"

    # `recursive=true`
    io = IOBuffer()
    with_logger(FormatLogger(JSON(; recursive=true), io)) do
        y = (1, 2)
        @info "info msg" x = [1, 2, 3] y = Dict("hi" => Dict("hi2" => [1,2]))
    end
    json = JSON3.read(seekstart(io))
    @test json.level == "info"
    @test json.msg == "info msg"
    @test json.module == "Main"
    @test json.line isa Int
    @test json.kwargs.x == [1, 2, 3]
    @test json.kwargs.y == Dict(:hi => Dict(:hi2 => [1,2]))

    # Fallback to strings
    io = IOBuffer()
    with_logger(FormatLogger(JSON(; recursive=true), io)) do
        y = (1, 2)
        @info "info msg" x = [1, 2, 3] y = Dict("hi" => NaN)
    end
    json = JSON3.read(seekstart(io))
    @test json.level == "info"
    @test json.msg == "info msg"
    @test json.module == "Main"
    @test json.line isa Int
    @test json.kwargs.x == "[1, 2, 3]"
    y = json.kwargs.y
    must_have = ("Dict", "\"hi\"", "=>", "NaN")
    @test all(h -> occursin(h, y), must_have) # avoid issues with printing changing with versions
    @test json.kwargs[Symbol("LoggingFormats.FormatError")] == "NaN not allowed to be written in JSON spec"

    # Test logging exceptions
    for recursive in (false, true)
        # no stacktrace
        io = IOBuffer()
        with_logger(FormatLogger(JSON(; recursive=recursive), io)) do
            try
                throw(ArgumentError("no"))
            catch e
                @error "Oh no" exception = e
            end
        end
        logs = JSON3.read(seekstart(io))
        @test logs["msg"] == "Oh no"
        @test logs["kwargs"]["exception"] == "ArgumentError: no"

        # stacktrace
        io = IOBuffer()
        with_logger(FormatLogger(JSON(; recursive=recursive), io)) do
            try
                throw(ArgumentError("no"))
            catch e
                @error "Oh no" exception = (e, catch_backtrace())
            end
        end
        logs = JSON3.read(seekstart(io))
        @test logs["msg"] == "Oh no"

        @test occursin("ArgumentError: no", logs["kwargs"]["exception"])
        # Make sure we get a stacktrace out:
        @test occursin(r"ArgumentError: no\nStacktrace:\s* \[1\]",
                    logs["kwargs"]["exception"])
    end
end

@testset "logfmt" begin
    io = IOBuffer()
    with_logger(FormatLogger(LogFmt(), io)) do
        @debug "debug msg"
        @info "info msg" _file="file with space.jl"
        @warn "msg with \"quotes\""
        @error "error msg with nothings" _module=nothing _file=nothing __line=nothing
        @error :notstring x = [1, 2, 3] y = "hello\" \"world"
        @error "hi" exception=ErrorException("bad")
    end
    strs = collect(eachline(seekstart(io)))
    @test occursin("level=debug msg=\"debug msg\" module=Main", strs[1])
    @test occursin("file=\"", strs[1])
    @test occursin("group=\"", strs[1])
    @test occursin("level=info msg=\"info msg\" module=Main", strs[2])
    @test occursin("file=\"file with space.jl\"", strs[2])
    @test occursin("group=\"file with space\"", strs[2])
    @test occursin("level=warn msg=\"msg with \\\"quotes\\\"\" module=Main", strs[3])
    @test occursin("file=\"", strs[3])
    @test occursin("group=\"", strs[3])
    @test occursin("level=error msg=\"error msg with nothings\" module=nothing", strs[4])
    @test occursin("file=\"nothing\"", strs[4])
    @test occursin("line=\"nothing\"", strs[4])
    @test occursin("level=error msg=\"notstring\" module=Main", strs[5])
    @test occursin("x=\"[1, 2, 3]\" y=\"hello\\\" \\\"world\"", strs[5])
    @test occursin("exception=\"bad\"", strs[6])

    # Now let's try exceptions with backtraces
    io = IOBuffer()
    with_logger(FormatLogger(LogFmt(), io)) do
        try
            my_throwing_function()
        catch e
            @error "Oh no" exception = (e, catch_backtrace())
        end
    end
    str = String(take!(io))
    @test occursin("level=error msg=\"Oh no\" module=Main", str)
    @test occursin("file=\"", str)
    @test occursin("group=\"", str)
    @test occursin("exception=\"ERROR: ArgumentError: no Stacktrace:", str)
    # no new lines (except at the end of the line)
    @test !occursin('\n', chomp(str))
    # no Ptr's showing up in the backtrace
    @test !occursin("Ptr", str)
    # Test we are getting at least some stacktrace, e.g., the function we called:
    @test occursin("my_throwing_function()", str)

    # Can test by converting to JSON with the node `logfmt` package:
    # first install it with `npm i -g logfmt`
    # Then:
    # in = Base.PipeEndpoint()
    # out = Base.PipeEndpoint()
    # p = run(pipeline(`logfmt`; stdin=in, stdout=out); wait=false)
    # write(in, str)
    # close(in)
    # wait(p)
    # output = JSON3.read(read(out))
end
