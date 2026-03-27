function has_parameters(expressions::Union{Vector, Tuple})
    length(expressions) > 0 && Meta.isexpr(expressions[1], :parameters)
end

function iskwarg(x, kwarg::Union{Symbol, Nothing} = nothing)
    x isa Expr && x.head == :kw && (kwarg === nothing || x.args[1] == kwarg)
end

"""
    expressions_to_args(@nospecialize(expressions); args_to_kwargs::Vector{Symbol} = [], defaults::AbstractDict{Symbol} = Dict())

Convert macro arguments (expressions) to arguments that can be passed to a function, including keyword arguments
    - kwargs are automatically converted
    - positional args can be converted to kwargs in a given order (`args_to_kwargs`)
    - default values for expected kwargs can be defined `defaults`

Example
```
f(args...; kwargs...) = [args, Dict(kwargs)]

macro f(expressions...)
    args = expressions_to_args(expressions)
    :(f(\$(args...))) |> esc
end

@f(1, [2, 3], a = 4, "567")
# 2-element Vector{Any}:
#  (1, [2, 3], "567")
#  Dict(:a => 4)
```
"""
function expressions_to_args(@nospecialize(expressions); args_to_kwargs::Vector{Symbol} = Symbol[], defaults::AbstractDict{Symbol} = Dict{Symbol, Any}())
    keys = Symbol[]
    inds = Int[]

    expressions isa Tuple && (expressions = Any[expressions...])

    # convert assignment expressions to keyword argument expressions
    # and collect the indices of positional arguments
    for (i, ex) in enumerate(expressions)
        if ex isa Expr && ex.head == :(=)
            ex.head = :kw
            push!(keys, ex.args[1])
        elseif !isa(ex, Expr) || ex.head != :parameters
            push!(inds, i)
        end
    end

    # loop through parameters after semicolon
    if has_parameters(expressions)
        for ex in expressions[1].args
            push!(keys, ex isa Symbol ? ex : ex.args[1])
        end
    end

    # collect positional args and convert them to kwargs according to the symbols in 'args_to_kwargs'
    # if they are not contained in the list of kwargs already and delete them from the list of positional args
    for (ind, kwarg) in zip(inds, args_to_kwargs)
        if kwarg ∉ keys
            push!(expressions, :($(Expr(:kw, kwarg, expressions[ind]))))
            push!(keys, kwarg)
        end
    end
    deleteat!(expressions, inds[1:min(length(args_to_kwargs), length(inds))])

    # apply default values for kwargs if there are any
    for kwarg in Base.keys(defaults)
        if kwarg ∉ keys
            push!(expressions, :($(Expr(:kw, kwarg, defaults[kwarg]))))
        end
    end

    return expressions
end

function locate_kwarg(expressions, kwarg::Symbol)
    ind = findfirst(x -> iskwarg(x, kwarg), expressions)
    parent = if ind === nothing
      # if not found look in the parameters, which reside at the first position of 'args'
      ind = findfirst(x -> x == kwarg || iskwarg(x, kwarg), expressions[1].args)
      expressions[1].args
    else
      expressions
    end
    expr = parent[ind] == kwarg ? kwarg : parent[ind].args[2]

    parent, ind, expr
end

function delete_kwarg!(expressions, kwarg::Symbol)
    parent, ind = locate_kwarg(expressions, kwarg)
    if parent === expressions || parent !== expressions && length(parent) > 1
        deleteat!(parent, ind)
    else
        deleteat!(expressions, 1)
    end

    return expressions
end

function delete_kwargs!(expressions, kwargs::Vector{Symbol})
    for kw in kwargs
        delete_kwarg!(expressions, kw)
    end
    return expressions
end

delete_kwarg(expressions, kwarg::Symbol) = delete_kwarg!(Any[copy(x) for x in expressions], kwarg)
delete_kwargs(expressions, kwarg::Vector{Symbol}) = delete_kwargs!(Any[copy(x) for x in expressions], kwarg)

using PrecompileTools

