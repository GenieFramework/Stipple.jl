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

export setchannel, getchannel

include("ParsingTools.jl")
include("ModelStorage.jl")
include("NamedTuples.jl")

include("stipple/reactivity.jl")
include("stipple/json.jl")
include("stipple/undefined.jl")
include("stipple/assets.jl")
include("stipple/converters.jl")

using .NamedTuples

export JSONParser, JSONText, json, @json, jsfunction, @jsfunction_str

const config = Genie.config
const channel_js_name = "window.CHANNEL"

const OptDict = Dict{Symbol, Any}
opts(;kwargs...) = OptDict(kwargs...)

#===#

const WEB_TRANSPORT = Ref{Module}(Genie.WebChannels)
webtransport!(transport::Module) = WEB_TRANSPORT[] = transport
webtransport() = WEB_TRANSPORT[]
is_channels_webtransport() = webtransport() == Genie.WebChannels

#===#

export R, Reactive, ReactiveModel, @R_str, @js_str, client_data
export PRIVATE, PUBLIC, READONLY, JSFUNCTION, NO_WATCHER, NO_BACKEND_WATCHER, NO_FRONTEND_WATCHER
export newapp
export onbutton
export @kwredef
export init

#===#

include("ReactiveTools.jl")

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

  deps_routes(core_theme = true)
end

#===#

"""
    function render

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
    function update! :: {M<:ReactiveModel}

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
    function watch

Abstract function. Can be used by plugins to define custom Vue.js watch functions.
"""
function watch end

#===#

include("stipple/jsmethods.jl")
include("stipple/components.jl")
include("stipple/mutators.jl")

#===#

"""
    function watch(vue_app_name::String, fieldtype::Any, fieldname::Symbol, channel::String, debounce::Int, model::M)::String where {M<:ReactiveModel}

Sets up default Vue.js watchers so that when the value `fieldname` of type `fieldtype` in model `vue_app_name` is
changed on the frontend, it is pushed over to the backend using `channel`, at a `debounce` minimum time interval.
"""
function watch(vue_app_name::String, fieldname::Symbol, channel::String, debounce::Int, model::M; jsfunction::String = "")::String where {M<:ReactiveModel}
  js_channel = isempty(channel) ?
                "window.Genie.Settings.webchannels_default_route" :
                (channel == Stipple.channel_js_name ? Stipple.channel_js_name : "'$channel'")

  isempty(jsfunction) &&
    (jsfunction = "Genie.WebChannels.sendMessageTo($js_channel, 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal, 'sesstoken': document.querySelector(\"meta[name='sesstoken']\")?.getAttribute('content')}});")

  output = """
    $vue_app_name.\$watch(function(){return this.$fieldname}, _.debounce(function(newVal, oldVal){$jsfunction}, $debounce), {deep: true});
  """
  # in production mode vue does not fill `this.expression` in the watcher, so we do it manually
  Genie.Configuration.isprod() &&
    (output *= "$vue_app_name._watchers[$vue_app_name._watchers.length - 1].expression = 'function(){return this.$fieldname}'")

  output *= "\n\n"
end

#===#

include("stipple/parsers.jl")

#===#

function channelfactory(length::Int = 32)
  randstring('A':'Z', length)
end


const MODELDEPID = "!!MODEL!!"
const CHANNELPARAM = :CHANNEL__


function sessionid(; encrypt::Bool = true) :: String
  sessid = Stipple.ModelStorage.Sessions.GenieSession.session().id

  encrypt ? Genie.Encryption.encrypt(sessid) : sessid
end


function sesstoken() :: ParsedHTMLString
  meta(name = "sesstoken", content=sessionid())
end


function channeldefault() :: Union{String,Nothing}
  params(CHANNELPARAM, (haskey(ENV, "$CHANNELPARAM") ? (Genie.Router.params!(CHANNELPARAM, ENV["$CHANNELPARAM"])) : nothing))
end


