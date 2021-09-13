# LoggingFormats.jl

This package is an aggregation of various useful functions to use used in 
[FormatLogger](https://github.com/JuliaLogging/LoggingExtras.jl#formatlogger-sink) from package 
[LoggingExtras](https://github.com/JuliaLogging/LoggingExtras.jl).

Currently, there are following functions available:
- `make_log_truncated`

## Truncate long variables and messages

`make_log_truncated(max_var_len=5_000)` is a function which formats data in similar manner as `ConsoleLogger`, 
but with truncation of string representation when it exceeds `max_var_len`.

```julia
julia> using LoggingExtras, 

julia> with_logger(FormatLogger(make_log_truncated(30))) do
    short_var = "a"^5
    long_var = "a"^50
    @info "a short message" short_var long_var
    @info "a very long message"^20 short_var long_var
end
┌ Info: a short message
│   short_var = aaaaa
│   long_var = aaaaaaaaaaaa…
└ @ Main REPL[46]:4
┌ Info: a very long messagea very lon…
│   short_var = aaaaa
│   long_var = aaaaaaaaaaaa…
└ @ Main REPL[46]:5
```