"""
    @stipple_precompile(setup, workload)

A macro that facilitates the precompilation process for Stipple-related code.

# Arguments
- `setup`: An optional setup configuration that is required for the precompilation.
- `workload`: The workload or tasks that need to be precompiled.

The macro defines three local routines: `precompile_get`, `precompile_post`, and `precompile_request`.
These routines can be used to send requests to the local server that is started during the
precompilation process.

The envrionment variable ENV["STIPPLE_PRECOMPILE_REQUESTS"] can be set to "false" to disable the
precompilation of HTTP.requests. The default value is "true".

# Example (see also end of Stipple.jl)
```
module MyApp
using Stipple, Stipple.ReactiveTools

@app PrecompileApp begin
    @in demo_i = 1
    @out demo_s = "Hi"

    @onchange demo_i begin
    println(demo_i)
    end
end

ui() = [cell("hello"), row("world"), htmldiv("Hello World")]

function __init__()
    @page("/", ui)
end

@stipple_precompile begin
    # the @page macro cannot be called here, as it reilies on writing some cache files to disk
    # hence, we use a manual route definition for precompilation

    route("/") do
        model = @init PrecompileApp
        page(model, ui) |> html
    end

    precompile_get("/")
end

end
```
"""
macro stipple_precompile(setup, workload)
    # wrap @app calls in @eval to avoid precompilation errors
    for (i, ex) in enumerate(workload.args)
        if ex isa Expr && ex.head == :macrocall && ex.args[1] == Symbol("@app")
            println("Found app declaration in precompilation section, wrapping in `@eval`!")
            workload.args[i] = Expr(:macrocall, Symbol("@eval"), ex.args)
        end
    end

    for (i, ex) in enumerate(setup.args)
        ex isa Expr && ex.head == :call && startswith("$(ex.args[1])", "precompile_") && continue
        if ex isa Expr && ex.head == :macrocall && ex.args[1] == Symbol("@app")
            setup.args[i] = :(@eval $(ex))#Expr(:macrocall, Symbol("@eval"), ex.args)
        end
        setup.args[i] = :(esc($ex))
    end

    quote
        Stipple.@setup_workload begin
            HTTP = Stipple.Genie.HTTPUtils.HTTP

            $setup

            Stipple.@compile_workload begin
                # all calls in this block will be precompiled, regardless of whether
                # they belong to your package or not (on Julia 1.8 and higher)
                # set secret in order to avoid automatic generation of a new one,
                # which would invalidate the precompiled file
                Stipple.Genie.Secrets.secret_token!(repeat("f", 64))

                port = tryparse(Int, get(ENV, "STIPPLE_PRECOMPILE_PORT", ""))
                port === nothing && (port = rand(8081:8999))
                precompile_requests = tryparse(Bool, get(ENV, "STIPPLE_PRECOMPILE_REQUESTS", "true"))
                # for compatibility with older versions
                precompile_requests |= tryparse(Bool, get(ENV, "STIPPLE_PRECOMPILE_GET", "true"))

                function precompile_request(method, location, args...; retry = false, kwargs...)
                    precompile_requests && HTTP.request(method, "http://localhost:$port/$(lstrip(location, '/'))", args...; retry, kwargs...)
                end

                precompile_get(location::String, args...; retry = false, kwargs...) = precompile_request(:GET, location, args...; retry, kwargs...)
                precompile_post(location::String, args...; retry = false, kwargs...) = precompile_request(:POST, location, args...; retry, kwargs...)

                Stipple.Logging.with_logger(Stipple.Logging.SimpleLogger(stdout, Stipple.Logging.Error)) do
                    Stipple.up(host = "127.0.0.1", port = port, wsport = port)

                    $workload

                    Stipple.down()
                end
                # reset secret back to empty string in case that the application sets the token during precompilation
                Stipple.Genie.Secrets.secret_token!("")
            end
        end
    end |> esc
end

macro stipple_precompile(workload)
    :(@stipple_precompile begin end begin
        $workload
    end) |> esc
end

"""
    striplines!(ex::Union{Expr, Vector})

Remove all line number nodes from an expression or vector of expressions. See also `striplines`.
"""
function striplines!(ex::Expr; recursive::Bool = false)
  for i in reverse(eachindex(ex.args))
    if isa(ex.args[i], LineNumberNode) && (ex.head != :macrocall || i > 1)
      deleteat!(ex.args, i)
    elseif isa(ex.args[i], Expr) && recursive
      striplines!(ex.args[i])
    end
  end
  ex
end

function striplines!(exprs::Vector; recursive::Bool = false)
  for i in reverse(eachindex(exprs))
    if isa(exprs[i], LineNumberNode)
      deleteat!(exprs, i)
    elseif isa(exprs[i], Expr) && recursive
      striplines!(exprs[i])
    end
  end
  exprs
end