"""
    function init(m::Type{M};
                    vue_app_name::S = Stipple.Elements.root(m),
                    endpoint::S = vue_app_name,
                    channel::Union{Any,Nothing} = nothing,
                    debounce::Int = JS_DEBOUNCE_TIME,
                    transport::Module = Genie.WebChannels,
                    core_theme::Bool = true)::M where {M<:ReactiveModel, S<:AbstractString}

Initializes the reactivity of the model `M` by setting up the custom JavaScript for integrating with the Vue.js
frontend and perform the 2-way backend-frontend data sync. Returns the instance of the model.

### Example

```julia
hs_model = Stipple.init(HelloPie)
```
"""
function init(m::Type{M};
              vue_app_name::S = Stipple.Elements.root(m),
              endpoint::S = vue_app_name,
              channel::Union{Any,Nothing} = channeldefault(),
              debounce::Int = JS_DEBOUNCE_TIME,
              transport::Module = Genie.WebChannels,
              core_theme::Bool = true)::M where {M<:ReactiveModel, S<:AbstractString}

  webtransport!(transport)
  model = Base.invokelatest(m)
  transport == Genie.WebChannels || (Genie.config.websockets_server = false)
  ok_response = "OK"

  channel = if channel !== nothing
    setchannel(model, channel)
  elseif hasproperty(model, CHANNELFIELDNAME)
    getchannel(model)
  else
    setchannel(model, channelfactory())
  end

  if is_channels_webtransport()
    Genie.Assets.channels_subscribe(channel)
  else
    Genie.Assets.webthreads_subscribe(channel)
    Genie.Assets.webthreads_push_pull(channel)
  end

  ch = "/$channel/watchers"
  if ! Genie.Router.ischannel(Symbol(ch))
    Genie.Router.channel(ch, named = Symbol(ch)) do
      payload = Genie.Requests.payload(:payload)["payload"]
      client = transport == Genie.WebChannels ? Genie.Requests.wsclient() : Genie.Requests.wtclient()

      try
        haskey(payload, "sesstoken") && ! isempty(payload["sesstoken"]) &&
          Genie.Router.params!(Stipple.ModelStorage.Sessions.GenieSession.PARAMS_SESSION_KEY,
                                Stipple.ModelStorage.Sessions.GenieSession.load(payload["sesstoken"] |> Genie.Encryption.decrypt))
      catch ex
        @error ex
      end

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
        convertvalue(val, payload["oldval"])
      catch ex
        val[]
      end

      push!(model, field => newval; channel = channel, except = client)
      update!(model, field, newval, oldval)

      ok_response
    end
  end

  ch = "/$channel/keepalive"
  if ! Genie.Router.ischannel(Symbol(ch))
    Genie.Router.channel(ch, named = Symbol(ch)) do
      ok_response
    end
  end

  ch = "/$channel/events"
  if ! Genie.Router.ischannel(Symbol(ch))
    Genie.Router.channel(ch, named = Symbol(ch)) do
      # get event name
      event = Genie.Requests.payload(:payload)["event"]
      # form handler parameter & call event notifier
      handler = Val(Symbol(get(event, "name", nothing)))
      notify(model, handler)
      return ok_response
    end
  end

  haskey(DEPS, M) || (DEPS[M] = stipple_deps(m, vue_app_name, debounce, core_theme, endpoint, transport))

  setup(model, channel)
end
function init(m::M; kwargs...)::M where {M<:ReactiveModel, S<:AbstractString}
  error("This method has been removed -- please use `init($M; kwargs...)` instead")``
end


function stipple_deps(m::Type{M}, vue_app_name, debounce, core_theme, endpoint, transport)::Function where {M<:ReactiveModel}
  () -> begin
    if ! Genie.Assets.external_assets(assets_config)
      if ! Genie.Router.isroute(Symbol(m))
        Genie.Router.route(Genie.Assets.asset_route(assets_config, :js, file = endpoint), named = Symbol(m)) do
          Stipple.Elements.vue_integration(m; vue_app_name, debounce, core_theme, transport) |> Genie.Renderer.Js.js
        end
      end
    end

    [
      if ! Genie.Assets.external_assets(assets_config)
        Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file = vue_app_name), defer = true)
      else
        Genie.Renderer.Html.script([
          (Stipple.Elements.vue_integration(m; vue_app_name, core_theme, debounce) |> Genie.Renderer.Js.js).body |> String
        ])
      end
    ]
  end
end


