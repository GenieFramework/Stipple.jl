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

using Logging, Mixers, Random, Reexport, Requires

@reexport using Observables
@reexport using Genie
@reexport using Genie.Renderer.Html
@reexport using JSON3
@reexport using StructTypes
@reexport using Parameters

include("NamedTuples.jl")
using .NamedTuples

const JSONParser = JSON3
const json = JSON3.write

struct JSONText
  s::String
end

@inline StructTypes.StructType(::Type{JSONText}) = JSON3.RawType()
@inline StructTypes.construct(::Type{JSONText}, x::JSON3.RawValue) = JSONText(string(x))
@inline JSON3.rawbytes(x::JSONText) = codeunits(x.s)

macro json(expr)
  expr.args[1].args[1] = :(StructTypes.$(expr.args[1].args[1]))
  T = expr.args[1].args[2].args[2]

  quote
    $(esc(:(StructTypes.StructType(::Type{($T)}) = StructTypes.CustomStruct())))
    $(esc(expr))
  end
end

export JSONParser, JSONText, json, @json, jsfunction, @jsfunction_str

# support for handling JS `undefined` values
export Undefined, UNDEFINED

struct Undefined
end

const UNDEFINED = Undefined()
const UNDEFINED_PLACEHOLDER = "__undefined__"
const UNDEFINED_VALUE = "undefined"

@json lower(x::Undefined) = UNDEFINED_PLACEHOLDER
Base.show(io::IO, x::Undefined) = Base.print(io, UNDEFINED_VALUE)

const config = Genie.config

"""
    const assets_confg :: Genie.Assets.AssetsConfig

Manages the configuration of the assets (path, version, etc). Overwrite in order to customize:

### Example

```julia
Stipple.assets_config.package = "Foo"
```
"""
const assets_config = Genie.Assets.AssetsConfig(package = "Stipple.jl")

function Genie.Renderer.Html.attrparser(k::Symbol, v::JSONText) :: String
  if startswith(v.s, ":")
    ":$(k |> Genie.Renderer.Html.parseattr)=$(v.s[2:end]) "
  else
    "$(k |> Genie.Renderer.Html.parseattr)=$(v.s) "
  end
end


mutable struct Reactive{T} <: Observables.AbstractObservable{T}
  o::Observables.Observable{T}
  r_mode::Int
  no_backend_watcher::Bool
  no_frontend_watcher::Bool

  Reactive{T}() where {T} = new{T}(Observable{T}(), PUBLIC, false, false)
  Reactive{T}(o, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, PUBLIC, no_bw, no_fw)
  Reactive{T}(o, mode::Int, no_bw::Bool = false, no_fw::Bool = false) where {T} = new{T}(o, mode, no_bw, no_fw)
  Reactive{T}(o, mode::Int, updatemode::Int) where {T} = new{T}(o, mode, updatemode & NO_BACKEND_WATCHER != 0, updatemode & NO_FRONTEND_WATCHER != 0)

  # Construct an Reactive{Any} without runtime dispatch
  Reactive{Any}(@nospecialize(o)) = new{Any}(Observable{Any}(o), PUBLIC, false, false)
end

Reactive(r::T, arg1, args...) where T = convert(Reactive{T}, (r, arg1, args...))
Reactive(r::T) where T = convert(Reactive{T}, r)

Base.convert(::Type{T}, x::T) where {T<:Reactive} = x  # resolves ambiguity with convert(::Type{T}, x::T) in base/essentials.jl
Base.convert(::Type{T}, x) where {T<:Reactive} = T(x)

Base.convert(::Type{Reactive{T}}, (r, m)::Tuple{T, Int}) where T = m < 16 ? Reactive{T}(Observable(r), m, PUBLIC) : Reactive{T}(Observable(r), PUBLIC, m)
Base.convert(::Type{Reactive{T}}, (r, w)::Tuple{T, Bool}) where T = Reactive{T}(Observable(r), PUBLIC, w, false)
Base.convert(::Type{Reactive{T}}, (r, m, nw)::Tuple{T, Int, Bool}) where T = Reactive{T}(Observable(r), m, nw, false)
Base.convert(::Type{Reactive{T}}, (r, nbw, nfw)::Tuple{T, Bool, Bool}) where T = Reactive{T}(Observable(r), PUBLIC, nbw, nfw)
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