"""
    striplines(ex::Union{Expr, Vector})

Return a copy of an expression with all line number nodes removed. See also `striplines!`.
"""
striplines(ex; recursive::Bool = false) = striplines!(copy(ex); recursive)


"""
    postwalk!(f::Function, expr::Expr)

Inplace version of MacroTools.postwalk()
"""
function postwalk!(f::Function, expr::Expr)
    ex = MacroTools.postwalk(f, expr)
    expr.head = ex.head
    expr.args = ex.args
end

"""
    debug(field::Reactive; listener::Int = 0)
    debug(field::Reactive, value; listener::Int = 0)
    
    debug(model::ReactiveModel, field::Symbol; listener::Int = 0)
    debug(model::ReactiveModel, field::Symbol, value; listener::Int = 0)

Execute a listener of a field in a `ReactiveModel` and return the result. The `index` argument can be used to select a specific listener.
The default index is the last listener. Negative indices are counted from the end of the list of listeners.

# Example
```julia
using Stipple, Stipple.ReactiveTools

@app TestApp begin
    @in x = 0
    @in y = 1

    @onchange x begin
        y = x + 1
        error("This is an error")
        println("x changed to \$x")
    end

    @onchange x, y begin
        println("x and y changed to \$x and \$y")
    end
end

model = @init TestApp
debug(model.x) # passes successfully
debug(model.x, 10; listener = -2) # returns an error including the location
```
"""
function debug(field::Reactive; listener::Int = 0)
  listeners = field.o.listeners
  index = listener == 0 ? length(listeners) : listener
  index < 0 && (index = length(listeners) + index + 1)
  index <= 0 && return "index '$index' not found in listeners, there are $(length(listeners)) listeners defined"
  listener = listeners[index][2]
  listener isa Observables.OnAny ? listener.f(listener.args...) : listener(field[])
end

function debug(field::Reactive, value; listener::Int = 0)
    # silent update then debug
    field[!] = value
    debug(field; listener)
end

debug(model::ReactiveModel, field::Symbol; listener::Int = 0) = debug(getfield(model, field); listener)
debug(model::ReactiveModel, field::Symbol, value; listener::Int = 0) = debug(getfield(model, field), value; listener)

# add method to get JS asset path for a ReactiveModel type
function Genie.Assets.asset_path(::Type{App}) where App <: ReactiveModel
    Genie.Assets.asset_path(Stipple.assets_config, :js; file = vm(App))
end

# utility function to get content from local server
function hget(target::AbstractString = "/";
    host::String = "http://localhost",
    port::Int = Genie.config.server_port
)
    startswith(host, "http") || (host = "http://$host")
    try Genie.HTTPUtils.HTTP.get("$host:$port/" * strip(target, '/'), retry = false).body |> String catch e; println("$e"[1:30]); nothing end
end

function get_channel_from_html(s::String; error::Bool = false)
    m = match(r"\(\) => window.create[^']+'([^']+)'", s)
    if m === nothing
        error && Base.error("No channel found in HTML, please specify one manually.")
        return nothing
    end
    String(m.captures[1])
end

function get_channel_from_html(::Nothing; error::Bool = false)
    default_channel = Genie.config.webchannels_default_route
    error && Base.error("No channel found in HTML, please specify one manually.")
    @warn "No channel found, using default channel '$default_channel'"
    default_channel
end

function _ws_client(messages = String[], payloads::Array{<:AbstractDict} = fill(Dict());
    verbose::Bool = true,
    host::String = "localhost",
    port::Int = Genie.config.server_port,
    target::String = "/",
    channel::String = get_channel_from_html(hget(target; host, port), error = true),
    async = false,
    timeout::Union{Period, Real} = 5,
    close_on_unsubscribe::Bool = true,
    close_on_error::Bool = true,
    maximum_async_duration::Union{Period, Real} = Hour(1)
)
    HTTP = Genie.HTTPUtils.HTTP
    channel == nothing && return nothing

    timeout isa Real || (timeout = Dates.toms(timeout) / 1000)
    pushfirst!(messages, "subscribe")
    # if not async then add unsubscribe message at the end
    async || push!(messages, "unsubscribe")
    if payloads isa Vector
        pushfirst!(payloads, Dict())
        push!(payloads, Dict())
    end

    websockets = Channel{HTTP.WebSocket}(1)
    ws_client = @async HTTP.WebSockets.open("ws://$host:$port") do ws
        put!(websockets, ws)
        messages = Dict.("channel" => channel, "message" .=> messages, "payload" .=> payloads)
        for msg in messages
            HTTP.WebSockets.send(ws, json(msg))
        end

        for msg in ws
            verbose && println("Received: $msg")
            if close_on_unsubscribe && msg == "Unsubscription: OK" || close_on_error && contains(msg, "ERROR")
                sleep(0.1)
                close(ws)
                break
            end
        end
    end
    
    if async
        ws = if timeout > 0
            @timeout timeout take!(websockets) nothing
        else
            take!(websockets)
        end::Union{Nothing, HTTP.WebSocket}
        ws === nothing && return nothing
        # make sure no idle tasks are left hanging around
        Genie.Util.isprecompiling || Timer(maximum_async_duration) do timer
            ws.writeclosed && return
            println("Maximum async duration reached, closing WebSocket connection.")
            close(ws)
        end
        Genie.WebChannels.ChannelClient(ws, String[channel])
    else
        if timeout > 0
            @timeout timeout wait(ws_client) nothing
        else
            wait(ws_client)
        end
        nothing
    end
