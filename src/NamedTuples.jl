module NamedTuples

"""
    function Core.NamedTuple(kwargs::Dict{Symbol,T})::NamedTuple where {T}

Converts the `Dict` `kwargs` with keys of type `Symbol` to a `NamedTuple`.

### Example

```julia
julia> NamedTuple(Dict(:a => "a", :b => "b"))
(a = "a", b = "b")
```
"""
function Core.NamedTuple(kwargs::Dict{Symbol,T})::NamedTuple where {T}
  NamedTuple{Tuple(keys(kwargs))}(collect(values(kwargs)))
end

"""
    function Core.NamedTuple(kwargs::Dict{Symbol,T}, property::Symbol, value::String)::NamedTuple where {T}

Prepends `value` to `kwargs[property]` if defined or adds a new `kwargs[property] = value` and then converts the
resulting `kwargs` dict to a `NamedTuple`.

### Example

```julia
julia> NamedTuple(Dict(:a => "a", :b => "b"), :d, "h")
(a = "a", b = "b", d = "h")

julia> NamedTuple(Dict(:a => "a", :b => "b"), :a, "h")
(a = "h a", b = "b")
```
"""
function Core.NamedTuple(kwargs::Dict{Symbol,T}, property::Symbol, value::String)::NamedTuple where {T}
  value = "$value $(get!(kwargs, property, ""))" |> strip
  kwargs = delete!(kwargs, property)
  kwargs[property] = value

  NamedTuple(kwargs)
end

end