"""
    function setup(model::M, channel = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}

Configures the reactive handlers for the reactive properties of the model. Called internally.
"""
function setup(model::M, channel = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  for f in fieldnames(M)
    field = getproperty(model, f)

    isa(field, Reactive) || continue

    #make sure, mode is properly set
    if field.r_mode == 0
      if occursin(SETTINGS.private_pattern, String(field))
        field.r_mode = PRIVATE
      elseif occursin(SETTINGS.readonly_pattern, String(field))
        field.r_mode = READONLY
      else
        field.r_mode = PUBLIC
      end
    end

    has_backend_watcher(field) || continue

    on(field) do _
      push!(model, f => field, channel = channel)
    end
  end

  model
end

#===#

const max_retry_times = 10

"""
    Base.push!(app::M, vals::Pair{Symbol,T}; channel::String,
                except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt}) where {T,M<:ReactiveModel}

Pushes data payloads over to the frontend by broadcasting the `vals` through the `channel`.
"""
function Base.push!(app::M, vals::Pair{Symbol,T};
                    channel::String = Genie.config.webchannels_default_route,
                    except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt} = nothing)::Bool where {T,M<:ReactiveModel}
  try
    webtransport().broadcast(channel, json(Dict("key" => julia_to_vue(vals[1]), "value" => Stipple.render(vals[2], vals[1]))), except = except)
  catch ex
    @error ex
  end
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}};
                    channel::String = Genie.config.webchannels_default_route,
                    except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt} = nothing)::Bool where {T,M<:ReactiveModel}
                    v = vals[2].r_mode != JSFUNCTION ? vals[2][] : replace_jsfunction(vals[2][])
  push!(app, Symbol(julia_to_vue(vals[1])) => v, channel = channel, except = except)
end

function Base.push!(model::M;
                    channel::String = getchannel(model),
                    skip::Vector{Symbol} = Symbol[])::Bool where {M<:ReactiveModel}

  result = true

  for field in fieldnames(M)
    (isprivate(field, model) || field in skip) && continue

    push!(model, field => getproperty(model, field), channel = channel) === false && (result = false)
  end

  result
end

#===#

include("stipple/rendering.jl")
include("stipple/jsintegration.jl")

#===#

import OrderedCollections
const DEPS = OrderedCollections.OrderedDict{Union{Any,AbstractString}, Function}()

"""
    function deps_routes(channel::String = Genie.config.webchannels_default_route) :: Nothing

Registers the `routes` for all the required JavaScript dependencies (scripts).
"""
function deps_routes(channel::String = Stipple.channel_js_name; core_theme::Bool = true) :: Nothing
  if ! Genie.Assets.external_assets(assets_config)

    Genie.Router.route(Genie.Assets.asset_route(Stipple.assets_config, :css, file="stipplecore")) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", file="stipplecore")),
        :css) |> Genie.Renderer.respond
    end

    if is_channels_webtransport()
      Genie.Assets.channels_route(Genie.Assets.jsliteral(channel))
    else
      Genie.Assets.webthreads_route(Genie.Assets.jsliteral(channel))
    end

    Genie.Router.route(
      Genie.Assets.asset_route(assets_config, :js, file="underscore-min"), named = :get_underscorejs) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="underscore-min")), :javascript) |> Genie.Renderer.respond
    end

    VUEJS = Genie.Configuration.isprod() ? "vue.min" : "vue"
    Genie.Router.route(
      Genie.Assets.asset_route(assets_config, :js, file=VUEJS), named = :get_vuejs) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file=VUEJS)), :javascript) |> Genie.Renderer.respond
    end

    if core_theme
      Genie.Router.route(Genie.Assets.asset_route(assets_config, :js, file="stipplecore"), named = :get_stipplecorejs) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="stipplecore")), :javascript) |> Genie.Renderer.respond
      end
    end

    Genie.Router.route(
      Genie.Assets.asset_route(assets_config, :js, file="vue_filters"), named = :get_vuefiltersjs) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="vue_filters")), :javascript) |> Genie.Renderer.respond
    end

    Genie.Router.route(Genie.Assets.asset_route(assets_config, :js, file="watchers"), named = :get_watchersjs) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="watchers")), :javascript) |> Genie.Renderer.respond
    end

    if Genie.config.webchannels_keepalive_frequency > 0 && is_channels_webtransport()
      Genie.Router.route(Genie.Assets.asset_route(assets_config, :js, file="keepalive"), named = :get_keepalivejs) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=normpath(joinpath(@__DIR__, "..")), type="js", file="keepalive")), :javascript) |> Genie.Renderer.respond
      end
    end

  end

  nothing
