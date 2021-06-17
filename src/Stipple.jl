"""
# Stipple

Stipple is a reactive UI library for Julia. It provides a rich API for building rich web UIs with 2-way bindings between
HTML UI elements and Julia. It requires minimum configuration, automatically setting up the WebSockets/Ajax communication
channels and automatically keeping the data in sync.

Stipple allows creating powerful reactive web data dashboards using only Julia coding. It employs a declarative
programming model, the framework taking care of the full data sync workflow.

Stipple uses Vue.js on the frontend and focuses mostly on the low level communication API, allowing data binding to HTML
elements, forms, etc. The core functionality is meant to be extended with specialized plugins, for example for powerful
UIs or plotting features. The plugins are easy to build, requiring a minimum Julia implementation that usually ties into
existing Vue.js libraries.
"""
module Stipple

using Logging, Reexport, Requires

@reexport using Observables
@reexport using Genie
@reexport using Genie.Renderer.Html
import Genie.Renderer.Json.JSONParser: JSONText, json
export JSONText

import Genie.Configuration: isprod, PROD, DEV

mutable struct Reactive{T} <: Observables.AbstractObservable{T}
  o::Observables.Observable{T}
  r_mode::Int
  no_backend_watcher::Bool
  no_frontend_watcher::Bool
  Reactive{T}() where {T} = new{T}(Observable{T}(), 0, false, false)
  Reactive{T}(o, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, 0, no_bw, no_fw)
  Reactive{T}(o, mode::Int, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, mode, no_bw, no_fw)
  Reactive{T}(o, mode::Int, updatemode::Int) where {T} = new{T}(o, mode, updatemode & NO_BACKEND_WATCHER != 0, updatemode & NO_FRONTEND_WATCHER != 0)

  # Construct an Reactive{Any} without runtime dispatch
  Reactive{Any}(@nospecialize(o)) = new{Any}(Observable{Any}(o), 0, false, false)
end

Reactive(r::T, arg1, args...) where T = convert(Reactive{T}, (r, arg1, args...))
Reactive(r::T) where T = convert(Reactive{T}, r)

Base.convert(::Type{T}, x::T) where {T<:Reactive} = x  # resolves ambiguity with convert(::Type{T}, x::T) in base/essentials.jl
Base.convert(::Type{T}, x) where {T<:Reactive} = T(x)

Base.convert(::Type{Reactive{T}}, (r, m)::Tuple{T, Int}) where T = m < 16 ? Reactive{T}(Observable(r), m, 0) : Reactive{T}(Observable(r), 0, m)
Base.convert(::Type{Reactive{T}}, (r, w)::Tuple{T, Bool}) where T = Reactive{T}(Observable(r), 0, w, false)
Base.convert(::Type{Reactive{T}}, (r, m, nw)::Tuple{T, Int, Bool}) where T = Reactive{T}(Observable(r), m, nw, false)
Base.convert(::Type{Reactive{T}}, (r, nbw, nfw)::Tuple{T, Bool, Bool}) where T = Reactive{T}(Observable(r), 0, nbw, nfw)
Base.convert(::Type{Reactive{T}}, (r, m, nbw, nfw)::Tuple{T, Int, Bool, Bool}) where T = Reactive{T}(Observable(r), m, nbw, nfw)
Base.convert(::Type{Reactive{T}}, (r, m, u)::Tuple{T, Int, Int}) where T = Reactive{T}(Observable(r), m, u)
Base.convert(::Type{Observable{T}}, r::Reactive{T}) where T = getfield(r, :o)

Base.getindex(r::Reactive{T}) where T = Base.getindex(getfield(r, :o))
Base.setindex!(r::Reactive{T}) where T = Base.setindex!(getfield(r, :o))

# pass indexing and property methods to referenced variable
function Base.getindex(r::Reactive{T}, arg1, args...) where T
  getindex(getfield(r, :o).val, arg1, args...)
end

