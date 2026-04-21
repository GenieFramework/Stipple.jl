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
function register_components(::Type{M}, keysvals::Union{AbstractVector, AbstractDict}; legacy::Bool = false) where {M<:ReactiveModel}
  AM = get_abstract_type(M)
  haskey(COMPONENTS, AM) || (COMPONENTS[AM] = LittleDict())
  for kv in keysvals
    (k, v) = if kv isa Pair
      kv
    elseif kv isa DataType && kv <: ReactiveModel
      js_name(kv), render_component(kv)
    else
      kv, kv
    end
    legacy && (v = "window.vueLegacy.components['$v']")
    delete!(COMPONENTS[AM], k)
    push!(COMPONENTS[AM], k => v)
  end
  COMPONENTS
end

function register_components(::Type{M}, args...; legacy::Bool = false) where M <: ReactiveModel
    register_components(M, collect(args); legacy)
end

register_global_components(args...; legacy::Bool = false) = register_components(ReactiveModel, args...; legacy)

"""
    function components(::Type{M})::String where {M<:ReactiveModel}
    function components(app::M)::String where {M<:ReactiveModel}

JSON representation of the Vue.js components registered for the `ReactiveModel` `M`.
"""
function components(::Type{M})::String where {M<:ReactiveModel}
  CM = get_abstract_type(M)
  haskey(COMPONENTS, CM) || return ""

  # change to LittleDict as the order of components can be essential
  json(LittleDict(k => JSONText(v) for (k, v) in COMPONENTS[CM]))[2:end - 1]
end

function components(app::M)::String where {M<:ReactiveModel}
  components(M)
end