end


"""
    ws_client_send(messages = String[], payloads::Array{<:AbstractDict} = fill(Dict());
    verbose::Bool = true,
    host::String = "localhost",
    port::Int = Genie.config.server_port,
    target::String = "/",
    channel = get_channel_from_html(hget(target; host, port), error = true),
    timeout::Union{Period, Real} = 5,
    close_on_unsubscribe::Bool = true,
    close_on_error::Bool = true,
)

Opens a WebSocket connection to the local Genie server
subscribes to a channel, sends a series of messages with optional payloads,
unsubscribes and then closes the connection.

There's also an async version `ws_client!` that returns the WebSocket connection
immediately after sending initial messages and waits for incoming messages.
"""
function ws_client_send(messages = String[], payloads::Array{<:AbstractDict} = fill(Dict());
    verbose::Bool = true,
    host::String = "localhost",
    port::Int = Genie.config.server_port,
    target::String = "/",
    channel = get_channel_from_html(hget(target; host, port), error = true),
    timeout::Union{Period, Real} = 5,
    close_on_unsubscribe::Bool = true,
    close_on_error::Bool = true,
)
    _ws_client(messages, payloads;
        async = false,
        verbose, host, port, channel, timeout,
        close_on_unsubscribe, close_on_error
    )
end

"""
    ws_client!(messages = String[], payloads::Array{<:AbstractDict} = fill(Dict());
    verbose::Bool = true,
    host::String = "localhost",
    port::Int = Genie.config.server_port,
    target::String = "/",
    channel = get_channel_from_html(hget(target; host, port), error = true),
    timeout::Union{Period, Real} = 5,
    close_on_unsubscribe::Bool = true,
    close_on_error::Bool = true,
    maximum_async_duration::Union{Period, Real} = Hour(1)
)

Opens a WebSocket connection to the local Genie server,
subscribes to a channel, sends a series of messages with optional payloads,
and keeps the connection open to receive incoming messages.
The WebSocket will be closed when an "unsubscribe" message is received
or when an error message is received (if `close_on_error` is true)

There's also a synchronous version `ws_client_send` that waits for all messages to be processed
before unsubscribing and closing the connection.
"""
function ws_client!(messages = String[], payloads::Array{<:AbstractDict} = fill(Dict());
    verbose::Bool = true,
    host::String = "localhost",
    port::Int = Genie.config.server_port,
    target::String = "/",
    channel = get_channel_from_html(hget(target; host, port), error = true),
    timeout::Union{Period, Real} = 5,
    close_on_unsubscribe::Bool = true,
    close_on_error::Bool = true,
    maximum_async_duration::Union{Period, Real} = Hour(1)
)
    _ws_client(messages, payloads;
        async = true,
        verbose, host, port, channel, timeout,
        close_on_unsubscribe, close_on_error, maximum_async_duration
    )
end

"""
    ws_client_send(client::Genie.WebChannels.ChannelClient, message::String, payload::Dict = Dict())

Send a message with optional payload to a WebSocket client connected to the local Genie server.

### Example

```julia
client = ws_client!()
ws_client_send(client, "unsubscribe")
"""
function ws_client_send(client::Genie.WebChannels.ChannelClient, message::String, payload::Dict = Dict())
    isempty(client.channels) && return false
    Genie.WebChannels.message_unsafe(client.client, json(Dict(:channel => client.channels[1], :message => message, :payload => payload)))
    return true
end