function Base.setindex!(r::Reactive{T}, val, arg1, args...) where T
  setindex!(getfield(r, :o).val, val, arg1, args...)
  Observables.notify!(r)
end

Base.setindex!(r::Reactive, val, ::typeof(!)) = getfield(r, :o).val = val
Base.getindex(r::Reactive, ::typeof(!)) = getfield(r, :o).val

function Base.getproperty(r::Reactive{T}, field::Symbol) where T
  if field in (:o, :r_mode, :no_backend_watcher, :no_frontend_watcher) # fieldnames(Reactive)
    getfield(r, field)
  else
    if field == :val
      @warn """Reactive API has changed, use "[]" instead of ".val"!"""
      getfield(r, :o).val
    else
      getproperty(getfield(r, :o).val, field)
    end
  end
end

function Base.setproperty!(r::Reactive{T}, field::Symbol, val) where T
  if field in fieldnames(Reactive)
    setfield!(r, field, val)
  else
    if field == :val
      @warn """Reactive API has changed, use "setfield_withoutwatchers!() or o.val" instead of ".val"!"""
      getfield(r, :o).val = val
    else
      setproperty!(getfield(r, :o).val, field, val)
      Observables.notify!(r)
    end
  end
end

Observables.observe(r::Reactive{T}, args...; kwargs...) where T = Observables.observe(getfield(r, :o), args...; kwargs...)
Observables.listeners(r::Reactive{T}, args...; kwargs...) where T = Observables.listeners(getfield(r, :o), args...; kwargs...)

@static if isdefined(Observables, :appendinputs!)
    Observables.appendinputs!(r::Reactive{T}, obsfuncs) where T = Observables.appendinputs!(getfield(r, :o), obsfuncs)
end

# workaround for `map!()`, as long as Observables.MapUpdater is not patched to handle AbstractObservables (probably Observables <= v0.4.0)
import Base.map!
@inline Base.map!(f::F, r::Reactive, os...; update::Bool=true) where F = Base.map!(f::F, getfield(r, :o), os...; update=update)

const R = Reactive
const PUBLIC = 1
const PRIVATE = 2
const READONLY = 4
const JSFUNCTION = 8
const NO_BACKEND_WATCHER = 16
const NO_FRONTEND_WATCHER = 32
const NO_WATCHER = 48


OptDict = Dict{Symbol, Any}
opts(;kwargs...) = OptDict(kwargs...)


WEB_TRANSPORT = Genie.WebChannels

export R, Reactive, ReactiveModel, @R_str, @js_str, client_data
export PRIVATE, PUBLIC, READONLY, JSFUNCTION, NO_WATCHER, NO_BACKEND_WATCHER, NO_FRONTEND_WATCHER
export newapp
export onbutton
export @kwredef

#===#

function __init__()
  Genie.config.websockets_server = true
  @require OffsetArrays  = "6fe1bfb0-de20-5000-8ca7-80f57d26f881" function convertvalue(targetfield::Union{Ref{T}, Reactive{T}}, value) where T <: OffsetArrays.OffsetArray
    valtype = eltype(targetfield)
    a = if value isa AbstractArray
      convert(Array{eltype(valtype)}, value)
    else
      eltype(valtype)[value]
    end
    if ! isa(value, OffsetArrays.OffsetArray)
      o = targetfield[].offsets
      OffsetArrays.OffsetArray(a, OffsetArrays.Origin(1 .+ o))
    else
      value
    end
  end
end

#===#

"""
    `type ReactiveModel`

The abstract type that is inherited by Stipple models. Stipple models are used for automatic 2-way data sync and data
exchange between the Julia backend and the JavaScript/Vue.js frontend.

### Example

```julia
Base.@kwdef mutable struct HelloPie <: ReactiveModel
  plot_options::R{PlotOptions} = PlotOptions(chart_type=:pie, chart_width=380, chart_animations_enabled=true,
                                            stroke_show = false, labels=["Slice A", "Slice B"])
  piechart::R{Vector{Int}} = [44, 55]
  values::R{String} = join(piechart, ",")
end
```
"""
abstract type ReactiveModel end
mutable struct Settings
  readonly_pattern
  private_pattern