function Base.hash(r::T) where {T<:Reactive}
  hash((( getfield(r, f) for f in fieldnames(typeof(r)) ) |> collect |> Tuple))
end

function Base.:(==)(a::T, b::R) where {T<:Reactive,R<:Reactive}
  hash(a) == hash(b)
end

Observables.observe(r::Reactive{T}, args...; kwargs...) where T = Observables.observe(getfield(r, :o), args...; kwargs...)
Observables.listeners(r::Reactive{T}, args...; kwargs...) where T = Observables.listeners(getfield(r, :o), args...; kwargs...)

@static if isdefined(Observables, :appendinputs!)
    Observables.appendinputs!(r::Reactive{T}, obsfuncs) where T = Observables.appendinputs!(getfield(r, :o), obsfuncs)
end

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
export init

#===#

function __init__()
  Genie.config.websockets_server = true
  @require OffsetArrays  = "6fe1bfb0-de20-5000-8ca7-80f57d26f881" function convertvalue(targetfield::Union{Ref{T}, Reactive{T}}, value) where T <: OffsetArrays.OffsetArray
    a = stipple_parse(eltype(targetfield), value)

    # if value is not an OffsetArray use the offset of the current array
    if ! isa(value, OffsetArrays.OffsetArray)
      o = targetfield[].offsets
      OffsetArrays.OffsetArray(a, OffsetArrays.Origin(1 .+ o))
    # otherwise use the existing value
    else
      a
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


export @reactors, @reactive, @reactive!
export ChannelName, getchannel

const ChannelName = String


function getchannel(m::T) where {T<:ReactiveModel}
  getfield(m, :channel__)
end


function setchannel(m::T, value) where {T<:ReactiveModel}
  setfield!(m, :channel__, ChannelName(value))
end


@pour reactors begin
  channel__::ChannelName = Stipple.channelfactory()
  isready::R{Bool} = false
  isreadydelay::R{Int} = 500
  isprocessing::R{Bool} = false
end

@mix @with_kw mutable struct reactive
  @reactors
end


@mix @kwredef mutable struct reactive!
    @reactors
end


mutable struct Settings
  readonly_pattern
  private_pattern
end
Settings(; readonly_pattern = r"_$", private_pattern = r"__$") = Settings(readonly_pattern, private_pattern)

function Base.hash(r::T) where {T<:ReactiveModel}
  hash((( getfield(r, f) for f in fieldnames(typeof(r)) ) |> collect |> Tuple))
end

function Base.:(==)(a::T, b::R) where {T<:ReactiveModel,R<:ReactiveModel}
  hash(a) == hash(b)
end

#===#
struct MissingPropertyException{T<:ReactiveModel} <: Exception
  property::Symbol
  entity::T
end
Base.string(ex::MissingPropertyException) = "Entity $entity does not have required property $property"

#===#

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
required for certain types in the resulting `Dict`, specialize `JSON.lower` for that specific type.

### Example

```julia
function Stipple.render(ps::PlotSeries, fieldname::Union{Symbol,Nothing} = nothing)
  Dict(:name => ps.name, ps.plotdata.key => ps.plotdata.data)
end
```

#### Specialized JSON rendering for `Undefined`

