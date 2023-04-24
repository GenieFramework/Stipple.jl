using JSON3

const RENDERING_MAPPINGS = Dict{String,String}()
mapping_keys() = collect(keys(RENDERING_MAPPINGS))

"""
    function rendering_mappings(mappings = Dict{String,String})

Registers additional `mappings` as Julia to Vue properties mappings  (eg `foobar` to `foo-bar`).
"""
function rendering_mappings(mappings = Dict{String,String})
  merge!(RENDERING_MAPPINGS, mappings)
end

"""
    function julia_to_vue(field, mapping_keys = mapping_keys())

Converts Julia names to Vue names (eg `foobar` to `foo-bar`).
"""
function julia_to_vue(field, mapping_keys = mapping_keys()) :: String
  if in(string(field), mapping_keys)
    parts = split(RENDERING_MAPPINGS[string(field)], "-")

    if length(parts) > 1
      extraparts = map((x) -> uppercasefirst(string(x)), parts[2:end])
      string(parts[1], join(extraparts))
    else
      parts |> string
    end
  else
    field |> string
  end
end

"""
    function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}

Renders the Julia `ReactiveModel` `app` as the corresponding Vue.js JavaScript code.
"""
function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    f = getfield(app, field)

    occursin(SETTINGS.private_pattern, String(field)) && continue
    f isa Reactive && f.r_mode == PRIVATE && continue

    result[julia_to_vue(field)] = Stipple.render(f, field)
  end

  # convert :data to () => ({   })
  data = JSON3.write(merge(result, client_data(app)))

  vue = Dict( #:el => JSONText("rootSelector"),
              :mixins => JSONText("[watcherMixin, reviveMixin]"),
              :data => JSONText("() => ($data)") )

  isempty(components(app)   |> strip)   || push!(vue, :components => components(app))
  isempty(js_computed(app)  |> strip)   || push!(vue, :computed   => JSONText("{ $(js_computed(app)) }"))
  isempty(js_watch(app)     |> strip)   || push!(vue, :watch      => JSONText("{ $(js_watch(app)) }"))
  isempty(js_created(app)   |> strip)   || push!(vue, :created    => JSONText("function(){ $(js_created(app)); }"))
  isempty(js_mounted(app)   |> strip)   || push!(vue, :mounted    => JSONText("function(){ $(js_mounted(app)); }"))
  methods = js_methods(app) |> strip
  push!(vue, :methods    => JSONText("{ $((isempty(methods) ? "" : methods*",")*js_methods_events()) }"))

  vue
end

"""
    function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}

Default rendering of value types. Specialize `Stipple.render` to define custom rendering for your types.
"""
function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  val
end

"""
    function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}

Default rendering of `Reactive` values. Specialize `Stipple.render` to define custom rendering for your type `T`.
"""
function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end