end
Settings(; readonly_pattern = r"_$", private_pattern = r"__$") = Settings(readonly_pattern, private_pattern)

#===#

"""
    `const JS_SCRIPT_NAME`

The name of the dynamically generated JavaScript file used for data sync.
"""
const JS_SCRIPT_NAME = "stipple.js"

"""
    `const JS_DEBOUNCE_TIME`

Debounce time used to indicate the minimum frequency for sending data payloads to the backend (for example to batch send
payloads when the user types into an text field, to avoid overloading the server).
"""
const JS_DEBOUNCE_TIME = 300 #ms
const SETTINGS = Settings()

#===#

"""
    `function render`

Abstract function. Needs to be specialized by plugins. It is automatically invoked by `Stipple` to serialize a Julia
data type (corresponding to the fields in the `ReactiveModel` instance) to JavaScript/JSON. In general the specialized
methods should return a Julia `Dict` which are automatically JSON encoded by `Stipple`. If custom JSON serialization is
required for certain types in the resulting `Dict`, specialize `Genie.Renderer.Json.JSON.lower` for that specific type.

### Example

```julia
function Stipple.render(ps::PlotSeries, fieldname::Union{Symbol,Nothing} = nothing)
  Dict(:name => ps.name, ps.plotdata.key => ps.plotdata.data)
end
```

#### Specialized JSON rendering for `Undefined`

```julia
Genie.Renderer.Json.JSON.lower(x::Undefined) = "__undefined__"
```
"""
function render end

"""
    `function update! :: {M<:ReactiveModel}`

Abstract function used to update the values of the fields in the `ReactiveModel` based on the data from the frontend.
Can be specialized for dedicated types, but it is usually not necessary. If specialized, it must return the update
instance of `ReactiveModel` provided as the first parameter.

### Example

```julia
function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  setfield!(model, field, newval)

  model
end
````
"""
function update! end

"""
    `function watch`

Abstract function. Can be used by plugins to define custom Vue.js watch functions.
"""
function watch end

"""
    `function js_methods(app::T) where {T<:ReactiveModel}`

Defines js functions for the `methods` section of the vue element.

### Example

```julia
js_methods(app::MyDashboard) = \"\"\"
  mysquare: function (x) {
    return x^2
  }
  myadd: function (x, y) {
    return x + y
  }
\"\"\"
```
"""
function js_methods(app::T)::String where {T<:ReactiveModel}
  ""
end

"""
    `function js_computed(app::T) where {T<:ReactiveModel}`

Defines js functions for the `computed` section of the vue element.
These properties are updated every time on of the inner parameters changes its value.

### Example

```julia
js_computed(app::MyDashboard) = \"\"\"
  fullName: function () {
    return this.firstName + ' ' + this.lastName
  }
\"\"\"
```
"""
function js_computed(app::T)::String where {T<:ReactiveModel}
  ""
end

"""
    `function js_watch(app::T) where {T<:ReactiveModel}`

Defines js functions for the `watch` section of the vue element.
These functions are called every time the respective property changes.

### Example

Updates the `fullName` every time `firstName` or `lastName` changes.

```julia
js_watch(app::MyDashboard) = \"\"\"
  firstName: function (val) {
    this.fullName = val + ' ' + this.lastName
  },
  lastName: function (val) {
    this.fullName = this.firstName + ' ' + val
  }
\"\"\"
```
"""
function js_watch(m::T)::String where {T<:ReactiveModel}
  ""
end

"""
    `function js_created(app::T)::String where {T<:ReactiveModel}`

Defines js statements for the `created` section of the vue element.
They are executed directly after the creation of the vue element.

### Example

```julia
js_created(app::MyDashboard) = \"\"\"
    if (this.cameraon) { startcamera() }
\"\"\"
```
"""
function js_created(app::T)::String where {T<:ReactiveModel}
  ""
