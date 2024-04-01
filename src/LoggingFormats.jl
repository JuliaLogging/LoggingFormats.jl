module LoggingFormats

import Logging, JSON3

const STANDARD_KEYS = (:level, :msg, :module, :file, :line, :group, :id)

###############
## Truncated ##
###############

shorten_str(str, max_len) = shorten_str(string(str), max_len)
function shorten_str(str::String, max_len)
    if textwidth(str) <= max_len
        return SubString(str)
    end
    len = textwidth('…')
    ind = 1
    for i in eachindex(str)
        c = @inbounds str[i]
        len += textwidth(c)
        len > max_len && break
        ind = i
    end
    return SubString(str, 1, ind) * '…'
end

struct Truncated <: Function
    max_var_len::Int
    Truncated(max_var_len) = max_var_len <= 0 ? error("max_var_len must be positive") : new(max_var_len)
end
Truncated() = Truncated(5_000)

# copied from https://github.com/JuliaLang/julia/blob/v1.5.4/stdlib/Logging/src/ConsoleLogger.jl and modified
function (tr::Truncated)(io, args)
    levelstr = args.level == Logging.Warn ? "Warning" : string(args.level)
    msglines = split(chomp(shorten_str(args.message, tr.max_var_len)), '\n')
    println(io, "┌ ", levelstr, ": ", msglines[1])
    for i in 2:length(msglines)
        str_line = sprint(print, "│ ", msglines[i])
        println(io, shorten_str(str_line, tr.max_var_len))
    end
    for (key, val) in args.kwargs
        str_line = sprint(print, "│   ", key, " = ", val)
        println(io, shorten_str(str_line, tr.max_var_len))
    end
    println(io, "└ @ ", something(args._module, "nothing"), " ",
            something(args.file, "nothing"), ":", something(args.line, "nothing"))
    nothing
end


##########
## JSON ##
##########

lvlstr(lvl::Logging.LogLevel) = lvl >= Logging.Error ? "error" :
                                lvl >= Logging.Warn  ? "warn"  :
                                lvl >= Logging.Info  ? "info"  :
                                                       "debug"


transform(::Type{String}, v) = string(v)
transform(::Type{Any}, v) = v

maybe_stringify_exceptions((e, bt)::Tuple{Exception,Any}) = sprint(Base.display_error, e, bt)
maybe_stringify_exceptions(e::Exception) = sprint(showerror, e)
maybe_stringify_exceptions(v) = v

unclash_key(k) = k in STANDARD_KEYS ? Symbol("_", k) : k

function to_namedtuple(::Type{T}, args; nest_kwargs) where {T}
    kw = (k => transform(T, maybe_stringify_exceptions(v)) for (k, v) in args.kwargs)
    if nest_kwargs
        kw = (:kwargs => Dict{String, T}(string(k) => transform(T, maybe_stringify_exceptions(v)) for (k, v) in args.kwargs),)
    else
        kw = (unclash_key(k) => transform(T, maybe_stringify_exceptions(v)) for (k, v) in args.kwargs)
    end
    return (;
        level=lvlstr(args.level),
        msg=args.message isa AbstractString ? args.message : string(args.message),
        :module => args._module === nothing ? nothing : string(args._module),
        file=args.file,
        line=args.line,
        group=args.group === nothing ? nothing : string(args.group),
        id=args.id === nothing ? nothing : string(args.id),
        kw...
    )
end

"""
    JSON(; recursive=false, nest_kwargs=true)

Creates a `JSON` format logger. If `recursive=true`, any custom arguments will be recursively serialized as JSON; otherwise, the values will be treated as strings. If `nest_kwargs` is true (the default),  all custom keyword arguments will be under the `kwargs` key. Otherwise, they will be inlined into the top-level JSON object. In the latter case, if the key name clashes with one of the standard keys (`$STANDARD_KEYS`), it will be renamed by prefixing it with a `_`.

## Examples

```julia
julia> using LoggingFormats, LoggingExtras

julia> with_logger(FormatLogger(LoggingFormats.JSON(; recursive=false), stderr)) do
    @info "hello, world" key=Dict("hello" => true)
end
{"level":"info","msg":"hello, world","module":"Main","file":"REPL[3]","line":2,"group":"REPL[3]","id":"Main_ffce16b4","kwargs":{"key":"Dict{String, Bool}(\"hello\" => 1)"}}

julia> with_logger(FormatLogger(LoggingFormats.JSON(; recursive=true), stderr)) do
           @info "hello, world" key=Dict("hello" => true)
end
{"level":"info","msg":"hello, world","module":"Main","file":"REPL[4]","line":2,"group":"REPL[4]","id":"Main_ffce16b5","kwargs":{"key":{"hello":true}}}

julia> with_logger(FormatLogger(LoggingFormats.JSON(; recursive=true, nest_kwargs=false), stderr)) do
    @info "hello, world" key=Dict("hello" => true)
end
{"level":"info","msg":"hello, world","module":"Main","file":"REPL[5]","line":2,"group":"REPL[5]","id":"Main_ffce16b6","key":{"hello":true}}
```
"""
struct JSON <: Function
    recursive::Bool
    nest_kwargs::Bool
end

JSON(; recursive=false, nest_kwargs=true) = JSON(recursive, nest_kwargs)

function (j::JSON)(io, args)
    if j.recursive
        logmsg = to_namedtuple(Any, args; nest_kwargs=j.nest_kwargs)
        try
            JSON3.write(io, logmsg)
        catch e
            if j.nest_kwargs
                fallback_msg = to_namedtuple(String, args; nest_kwargs=true)
                fallback_msg.kwargs["LoggingFormats.FormatError"] = sprint(showerror, e)
            else
                fallback_msg = (; to_namedtuple(String, args; nest_kwargs=false)..., Symbol("LoggingFormats.FormatError") => sprint(showerror, e))
            end
            JSON3.write(io, fallback_msg)
        end
    else
        logmsg = to_namedtuple(String, args; nest_kwargs=j.nest_kwargs)
        JSON3.write(io, logmsg)
    end
    println(io)
    return nothing
end

############
## logfmt ##
############
# See  https://brandur.org/logfmt

struct LogFmt <: Function
end
function (::LogFmt)(io, args)
    print(io, "level=", lvlstr(args.level),
              " msg=\"",
    )
    escape_string(io, args.message isa AbstractString ? args.message : string(args.message), '"')
    print(io, "\"",
              " module=", something(args._module, "nothing"),
              " file=\"",
    )
    escape_string(io, args.file isa AbstractString ? args.file : string(something(args.file, "nothing")), '"')
    print(io, "\"",
              " line=", something(args.line, "nothing"),
              " group=\"",
    )
    escape_string(io, args.group isa AbstractString ? args.group : string(something(args.group, "nothing")), '"')
    print(io, "\"",
              " id=", something(args.id, "nothing"),
    )
    for (k, v) in args.kwargs
        print(io, " ", k, "=\"")
        v = maybe_stringify_exceptions(v)
        escape_string(io, sprint(print, something(v, "nothing")), '"')
        print(io, "\"")
    end
    println(io)
    return nothing
end

end # module
