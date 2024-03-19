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
function register_components(model::Type{M}, keysvals::Union{AbstractVector, AbstractDict}; legacy::Bool = false) where {M<:ReactiveModel}
  haskey(COMPONENTS, model) || (COMPONENTS[model] = LittleDict())
  for kv in keysvals
    (k, v) = kv isa Pair ? kv : (kv, kv)
    legacy && (v = "window.vueLegacy.components['$v']")
    delete!(COMPONENTS[model], k)
    push!(COMPONENTS[model], k => v)
  end
  COMPONENTS
end

register_components(model::Type{<:ReactiveModel}, args...; legacy::Bool = false) = register_components(model, collect(args); legacy)

register_global_components(args...; legacy::Bool = false) = register_components(ReactiveModel, args...; legacy)

"""
    function components(m::Type{M})::String where {M<:ReactiveModel}
    function components(app::M)::String where {M<:ReactiveModel}

JSON representation of the Vue.js components registered for the `ReactiveModel` `M`.
"""
function components(m::Type{M})::String where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  # change to LittleDict as the order of components can be essential
  json(LittleDict(k => JSONText(v) for (k, v) in COMPONENTS[m]))[2:end - 1]
end

function components(app::M)::String where {M<:ReactiveModel}
  components(get_abstract_type(M))
end