end

"""
    `function js_mounted(app::T)::String where {T<:ReactiveModel}`

Defines js statements for the `mounted` section of the vue element.
They are executed directly after the mounting of the vue element.

### Example

```julia
js_created(app::MyDashboard) = \"\"\"
    if (this.cameraon) { startcamera() }
\"\"\"
```
"""
function js_mounted(app::T)::String where {T<:ReactiveModel}
  ""
end

"""
    `function client_data(app::T)::String where {T<:ReactiveModel}`

Defines additional data that will only be visible by the browser.

It is meant to keep volatile data, e.g. form data that needs to pass a validation first.
In order to use the data you most probably also want to define [`js_methods`](@ref)
### Example

```julia
import Stipple.client_data
client_data(m::Example) = client_data(client_name = js"null", client_age = js"null", accept = false)
```
will define the additional fields `client_name`, `clientage` and `accept` for the model `Example`. These should, of course, not overlap with existing fields of your model.
"""
client_data(app::T) where T <: ReactiveModel = Dict{String, Any}()

client_data(;kwargs...) = Dict{String, Any}([String(k) => v for (k, v) in kwargs]...)

#===#

const COMPONENTS = Dict()

"""
    `function register_components(model::Type{M}, keysvals::AbstractVector) where {M<:ReactiveModel}`

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

"""
    `function components(m::Type{M})::String where {M<:ReactiveModel}`
    `function components(app::M)::String where {M<:ReactiveModel}`

JSON representation of the Vue.js components registered for the `ReactiveModel` `M`.
"""
function components(m::Type{M})::String where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  replace(Dict(COMPONENTS[m]...) |> Genie.Renderer.Json.JSONParser.json, "\""=>"") |> string
end

function components(app::M)::String where {M<:ReactiveModel}
  components(M)
end

#===#

"""
    `setindex_withoutwatchers!(field::Reactive, val; notify=(x)->true)`
    `setindex_withoutwatchers!(field::Reactive, val, keys::Int...; notify=(x)->true)`

