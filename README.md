# LoggingFormats.jl

This package is an aggregation of various useful format functions to use with the
[FormatLogger](https://github.com/JuliaLogging/LoggingExtras.jl#formatlogger-sink) from the
[LoggingExtras](https://github.com/JuliaLogging/LoggingExtras.jl) package.

Currently, the following functors are available:
- `JSON`, `RecursiveJSON`: output log events as JSON
- `LogFmt`: output log events formatted as [logfmt](https://brandur.org/logfmt)
- `Truncated`: truncation of log messages

## `JSON` and `RecursiveJSON`: Output log events as JSON

`LoggingFormats.JSON()` is a function which formats the log message and the log metadata as JSON.
Example:

```julia
julia> using LoggingFormats, LoggingExtras

julia> with_logger(FormatLogger(LoggingFormats.JSON(), stderr)) do
           @info "hello, world"
           @error "something is wrong"
       end
{"level":"info","msg":"hello, world","module":"Main","file":"REPL[10]","line":2,"group":"REPL[10]","id":"Main_6972c828","kwargs":{}}
{"level":"error","msg":"something is wrong","module":"Main","file":"REPL[10]","line":3,"group":"REPL[10]","id":"Main_2289c7f9","kwargs":{}}
```

One can also use `RecursiveJSON` to recursively serialize the `kwargs` as JSON:

```julia
julia> using LoggingFormats, LoggingExtras

julia> with_logger(FormatLogger(LoggingFormats.RecursiveJSON(), stderr)) do
                  @info "hello, world" key=Dict("hello" => true)
       end
{"level":"info","msg":"hello, world","module":"Main","file":"REPL[18]","line":2,"group":"REPL[18]","id":"Main_ffce16b5","kwargs":{"key":{"hello":true}}}
```

If it encounters something which does not have a defined `StructTypes.StructType` to use
for serializing to JSON, it will fallback to converting the objects to strings, like the
`JSON` log format does.

## `LogFmt`: Format log events as logfmt

`LoggingFormats.LogFmt()` is a function which formats the log message in the
[logfmt](https://brandur.org/logfmt) format. Example:

```julia
julia> using LoggingFormats, LoggingExtras

julia> with_logger(FormatLogger(LoggingFormats.LogFmt(), stderr)) do
           @info "hello, world"
           @error "something is wrong"
       end
level=info msg="hello, world" module=Main file="REPL[2]" line=2 group="REPL[2]" id=Main_6972c827
level=error msg="something is wrong" module=Main file="REPL[2]" line=3 group="REPL[2]" id=Main_2289c7f8
```

## `Truncated`: Truncate long variables and messages

`LoggingFormats.Truncated(max_var_len=5_000)` is a function which formats data in similar manner as `ConsoleLogger`,
but with truncation of string representation when it exceeds `max_var_len`.
This format truncates the length of message itself, and truncates string representation of 
individual variables, but does not truncate the size of whole printed text.

See the examples:

```julia
julia> using LoggingFormats, LoggingExtras

julia> with_logger(FormatLogger(LoggingFormats.Truncated(30))) do
    short_var = "a"^5
    long_var = "a"^50
    @info "a short message" short_var long_var
    @info "a very long message "^20 short_var long_var
end
┌ Info: a short message
│   short_var = aaaaa
│   long_var = aaaaaaaaaaaa…
└ @ Main REPL[46]:4
┌ Info: a very long message a very lo…
│   short_var = aaaaa
│   long_var = aaaaaaaaaaaa…
└ @ Main REPL[46]:5
```