end


function injectdeps(output::Vector{AbstractString}, M::Type{<:ReactiveModel}) :: Vector{AbstractString}
  for (key, f) in DEPS
    key isa DataType && key <: ReactiveModel && continue
    push!(output, f()...)
  end

  haskey(DEPS, M) && push!(output, DEPS[M]()...)

  output
end


function channelscript(channel::String) :: String
  Genie.Renderer.Html.script(["window.CHANNEL = '$(channel)';"])
end


"""
    function deps(channel::String = Genie.config.webchannels_default_route)

Outputs the HTML code necessary for injecting the dependencies in the page (the <script> tags).
"""
function deps(m::M; core_theme::Bool = true) :: Vector{String} where {M<:ReactiveModel}
  channel = getchannel(m)
  output = [
    channelscript(channel),
    (is_channels_webtransport() ? Genie.Assets.channels_script_tag(channel) : Genie.Assets.webthreads_script_tag(channel)),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="underscore-min")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file=(Genie.Configuration.isprod() ? "vue.min" : "vue"))),
    core_theme && Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="stipplecore")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="vue_filters"), defer=true),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="watchers")),

    (
      (Genie.config.webchannels_keepalive_frequency > 0 && is_channels_webtransport()) ?
        Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="keepalive"), defer=true) : ""
    )
  ]

  injectdeps(output, M)
end

function deps!(m::Any, f::Function)
  DEPS[m] = f
end

macro R_str(s)
  :(Symbol($s))
end

#== ==#

# add a method to Observables.on to accept inverted order of arguments similar to route()
import Observables.on
on(observable::Observables.AbstractObservable, f::Function; weak = true) = on(f, observable; weak = weak)

"""
    onbutton(f::Function, button::R{Bool}; async = false, weak = false)

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
    @js_str -> JSONText

Construct a JSONText, such as `js"button=false"`, without interpolation and unescaping
(except for quotation marks `"`` which still has to be escaped). Avoiding escaping `"`` can be done by
`js\"\"\"alert("Hello World")\"\"\"`.
"""
macro js_str(expr)
  :( JSONText($(esc(expr))) )
end

"""
    @kwredef(expr)

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
    if VERSION < v"1.8-alpha"
      $curly ? $T_new.body.name.name = $(QuoteNode(T_old)) : $T_new.name.name = $(QuoteNode(T_old)) # fix the name
    end

    $T_new
  end)
end

"""
    Stipple.@kwdef

Helper function for model definition that acts as a one-to-one replacement for `Base.@kwdef`.

When `Genie.Configuration.isprod() == true` this macro calls `@kwredef` and allows for redefinition of models.
Otherwise it calls `Base.@kwdef`.
"""
macro kwdef(expr)
  esc(quote
    Genie.Configuration.isprod() ? Base.@kwdef($expr) : Stipple.@kwredef($expr)
  end)
end

#===#

include("stipple/reactive_props.jl")

#===#


function attributes(kwargs::Union{Vector{<:Pair}, Base.Iterators.Pairs, Dict},
                    mappings::Dict{String,String} = Dict{String,String}())::NamedTuple

  attrs = Stipple.OptDict()
  mapped = false

  for (k,v) in kwargs
    v === nothing && continue
    mapped = false

    if haskey(mappings, string(k))
      k = mappings[string(k)]
    end

    attr_key = string((isa(v, Symbol) && ! startswith(string(k), ":") &&
                ! ( startswith(string(k), "v-") || startswith(string(k), "v" * Genie.config.html_parser_char_dash) ) ? ":" : ""), "$k") |> Symbol
    attr_val = isa(v, Symbol) && ! startswith(string(k), ":") ? Stipple.julia_to_vue(v) : v

    attrs[attr_key] = attr_val
  end

  NamedTuple(attrs)
end

#===#

include("Pages.jl")

#===#

_deepcopy(r::R{T}) where T = R(deepcopy(r.o.val), r.r_mode, r.no_backend_watcher, r.no_frontend_watcher)
_deepcopy(x) = deepcopy(x)

"""
    function register_mixin(context = @__MODULE__)