Change the content of a Reactive field without triggering the listeners.
If keys are specified, only these listeners are exempted from triggering.
"""
function setindex_withoutwatchers!(field::Reactive, val, keys::Int...; notify=(x)->true)
  count = 1
  field.o.val = val
  length(keys) == 0 && return field

  for f in Observables.listeners(field.o)
    if in(count, keys)
      count += 1
      continue
    end

    if notify(f)
      Base.invokelatest(f, val)
    end

    count += 1
  end

  return field
end

"""
    `setfield_withoutwatchers!(app::ReactiveModel, field::Symmbol, val; notify=(x)->true)``
    `setfield_withoutwatchers!(app::ReactiveModel, field::Symmbol, val, keys...; notify=(x)->true)`

Change the field of a ReactiveModel without triggering the listeners.
If keys are specified, only these listeners are exempted from triggering.
"""
function setfield_withoutwatchers!(app::T, field::Symbol, val, keys...; notify=(x)->true) where T <: ReactiveModel
  f = getfield(app, field)
  if f isa Reactive
    setindex_withoutwatchers!(f, val, keys...; notify = notify)
  else
    setfield!(app, field, val)
  end
  return app
end

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")

@reexport using .Typography
@reexport using .Elements
@reexport using .Layout

#===#

function convertvalue(targetfield::Any, value)
  valtype = eltype(targetfield)
  try
    if valtype <: AbstractFloat && typeof(value) <: Integer
      convert(valtype, value)
    elseif valtype <: AbstractArray
      a = if value isa AbstractArray
        convert(Array{eltype(valtype)}, value)
      else
        eltype(valtype)[value]
      end
    else
      Base.parse(valtype, value)
    end
  catch ex
    # @error ex
    value
  end
end

"""
    `function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}`
    `function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}`
    `function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}`

Sets the value of `model.field` from `oldval` to `newval`. Returns the upated `model` instance.
"""
function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  f = getfield(model, field)
  if f isa Reactive
    f.r_mode == PRIVATE ? f[] = newval : setindex_withoutwatchers!(f, newval, 1)
  else
    setfield!(model, field, newval)
  end
  model
end

function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  field.r_mode == PRIVATE || field.no_backend_watcher ? field[] = newval : setindex_withoutwatchers!(field, newval, 1)

  model
end

function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  setfield!(model, field, newval)

  model
end

#===#

"""
    `function watch(vue_app_name::String, fieldtype::Any, fieldname::Symbol, channel::String, debounce::Int, model::M)::String where {M<:ReactiveModel}`

Sets up default Vue.js watchers so that when the value `fieldname` of type `fieldtype` in model `vue_app_name` is
changed on the frontend, it is pushed over to the backend using `channel`, at a `debounce` minimum time interval.
"""
function watch(vue_app_name::String, fieldname::Symbol, channel::String, debounce::Int, model::M)::String where {M<:ReactiveModel}
  js_channel = channel == "" ? "window.Genie.Settings.webchannels_default_route" : "'$channel'"

  output = """
    $vue_app_name.\$watch(function(){return this.$fieldname}, _.debounce(function(newVal, oldVal){
      Genie.WebChannels.sendMessageTo($js_channel, 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal}});
    }, $debounce));
  """
  # in production mode vue does not fill `this.expression` in the watcher, so we do it manually
  if Genie.Configuration.isprod()
    output *= "$vue_app_name._watchers[$vue_app_name._watchers.length - 1].expression = 'function(){return this.$fieldname}'"
  end

  output *= "\n\n"
end

#===#

function Base.parse(::Type{T}, v::T) where {T}
  v::T
end

"""
    `function init(model::M, ui::Union{String,Vector} = ""; vue_app_name::String = Stipple.Elements.root(model),
                    endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route,
                    debounce::Int = JS_DEBOUNCE_TIME, transport::Module = Genie.WebChannels)::M where {M<:ReactiveModel}`

Initializes the reactivity of the model `M` by setting up the custom JavaScript for integrating with the Vue.js
frontend and perform the 2-way backend-frontend data sync. Returns the instance of the model.

### Example

```julia
hs_model = Stipple.init(HelloPie())
```
"""
function init(model::M, ui::Union{String,Vector} = ""; vue_app_name::String = Stipple.Elements.root(model),
              endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route,
              debounce::Int = JS_DEBOUNCE_TIME, transport::Module = Genie.WebChannels,
              parse_errors::Bool = false)::M where {M<:ReactiveModel}

  global WEB_TRANSPORT = transport
  transport == Genie.WebChannels || (Genie.config.websockets_server = false)

  deps_routes(channel)

  Genie.Router.channel("/$(channel)/watchers") do
    payload = Genie.Router.@params(:payload)["payload"]
    client = Genie.Router.@params(:WS_CLIENT)
    # if only elements of the array change, oldval and newval are identical
    ! isa(payload["newval"], Array) && payload["newval"] == payload["oldval"] && return "OK"

    field = Symbol(payload["field"])

    #check if field exists
    hasfield(M, field) || return "OK"
    valtype = Dict(zip(fieldnames(M), M.types))[field]
    val = valtype <: Reactive ? getfield(model, field) : Ref{valtype}(getfield(model, field))
    # reject non-public types
    if val isa Reactive
      val.r_mode == PUBLIC || return "OK"
    elseif occursin(SETTINGS.readonly_pattern, String(field)) || occursin(SETTINGS.private_pattern, String(field))
      return "OK"
    end

    newval = convertvalue(val, payload["newval"])
    oldval = convertvalue(val, payload["oldval"])

    push!(model, field => newval, channel = channel, except = client)
    update!(model, field, newval, oldval)

    "OK"
  end

  ep = channel == Genie.config.webchannels_default_route ? endpoint : "js/$channel/$endpoint"
  Genie.Router.route("/$(ep)") do
    Stipple.Elements.vue_integration(model, vue_app_name = vue_app_name, endpoint = ep, channel = "", debounce = debounce) |> Genie.Renderer.Js.js
  end

  setup(model, channel)
end

"""
    `function setup(model::M, channel = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}`

Configures the reactive handlers for the reactive properties of the model. Called internally.
"""
function setup(model::M, channel = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  for field in fieldnames(M)
    f = getproperty(model, field)
    isa(f, Reactive) || continue
    if f.r_mode == 0
      if occursin(SETTINGS.private_pattern, String(field))
        f.r_mode = PRIVATE
      elseif occursin(SETTINGS.readonly_pattern, String(field))
        f.r_mode = READONLY
      else
        f.r_mode = PUBLIC
      end
    end
    f.r_mode == PRIVATE || f.no_backend_watcher && continue

    on(f) do _
      push!(model, field => f, channel = channel)
    end
  end

  model
end

#===#

"""
    `Base.push!(app::M, vals::Pair{Symbol,T}; channel::String,
                except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt}) where {T,M<:ReactiveModel}`

Pushes data payloads over to the frontend by broadcasting the `vals` through the `channel`.
"""
function Base.push!(app::M, vals::Pair{Symbol,T};
                    channel::String = Genie.config.webchannels_default_route,
                    except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt} = nothing) where {T,M<:ReactiveModel}
  WEB_TRANSPORT.broadcast(channel,
                          Genie.Renderer.Json.JSONParser.json(Dict( "key" => julia_to_vue(vals[1]),
                                                                    "value" => Stipple.render(vals[2], vals[1]))),
                          except = except)
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}};
                    channel::String = Genie.config.webchannels_default_route,
                    except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt} = nothing) where {T,M<:ReactiveModel}
                    v = vals[2].r_mode != JSFUNCTION ? vals[2][] : replace_jsfunction(vals[2][])
  push!(app, Symbol(julia_to_vue(vals[1])) => v, channel = channel, except = except)
end

#===#

RENDERING_MAPPINGS = Dict{String,String}()
mapping_keys() = collect(keys(RENDERING_MAPPINGS))

"""
    `function rendering_mappings(mappings = Dict{String,String})`

Registers additional `mappings` as Julia to Vue properties mappings  (eg `foobar` to `foo-bar`).
"""
function rendering_mappings(mappings = Dict{String,String})
  merge!(RENDERING_MAPPINGS, mappings)
end

"""
    `function julia_to_vue(field, mapping_keys = mapping_keys())`

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
    `function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}`

Renders the Julia `ReactiveModel` `app` as the corresponding Vue.js JavaScript code.
"""
function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()
  for field in fieldnames(typeof(app))
    f = getfield(app, field)
    !(f isa Reactive) && occursin(SETTINGS.private_pattern, String(field)) && continue
    f isa Reactive && f.r_mode == PRIVATE && continue
    result[julia_to_vue(field)] = Stipple.render(f, field)
  end

  vue = Dict(:el => Elements.elem(app), :mixins =>JSONText("[watcherMixin, reviveMixin]"), :data => merge(result, client_data(app)))

  isempty(components(app) |> strip)   || push!(vue, :components => components(app))
  isempty(js_methods(app) |> strip)   || push!(vue, :methods    => JSONText("{ $(js_methods(app)) }"))
  isempty(js_computed(app) |> strip)  || push!(vue, :computed   => JSONText("{ $(js_computed(app)) }"))
  isempty(js_watch(app) |> strip)     || push!(vue, :watch      => JSONText("{ $(js_watch(app)) }"))
  isempty(js_created(app) |> strip)   || push!(vue, :created    => JSONText("function(){ $(js_created(app)); }"))
  isempty(js_mounted(app) |> strip)   || push!(vue, :mounted    => JSONText("function(){ $(js_mounted(app)); }"))

  vue
end

"""
    `function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}`

Default rendering of value types. Specialize `Stipple.render` to define custom rendering for your types.
"""
function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  val
end

"""
    `function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}`

Default rendering of `Reactive` values. Specialize `Stipple.render` to define custom rendering for your type `T`.
"""
function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end

"""
```
function parse_jsfunction(s::AbstractString)
```
Checks whether the string is a valid js function and returns a `Dict` from which a reviver function
in the backend can construct a function.
"""
function parse_jsfunction(s::AbstractString)
    # look for classical function definition
    m = match( r"function\s*\(([^)]*)\)\s*{(.*)}", s)
    !isnothing(m) && length(m.captures) == 2 && return opts(arguments=m[1], body=m[2])

    # look for pure function definition
    m = match( r"\s*\(?([^=)]*?)\)?\s*=>\s*({*.*?}*)\s*$" , s )
    (isnothing(m) || length(m.captures) != 2) && return nothing

    # if pure function body is without curly brackets, add a `return`, otherwise strip the brackets
    # Note: for utf-8 strings m[2][2:end-1] will fail if the string ends with a wide character, e.g. ϕ
    body = startswith(m[2], "{") ? m[2][2:prevind(m[2], lastindex(m[2]))] : "return " * m[2]
    return opts(arguments=m[1], body=body)
end

"""
```
function replace_jsfunction!(js::Union{Dict, JSONText})
```
Replaces all JSONText values that contain a valid js function by a `Dict` that codes the function for a reviver.
For JSONText variables it encapsulates the dict in a JSONText to make the function type stable.
"""
function replace_jsfunction!(d::Dict)
    for (k,v) in d
        if isa(v, Dict)
            replace_jsfunction!(v)
        elseif isa(v, JSONText)
            jsfunc = parse_jsfunction(v.s)
            isnothing(jsfunc) || ( d[k] = opts(jsfunction=jsfunc) )
        end
    end
    return d
end

function replace_jsfunction(d::Dict)
  replace_jsfunction!(deepcopy(d))
end

function replace_jsfunction(js::JSONText)
    jsfunc = parse_jsfunction(js.s)
    isnothing(jsfunc) ? js : JSONText(json(opts(jsfunction=jsfunc)))
end
#===#

const DEPS = Function[]

vuejs() = @static Genie.Configuration.isprod() ? "vue.min.js" : "vue.js"

"""
    `function deps_routes(channel::String = Genie.config.webchannels_default_route) :: Nothing`

Registers the `routes` for all the required JavaScript dependencies (scripts).
"""
function deps_routes(channel::String = Genie.config.webchannels_default_route) :: Nothing
  Genie.Router.route("/js/stipple/$(vuejs())") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", vuejs()), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/vue_filters.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "vue_filters.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/underscore-min.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "underscore-min.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/stipplecore.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "stipplecore.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  (WEB_TRANSPORT == Genie.WebChannels ? Genie.Assets.channels_support(channel) : Genie.Assets.webthreads_support(channel))

  nothing
end

"""
    `function deps(channel::String = Genie.config.webchannels_default_route) :: String`

Outputs the HTML code necessary for injecting the dependencies in the page (the <script> tags).
"""
function deps(channel::String = Genie.config.webchannels_default_route) :: String

  endpoint = (channel == Genie.config.webchannels_default_route) ?
              Stipple.JS_SCRIPT_NAME :
              "js/$(channel)/$(Stipple.JS_SCRIPT_NAME)"

  string(
    (WEB_TRANSPORT == Genie.WebChannels ? Genie.Assets.channels_support(channel) : Genie.Assets.webthreads_support(channel)),
    Genie.Renderer.Html.script(src="$(Genie.config.base_path)js/stipple/underscore-min.js"),
    Genie.Renderer.Html.script(src="$(Genie.config.base_path)js/stipple/$(vuejs())"),
    join([f() for f in DEPS], "\n"),
    Genie.Renderer.Html.script(src="$(Genie.config.base_path)js/stipple/stipplecore.js", defer=true),
    Genie.Renderer.Html.script(src="$(Genie.config.base_path)js/stipple/vue_filters.js", defer=true),

    # if the model is not configured and we don't generate the stipple.js file, no point in requesting it
    in(Symbol("get_$(replace(endpoint, '/' => '_'))"), Genie.Router.named_routes() |> keys |> collect)
      ?
      Genie.Renderer.Html.script(src="$(Genie.config.base_path)$(endpoint)?v=$(Genie.Configuration.isdev() ? rand() : 1)",
                                    defer=true, onload="Stipple.init({theme: 'stipple-blue'});")
      :
      begin
        @warn "The Reactive Model is not initialized - make sure you call Stipple.init(YourModel()) to initialize it"
        ""
      end
  )
end

#===#

"""
    `function Core.NamedTuple(kwargs::Dict{Symbol,T})::NamedTuple where {T}`

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
    `function Core.NamedTuple(kwargs::Dict{Symbol,T}, property::Symbol, value::String)::NamedTuple where {T}`

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

macro R_str(s)
  :(Symbol($s))
end

#== ==#

# add a method to Observables.on to accept inverted order of arguments similar to route()
import Observables.on
on(observable::Observables.AbstractObservable, f::Function; weak = false) = on(f, observable; weak = weak)

"""
    `onbutton(f::Function, button::R{Bool}; async = false, weak = false)`

Links a function to a reactive boolean parameter, typically a representing a button of an app.
After the function is called, the parameter is set back to false. The `async` keyword
specifies whether the call should be made asynchroneously or not.

### Example

```julia
onbutton(model.save_button) do
  # save what has to be saved
