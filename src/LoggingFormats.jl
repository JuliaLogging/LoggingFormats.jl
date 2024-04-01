module LoggingFormats

import Logging, JSON3, StructTypes

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

struct JSONLogMessage{T}
    level::String
    msg::String
    _module::Union{String,Nothing}
    file::Union{String,Nothing}
    line::Union{Int,Nothing}
    group::Union{String,Nothing}
    id::Union{String,Nothing}
    kwargs::Dict{String,T}
end

transform(::Type{String}, v) = string(v)
transform(::Type{Any}, v) = v

function maybe_stringify_exceptions(key, v)
    key == :exception || return v
    if v isa Tuple && length(v) == 2 && v[1] isa Exception
        e, bt = v
        msg = sprint(Base.display_error, e, bt)
        return msg
    end
    return sprint(showerror, v)
end

# Use key information, then lower to 2-arg transform
function transform(::Type{T}, key, v) where {T}
    v = maybe_stringify_exceptions(key, v)
    return transform(T, v)
end

function JSONLogMessage{T}(args) where {T}
    JSONLogMessage{T}(
        lvlstr(args.level),
        args.message isa AbstractString ? args.message : string(args.message),
        args._module === nothing ? nothing : string(args._module),
        args.file,
        args.line,
        args.group === nothing ? nothing : string(args.group),
        args.id === nothing ? nothing : string(args.id),
        Dict{String,T}(string(k) => transform(T, k, v) for (k, v) in args.kwargs)
    )
end
StructTypes.StructType(::Type{<:JSONLogMessage}) = StructTypes.OrderedStruct()
StructTypes.names(::Type{<:JSONLogMessage}) = ((:_module, :module), )

struct JSON <: Function
    recursive::Bool
end

JSON(; recursive=false) = JSON(recursive)

function (j::JSON)(io, args)
    if j.recursive
        logmsg = JSONLogMessage{Any}(args)
        try
            JSON3.write(io, logmsg)
        catch e
            fallback_msg = JSONLogMessage{String}(args)
            fallback_msg.kwargs["LoggingFormats.FormatError"] = sprint(showerror, e)
            JSON3.write(io, fallback_msg)
        end
    else
        logmsg = JSONLogMessage{String}(args)
        JSON3.write(io, logmsg)
    end
    println(io)
    return nothing
end

############
## logfmt ##
############
# See  https://brandur.org/logfmt

const STANDARD_KEYS = (:level, :msg, :module, :file, :line, :group, :id)

"""
    LogFmt(standard_keys=$STANDARD_KEYS)
    LogFmt(standard_keys...)

Creates a `logfmt` format logger. The log message includes each of the `standard_keys`, as well as any "custom" keys. For example,

```julia
julia> using LoggingFormats, LoggingExtras

julia> with_logger(FormatLogger(LoggingFormats.LogFmt((:level, :message, :file)), stderr)) do
           @info "hello, world" extra="bye"
           @error "something is wrong"
       end
level=info msg="hello, world" file="REPL[5]" extra="bye"
level=error msg="something is wrong" file="REPL[5]"
```

Note that the order of arguments to `LogFmt` is respected in the log printing.
"""
struct LogFmt <: Function
    standard_keys::NTuple{<:Any,Symbol}
    function LogFmt(keys::NTuple{N,Symbol}) where {N}
        extra = setdiff(keys, STANDARD_KEYS)

        if !isempty(extra)
            if length(extra) == 1
                extra = first(extra)
                plural = ""
            else
                extra = Tuple(extra)
                plural = "s"
            end
            throw(ArgumentError("Unsupported standard logging key$plural `$(repr(extra))` found. The only supported keys are: `$STANDARD_KEYS`."))
        end
        return new(keys)
    end
end
LogFmt() = LogFmt(STANDARD_KEYS)
LogFmt(keys::Symbol...) = LogFmt(keys)

function fmtval(k, v)
    k == :level && return lvlstr(v)
    return v isa AbstractString ? v : string(something(v, "nothing"))
end

function (l::LogFmt)(io, args)
    for (i, k) in enumerate(l.standard_keys)
        i == 1 || print(io, ' ')
        print(io, k, '=')
        k in (:level, :module) || print(io, '"')
        k_lookup = k === :module ? :_module : k === :msg ? :message : k
        escape_string(io, fmtval(k, getproperty(args, k_lookup)), '"')
        k in (:level, :module) || print(io, '"')
    end
    for (k, v) in args.kwargs
        print(io, " ", k, "=\"")
        v = maybe_stringify_exceptions(k, v)
        escape_string(io, sprint(print, something(v, "nothing")), '"')
        print(io, "\"")
    end
    println(io)
    return nothing
end

end # module
