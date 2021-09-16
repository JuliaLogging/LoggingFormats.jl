# LoggingFormats.jl

This package is an aggregation of various useful format functions to use with the
[FormatLogger](https://github.com/JuliaLogging/LoggingExtras.jl#formatlogger-sink) from the
[LoggingExtras](https://github.com/JuliaLogging/LoggingExtras.jl) package.

Currently, the following functors are available:
- `Truncated`

## `Truncated`: Truncate long variables and messages

`Truncated(max_var_len=5_000)` is a function which formats data in similar manner as `ConsoleLogger`, 
but with truncation of string representation when it exceeds `max_var_len`.
This format truncates the length of message itself, and truncates string representation of 
individual variables, but does not truncate the size of whole printed text.

See the examples:

```julia
julia> using LoggingExtras, LoggingFormat

julia> with_logger(FormatLogger(Truncated(30))) do
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
