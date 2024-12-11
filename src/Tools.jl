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
    quote
        @setup_workload begin
        # Putting some things in `setup` can reduce the size of the
        # precompile file and potentially make loading faster.
        using Genie.HTTPUtils.HTTP
        PRECOMPILE[] = true

        esc($setup)

        @compile_workload begin
            # all calls in this block will be precompiled, regardless of whether
            # they belong to your package or not (on Julia 1.8 and higher)
            # set secret in order to avoid automatic generation of a new one,
            # which would invalidate the precompiled file
            Genie.Secrets.secret_token!(repeat("f", 64))
            
            port = tryparse(Int, get(ENV, "STIPPLE_PRECOMPILE_PORT", ""))
            port === nothing && (port = rand(8081:8999))
            precompile_requests = tryparse(Bool, get(ENV, "STIPPLE_PRECOMPILE_REQUESTS", "true"))
            # for compatibility with older versions
            precompile_requests |= tryparse(Bool, get(ENV, "STIPPLE_PRECOMPILE_GET", "true"))

            function precompile_request(method, location, args...; kwargs...)
                precompile_requests && HTTP.request(method, "http://localhost:$port/$(lstrip(location, '/'))", args...; kwargs...)
            end

            precompile_get(location::String, args...; kwargs...) = precompile_request(:GET, location, args...; kwargs...)
            precompile_post(location::String, args...; kwargs...) = precompile_request(:POST, location, args...; kwargs...)
            
            Logging.with_logger(Logging.SimpleLogger(stdout, Logging.Error)) do
                up(port)
                
                esc($workload)

                down()
            end
            # reset secret back to empty string
            Genie.Secrets.secret_token!("")
        end
        PRECOMPILE[] = false
        end
    end
end

macro stipple_precompile(workload)
    # wrap @app calls in @eval to avoid precompilation errors
    for (i, ex) in enumerate(workload.args)
        if ex isa Expr && ex.head == :macrocall && ex.args[1] == Symbol("@app")
            workload.args[i] = :(@eval $(ex))#Expr(:macrocall, Symbol("@eval"), ex.args)
        end
    end
    quote
        @stipple_precompile begin end begin
            $workload
        end
    end
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