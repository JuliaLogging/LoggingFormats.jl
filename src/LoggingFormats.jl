module LoggingFormats

export Truncated

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

struct JSONLogMessage
    level::String
    msg::String
    _module::Union{String,Nothing}
    file::Union{String,Nothing}
    line::Union{Int,Nothing}
    group::Union{String,Nothing}
    id::Union{String,Nothing}
    kwargs::Dict{String,String}
end
function JSONLogMessage(args)
    JSONLogMessage(
        lvlstr(args.level),
        args.message isa AbstractString ? args.message : string(args.message),
        args._module === nothing ? nothing : string(args._module),
        args.file,
        args.line,
        args.group === nothing ? nothing : string(args.group),
        args.id === nothing ? nothing : string(args.id),
        Dict{String,String}(string(k) => string(v) for (k, v) in args.kwargs)
    )
end
StructTypes.StructType(::Type{JSONLogMessage}) = StructTypes.OrderedStruct()
StructTypes.names(::Type{JSONLogMessage}) = ((:_module, :module), )

struct JSON <: Function
end

function (::JSON)(io, args)
    logmsg = JSONLogMessage(args)
    JSON3.write(io, logmsg)
    println(io)
    return nothing
end

end # module