end
```
"""
onbutton(f::Function, button::R{Bool}; async = false, kwargs...) = on(button; kwargs...) do pressed
  pressed || return
  if async
      @async begin
          try
            f()
          catch ex
            warn(ex)
          end
          button[] = false
      end
  else
      try
        f()
      catch ex
        warn(ex)
      end
      button[] = false
  end
  return
end

onbutton(button::R{Bool}, f::Function; kwargs...) = onbutton(f, button; kwargs...)

"""
    `@js_str -> JSONText`

Construct a JSONText, such as `js"button=false"`, without interpolation and unescaping
(except for quotation marks `"`` which still has to be escaped). Avoiding escaping `"`` can be done by
`js\"\"\"alert("Hello World")\"\"\"`.
"""
macro js_str(expr)
  :( JSONText($(esc(expr))) )
end

"""
    `@kwredef(expr)`

Helper function during development that is a one-to-one replacement for `@kwdef` but allows for redefinition of the struct.

Internally it defines a new struct with a number appended to the original struct name
and assigns this struct to a variable with the original struct name.
"""
macro kwredef(expr)
  expr = macroexpand(__module__, expr) # to expand @static
  expr isa Expr && expr.head === :struct || error("Invalid usage of @kwredef")
  expr = expr::Expr

  t = expr.args; n = 2
  if t[n] isa Expr && t[n].head === :<:
      t = t[n].args
      n = 1
  end
  curly = t[n] isa Expr && t[n].head === :curly
  if curly
      t = t[n].args
      n=1
  end

  T_old = t[n]
  t[n] = T_new = gensym(T_old)

  esc(quote
    Base.@kwdef $expr
    $T_old = $T_new
    $curly ? $T_new.body.name.name = $(QuoteNode(T_old)) : $T_new.name.name = $(QuoteNode(T_old)) # fix the name
  end)
end

"""
    `Stipple.@kwdef`

Helper function for model definition that acts as a one-to-one replacement for `Base.@kwdef`.

When `Stipple.isprod() == true` this macro calls `@kwredef` and allows for redefinition of models.
Otherwise it calls `Base.@kwdef`.
"""
macro kwdef(expr)
  esc(quote
    Stipple.isprod() ? Base.@kwdef($expr) : Stipple.@kwredef($expr)
  end)
end

end