```julia
JSON.lower(x::Undefined) = "__undefined__"
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

const jscomputed = js_computed

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

const jswatch = js_watch

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

const jscreated = js_created

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

const jsmounted = js_mounted

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

COMPONENTS = Dict()

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

function register_components(model::Type{M}, args...) where {M<:ReactiveModel}
  for a in args
    register_components(model, a)
  end
end

"""
    `function components(m::Type{M})::String where {M<:ReactiveModel}`
    `function components(app::M)::String where {M<:ReactiveModel}`

JSON representation of the Vue.js components registered for the `ReactiveModel` `M`.
"""
function components(m::Type{M})::String where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  replace(Dict(COMPONENTS[m]...) |> json, "\""=>"") |> string
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
function setindex_withoutwatchers!(field::Reactive{T}, val, keys::Int...; notify=(x)->true) where T
  count = 1
  field.o.val = val
  length(keys) == 0 && return field

  for f in Observables.listeners(field.o)
    if in(count, keys)
      count += 1

      continue
    end

    if notify(f)
      try
        Base.invokelatest(f, val)
      catch ex
        @error "Error attempting to invoke $f with $val"
        @error ex
      end
    end

    count += 1
  end

  return field
end

function Base.setindex!(r::Reactive{T}, val, args::Vector{Int}; notify=(x)->true) where T
  setindex_withoutwatchers!(r, val, args...)
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

  app
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
  stipple_parse(eltype(targetfield), value)
end

"""
    `function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}`
    `function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}`
    `function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}`

Sets the value of `model.field` from `oldval` to `newval`. Returns the upated `model` instance.
"""
function update!(model::M, field::Symbol, newval::T1, oldval::T2)::M where {T1, T2, M<:ReactiveModel}
  f = getfield(model, field)
  if f isa Reactive
    f.r_mode == PRIVATE || f.no_backend_watcher ? f[] = newval : setindex_withoutwatchers!(f, newval, 1)
  else
    setfield!(model, field, newval)
  end
  model
end

function update!(model::M, field::Reactive{T}, newval::T, oldval::T)::M where {T, M<:ReactiveModel}
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
  js_channel = isempty(channel) ?
                "window.Genie.Settings.webchannels_default_route" :
                (channel == "CHANNEL" ? "CHANNEL" : "'$channel'")

  output = """
    $vue_app_name.\$watch(function(){return this.$fieldname}, _.debounce(function(newVal, oldVal){
      Genie.WebChannels.sendMessageTo($js_channel, 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal}});
    }, $debounce), {deep: true});
  """
  # in production mode vue does not fill `this.expression` in the watcher, so we do it manually
  if Genie.Configuration.isprod()
    output *= "$vue_app_name._watchers[$vue_app_name._watchers.length - 1].expression = 'function(){return this.$fieldname}'"
  end

  output *= "\n\n"
end

#===#

# wrapper around Base.parse to prevent type piracy
stipple_parse(::Type{T}, value) where T = Base.parse(T, value)

function stipple_parse(::Type{T}, value::Dict) where T <: AbstractDict
  convert(T, value)
end

function stipple_parse(::Type{T}, value::Dict) where {Tval, T <: AbstractDict{Symbol, Tval}}
  T(zip(Symbol.(string.(keys(value))), values(value)))
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: Number, T2 <: Number}
  convert(T1, value)
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: Integer, T2 <: Number}
  round(T1, value)
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: AbstractArray, T2 <: AbstractArray}
  convert(T1, value)
end

function stipple_parse(::Type{T}, value) where T <: AbstractArray
  convert(T, eltype(T)[value])
end

function stipple_parse(::Type{T}, v::T) where {T}
  v::T
end

function stipple_parse(::Type{Symbol}, s::String)
  Symbol(s)
end


function channelfactory(length::Int = 32)
  randstring('A':'Z', length)
end


"""
    `function init(model::M, ui::Union{String,Vector} = ""; vue_app_name::String = Stipple.Elements.root(model),
                    endpoint::String = vue_app_name, channel::String = Genie.config.webchannels_default_route,
                    debounce::Int = JS_DEBOUNCE_TIME, transport::Module = Genie.WebChannels)::M where {M<:ReactiveModel}`

Initializes the reactivity of the model `M` by setting up the custom JavaScript for integrating with the Vue.js
frontend and perform the 2-way backend-frontend data sync. Returns the instance of the model.

### Example

```julia
hs_model = Stipple.init(HelloPie())
```
"""
function init(m::Type{M};
              vue_app_name::S = Stipple.Elements.root(m),
              endpoint::S = vue_app_name,
              channel::Union{Any,Nothing} = nothing,
              debounce::Int = JS_DEBOUNCE_TIME,
              transport::Module = Genie.WebChannels,
              parse_errors::Bool = false,
              core_theme::Bool = true)::M where {M<:ReactiveModel, S<:AbstractString}

  global WEB_TRANSPORT = transport
  model = Base.invokelatest(m)
  transport == Genie.WebChannels || (Genie.config.websockets_server = false)
  ok_response = "OK"

  channel = if channel !== nothing
    setchannel(model, channel)
  elseif hasproperty(model, :channel__)
    getchannel(model)
  else
    setchannel(model, channelfactory())
  end

  deps_routes(channel)

  Genie.Router.channel("/$channel/watchers") do
    payload = Genie.Requests.payload(:payload)["payload"]
    client = transport == Genie.WebChannels ? Genie.Requests.wsclient() : Genie.Requests.wtclient()

    field = Symbol(payload["field"])

    #check if field exists
    hasfield(M, field) || return ok_response

    valtype = Dict(zip(fieldnames(M), M.types))[field]
    val = valtype <: Reactive ? getfield(model, field) : Ref{valtype}(getfield(model, field))

    # reject non-public types
    if val isa Reactive
      val.r_mode == PUBLIC || return ok_response
    elseif occursin(SETTINGS.readonly_pattern, String(field)) || occursin(SETTINGS.private_pattern, String(field))
      return ok_response
    end

    newval = convertvalue(val, payload["newval"])
    oldval = try
      convertvalue(val, payload["oldval"])
    catch ex
      val[]
    end

    push!(model, field => newval; channel = channel, except = client)
    update!(model, field, newval, oldval)

    ok_response
  end

  Genie.Router.channel("/$channel/keepalive") do
    ok_response
  end

  if ! Genie.Assets.external_assets(assets_config)
    Genie.Router.route(Genie.Assets.asset_path(assets_config, :js, # path = channel,
                                              file = endpoint)) do
      Stipple.Elements.vue_integration(m; vue_app_name, channel, debounce, core_theme, transport) |> Genie.Renderer.Js.js
    end
  end

  DEPS[channel] = stipple_deps(m, vue_app_name, channel, debounce, core_theme)

  setup(model, channel)
end
function init(m::M; kwargs...)::M where {M<:ReactiveModel, S<:AbstractString}
  @warn "This method has been deprecated and will be removed soon. Please use `init(m::Type{M}, kwargs...)` instead."
  init(M; kwargs...)
end


function stipple_deps(m::Type{M}, vue_app_name, channel, debounce, core_theme)::Function where {M<:ReactiveModel}
  () -> begin
    string(
      Genie.Renderer.Html.script(["window.CHANNEL = '$(channel)';"]),
      if ! Genie.Assets.external_assets(assets_config)
        Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js,
                                  file = vue_app_name), defer = true)
      else
        Genie.Renderer.Html.script([
          (Stipple.Elements.vue_integration(m; vue_app_name, channel, core_theme, debounce) |> Genie.Renderer.Js.js).body |> String
        ])
      end
    )
  end
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
  try
    WEB_TRANSPORT.broadcast(channel,
                                    json(Dict("key" => julia_to_vue(vals[1]),
                                              "value" => Stipple.render(vals[2], vals[1]))),
                                    except = except)
  catch
  end
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}};
                    channel::String = Genie.config.webchannels_default_route,
                    except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt} = nothing) where {T,M<:ReactiveModel}
                    v = vals[2].r_mode != JSFUNCTION ? vals[2][] : replace_jsfunction(vals[2][])
  push!(app, Symbol(julia_to_vue(vals[1])) => v, channel = channel, except = except)
end

function Base.push!(model::M;
                    channel::String = getchannel(model),
                    skip::Vector{Symbol} = Symbol[]) where {M<:ReactiveModel}
  for field in fieldnames(M)
    (ispublic(field, model) && !(field in skip)) || continue

    push!(model, field => getproperty(model, field), channel = channel)
  end
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

    occursin(SETTINGS.private_pattern, String(field)) && continue
    f isa Reactive && f.r_mode == PRIVATE && continue

    result[julia_to_vue(field)] = Stipple.render(f, field)
  end

  vue = Dict(:el => Elements.elem(app), :mixins => JSONText("[watcherMixin, reviveMixin]"), :data => merge(result, client_data(app)))

  isempty(components(app)   |> strip)   || push!(vue, :components => components(app))
  isempty(js_methods(app)   |> strip)   || push!(vue, :methods    => JSONText("{ $(js_methods(app)) }"))
  isempty(js_computed(app)  |> strip)   || push!(vue, :computed   => JSONText("{ $(js_computed(app)) }"))
  isempty(js_watch(app)     |> strip)   || push!(vue, :watch      => JSONText("{ $(js_watch(app)) }"))
  isempty(js_created(app)   |> strip)   || push!(vue, :created    => JSONText("function(){ $(js_created(app)); }"))
  isempty(js_mounted(app)   |> strip)   || push!(vue, :mounted    => JSONText("function(){ $(js_mounted(app)); }"))

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
# fallback is identity function
replace_jsfunction!(x) = x

function replace_jsfunction!(d::Dict)
    for (k,v) in d
        if isa(v, Dict) || isa(v, Array)
            replace_jsfunction!(v)
        elseif isa(v, JSONText)
            jsfunc = parse_jsfunction(v.s)
            isnothing(jsfunc) || ( d[k] = opts(jsfunction=jsfunc) )
        end
    end
    return d
end

function replace_jsfunction!(v::Array)
  replace_jsfunction!.(v)
end

function replace_jsfunction(d::Dict)
  replace_jsfunction!(deepcopy(d))
end

function replace_jsfunction(v::Vector)
  replace_jsfunction!.(deepcopy(v))
end

function replace_jsfunction(js::JSONText)
    jsfunc = parse_jsfunction(js.s)
    isnothing(jsfunc) ? js : JSONText(json(opts(jsfunction=jsfunc)))
end

replace_jsfunction(s::AbstractString) = replace_jsfunction(JSONText(s))

"""
    `function jsfunction(jscode::String)`

Build a dictionary that is converted to a js function in the frontend by the reviver.
There is also a string macro version `jsfunction"<js code>"`
"""
function jsfunction(jscode::String)
  jsfunc = parse_jsfunction(jscode)
  isnothing(jsfunc) && (jsfunc = opts(arguments = "", body = jscode) )
  opts(jsfunction = jsfunc)
end

"""
    `jsfunction"<js code>"`

Build a dictionary that is converted to a js function in the frontend by the reviver.
"""
macro jsfunction_str(expr)
  :( jsfunction($(esc(expr))) )
end

"""
    `function Base.run(model::ReactiveModel, jscode::String; context = :model)`

Execute js code in the frontend. `context` can be `:model` or `:app`
"""
function Base.run(model::ReactiveModel, jscode::String; context = :model)
  context ∈ (:model, :app) && push!(model, Symbol("js_", context) => jsfunction(jscode); channel = getchannel(model))
  nothing
end

#===#

import OrderedCollections
const DEPS = OrderedCollections.OrderedDict{Union{Module, String}, Function}()

"""
    `function deps_routes(channel::String = Genie.config.webchannels_default_route) :: Nothing`

Registers the `routes` for all the required JavaScript dependencies (scripts).
"""
function deps_routes(channel::AbstractString = Genie.config.webchannels_default_route) :: Nothing
  if ! Genie.Assets.external_assets(assets_config)

    VUEJS = Genie.Configuration.isprod() ? "vue.min" : "vue"

    Genie.Router.route(
      Genie.Assets.asset_path(assets_config, :js, file=VUEJS), named = :get_vuejs) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file=VUEJS)), :javascript) |> Genie.Renderer.respond
    end

    Genie.Router.route(
      Genie.Assets.asset_path(assets_config, :js, file="vue_filters"), named = :get_vuefiltersjs) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="vue_filters")), :javascript) |> Genie.Renderer.respond
    end

    Genie.Router.route(
      Genie.Assets.asset_path(assets_config, :js, file="underscore-min"), named = :get_underscorejs) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="underscore-min")), :javascript) |> Genie.Renderer.respond
    end

    Genie.Router.route(Genie.Assets.asset_path(assets_config, :js, file="stipplecore"), named = :get_stipplecorejs) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="stipplecore")), :javascript) |> Genie.Renderer.respond
    end

    Genie.Router.route(Genie.Assets.asset_path(assets_config, :js, file="watchers"), named = :get_watchersjs) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="watchers")), :javascript) |> Genie.Renderer.respond
    end

    if Genie.config.webchannels_keepalive_frequency > 0 && WEB_TRANSPORT == Genie.WebChannels
      Genie.Router.route(Genie.Assets.asset_path(assets_config, :js, file="keepalive"), named = :get_keepalivejs) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="keepalive")), :javascript) |> Genie.Renderer.respond
      end
    end

  end

  (WEB_TRANSPORT == Genie.WebChannels ? Genie.Assets.channels_support(channel) : Genie.Assets.webthreads_support(channel))

  nothing
end


"""
    `function deps(channel::String = Genie.config.webchannels_default_route) :: String`

Outputs the HTML code necessary for injecting the dependencies in the page (the <script> tags).
"""
function deps(channel::String = Genie.config.webchannels_default_route; core_theme::Bool = true) :: String

  string(
    (WEB_TRANSPORT == Genie.WebChannels ? Genie.Assets.channels_support(channel) : Genie.Assets.webthreads_support(channel)),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="underscore-min")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file=(Genie.Configuration.isprod() ? "vue.min" : "vue"))),

    core_theme && Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="stipplecore")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="vue_filters"), defer=true),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="watchers")),

    (
      (Genie.config.webchannels_keepalive_frequency > 0 && WEB_TRANSPORT == Genie.WebChannels) ?
        Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="keepalive"), defer=true) : ""
    ),

    join([f() for (key, f) in DEPS if isa(key, Module) || key == channel], "\n")
  )
end

function deps(m::M; kwargs...) where {M<:ReactiveModel}
  deps(getchannel(m); kwargs...)
end

macro R_str(s)
  :(Symbol($s))
end

#== ==#

# add a method to Observables.on to accept inverted order of arguments similar to route()
import Observables.on
on(observable::Observables.AbstractObservable, f::Function; weak = true) = on(f, observable; weak = weak)

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
        @warn(ex)
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

When `Genie.Configuration.isprod() == true` this macro calls `@kwredef` and allows for redefinition of models.
Otherwise it calls `Base.@kwdef`.
"""
macro kwdef(expr)
  esc(quote
    Genie.Configuration.isprod() ? Base.@kwdef($expr) : Stipple.@kwredef($expr)
  end)
end


function isprivate(field::Symbol, model::M)::Bool where {M<:ReactiveModel}
  val = getfield(model, field)
  val isa Reactive && (val.r_mode != PUBLIC || val.no_frontend_watcher) && return true
  ! isa(val, Reactive) && occursin(Stipple.SETTINGS.private_pattern, String(field)) && return true

  false
end


function isreadonly(field::Symbol, model::M)::Bool where {M<:ReactiveModel}
  val = getfield(model, field)
  ! isa(val, Reactive) && occursin(Stipple.SETTINGS.readonly_pattern, String(field)) && return true

  false
end

function ispublic(field::Symbol, model::M)::Bool where {M<:ReactiveModel}
  ! isprivate(field, model) && ! isreadonly(field, model)
end


end
