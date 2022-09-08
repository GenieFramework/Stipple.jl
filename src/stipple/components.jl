const COMPONENTS = Dict()

"""
    function register_components(model::Type{M}, keysvals::AbstractVector) where {M<:ReactiveModel}

Utility function for adding Vue components that need to be registered with the Vue.js app.
This is usually needed for registering components provided by Stipple plugins.

### Example

```julia
Stipple.register_components(HelloPie, StippleCharts.COMPONENTS)
```
"""
function register_components(model::Type{M}, keysvals::AbstractVector) where {M<:ReactiveModel}
  haskey(COMPONENTS, model) || (COMPONENTS[model] = Any[])
  push!(COMPONENTS[model], keysvals...)
end

function register_components(model::Type{M}, args...) where {M<:ReactiveModel}
  for a in args
    register_components(model, a)
  end
end

"""
    function components(m::Type{M})::String where {M<:ReactiveModel}
    function components(app::M)::String where {M<:ReactiveModel}

JSON representation of the Vue.js components registered for the `ReactiveModel` `M`.
"""
function components(m::Type{M})::String where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  replace(Dict(COMPONENTS[m]...) |> json, "\""=>"") |> string
end

function components(app::M)::String where {M<:ReactiveModel}
  components(M)
end