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