register a macro `@mixin` that can be used for inserting structs or struct types
in `ReactiveModel`s or other `Base.@kwdef` structs.

There are two modes of usage:
```
@reactive! mutable struct PlotlyDemo <: ReactiveModel
  @mixin PlotWithEvents "prefix_" "_postfix"
end

@reactive! mutable struct PlotlyDemo <: ReactiveModel
  @mixin prefix::PlotWithEvents
end
```
`prefix` and `postfix` both default to `""`
### Example

```
register_mixin(@__MODULE__)

const PlotlyEvent = Dict{String, Any}
Base.@kwdef struct PlotlyEvents
    _selected::R{PlotlyEvent} = PlotlyEvent()
    _hover::R{PlotlyEvent} = PlotlyEvent()
    _click::R{PlotlyEvent} = PlotlyEvent()
    _relayout::R{PlotlyEvent} = PlotlyEvent()
end

Base.@kwdef struct PlotWithEvents
    var""::R{Plot} = Plot()
    @mixin plot::PlotlyEvents
end

@reactive! mutable struct PlotlyDemo <: ReactiveModel
  @mixin prefix::PlotWithEvents
end

julia> fieldnames(PlotlyDemo)
(:plot, :plot_selected, :plot_hover, :plot_click, :plot_relayout, :channel__, :isready, :isprocessing)

Note: The latest version of StipplePlotly exports `PlotlyEvents`, `PlotWithEvents`, `PBPlotWithEvents`
```
"""
function register_mixin(context = @__MODULE__)
  Core.eval(context, :(
    macro mixin(expr, prefix = "", postfix = "", context = @__MODULE__)
        if hasproperty(expr, :head) && expr.head == :(::)
            prefix = string(expr.args[1])
            expr = expr.args[2]
        end

        x = eval(expr)
        pre = eval(prefix)
        post = eval(postfix)
        T = x isa DataType ? x : typeof(x)
        mix = x isa DataType ? x() : x
        values = getfield.(Ref(mix), fieldnames(T))
        output = quote end
        for (f, type, v) in zip(Symbol.(pre, fieldnames(T), post), fieldtypes(T), values)
            push!(output.args, :($(esc(f))::$type = Stipple._deepcopy($v)) )
        end

        :($output)
    end
  ))
  nothing
end

export register_mixin

export off!, nlistener

"""
    nlistener(@nospecialize(o::Observables.AbstractObservable)) = length(Observables.listeners(o))

Number of listeners of the observable.

"""
nlistener(@nospecialize(o::Observable)) = length(Observables.listeners(o))

"""
    function off!(o::Observable, index::Union{Integer, AbstractRange, Vector})

Remove listener or listeners with a given index from an observable.

### Example
```
o = Observable(10)
for i = 1:10
    on(o) do o
        println("Hello world, $i")
    end
end

off!(o, 2:2:10)

notify(o)
# Hello world, 1
# Hello world, 3
# Hello world, 5
# Hello world, 7
# Hello world, 9

off!(o, nlistener(o) - 1)

julia> notify(o)
# Hello world, 1
# Hello world, 3
# Hello world, 5
# Hello world, 9
```
"""
function off!(@nospecialize(o::Observables.AbstractObservable), index::Union{AbstractRange{<:Integer}, Vector{<:Integer}})
  allunique(index) || (@info("All indices must be distinct"); return BitVector(zeros(len)))

  len = length(index)
  callbacks = Observables.listeners(o)
  success = BitVector(zeros(len))

  for (i, n) in enumerate(reverse(sort(index)))
    if 0 < n <= length(callbacks)
      for g in Observables.removehandler_callbacks
        g(observable, callbacks[n])
      end
      deleteat!(callbacks, n)
      success[len - i + 1] = true
    end
  end

  success
end

off!(@nospecialize(o::Observables.AbstractObservable), index::Integer) = off!(o, [index])[1]

"""
    function off!(o::Observable)

Remove all listeners from an observable.
"""
off!(@nospecialize(o::Observables.AbstractObservable)) = off!(o, 1:length(Observables.listeners(o)))

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")

@reexport using .Typography
@reexport using .Elements
@reexport using .Layout

end
