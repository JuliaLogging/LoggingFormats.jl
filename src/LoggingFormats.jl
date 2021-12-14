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

# Use key information, then lower to 2-arg transform
function transform(::Type{T}, key, v) where {T}
    key == :exception || return transform(T, v)
    if v isa Tuple && length(v) == 2
        e, bt = v
        msg = sprint(showerror, e, stacktrace(bt))
        return transform(T, (string(e), msg))
    end
    return transform(T, sprint(showerror, v))
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
        escape_string(io, sprint(print, something(v, "nothing")), '"')
        print(io, "\"")
    end
    println(io)
    return nothing
end

end # module
