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

"""
@using_except(expr)

using statement while excluding certain names

### Example
```
using Parent.MyModule: x, y
```
will import all names from Parent.MyModule except `x` and `y`. Currently suports only a single module.
"""
macro using_except(expr)
  # check validity
  expr isa Expr && (expr.args[1] == :(:) || (expr.args[1].head == :call && expr.args[1].args[1] == :(:))) || return

  # determine module name and list of excluded symbols
  m, excluded = expr.args[1] == :(:) ? (expr.args[2], Symbol[expr.args[3]]) : (expr.args[1].args[2], Symbol[s for s in vcat([expr.args[1].args[3]], expr.args[2:end])])

  # convert m.args to list of Symbols
  if m isa Expr
      m.args[2] = m.args[2].value
      while m.args[1] isa Expr
          pushfirst!(m.args, m.args[1].args[1]);
          m.args[2] = m.args[2].args[2].value
      end
  end

  m_name = m isa Expr ? m.args[end] : m

  # as a first step use only the module name
  # by constructing `using Parent.MyModuleName: MyModule`
  expr = :(using dummy1: dummy2)
  expr.args[1].args[1].args = m isa Expr ? m.args : Any[m]
  expr.args[1].args[2].args[1] = m_name

  # execute the using statement
  M = Core.eval(__module__, :($expr; $m_name))

  # determine list of all exported names
  nn = filter!(x -> Base.isexported(M, x) && ! (x ∈ excluded) && isdefined(M, x), names(M; all = true, imported = true))

  # convert the list of symbols to list of imported names
  args = [:($(Expr(:., n))) for n in nn]

  # re-use previous expression and insert the names to be imported
  expr.args[1].args = pushfirst!(args, expr.args[1].args[1])

  @debug(expr)
  expr
end


using Logging, Mixers, Random, Reexport, Dates, Tables

@reexport using Observables
@reexport @using_except Genie: download
import Genie.Router.download
@reexport @using_except Genie.Renderer.Html: mark, div, time, view, render, Headers
const htmldiv = Html.div
export render, htmldiv
@reexport using JSON3
@reexport using StructTypes
@reexport using Parameters
@reexport using OrderedCollections

export setchannel, getchannel

# compatibility with Observables 0.3
isempty(methods(notify, Observables)) && (Base.notify(observable::AbstractObservable) = Observables.notify!(observable))

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

const IF_ITS_THAT_LONG_IT_CANT_BE_A_FILENAME = 500

const LAST_ACTIVITY = Dict{Symbol, DateTime}()
const PURGE_TIME_LIMIT = Ref{Period}(Day(1))
const PURGE_NUMBER_LIMIT = Ref(1000)
const PURGE_CHECK_DELAY = Ref(60)

"""
`function sorted_channels()`

return the active channels sorted by latest activity, latest appear first
"""
function sorted_channels()
  getindex.(sort(rev = true, collect(zip(values(LAST_ACTIVITY), keys(LAST_ACTIVITY)))), 2)
end

"""
`function delete_channels(channelname::Union{Symbol, AbstractString})`

delete all channels that are associated with this channelname
"""
function delete_channels(channelname::Union{Symbol, AbstractString})
  r = Regex("/?$channelname", "i")
  for c in Genie.Router.channels()
    startswith(String(c.name), r) && delete!(Genie.Router._channels, c.name)
  end
end

function isendoflive(@nospecialize(m::ReactiveModel))
  channel = Symbol(getchannel(m))
  last_activity = get!(now, LAST_ACTIVITY, channel)
  limit_reached = now() - last_activity > PURGE_TIME_LIMIT[] ||
    length(LAST_ACTIVITY) > PURGE_NUMBER_LIMIT[] &&
    last_activity ≤ LAST_ACTIVITY[sorted_channels()[PURGE_NUMBER_LIMIT[] + 1]]
  if limit_reached
    # prevent removal of clients that are still connected (should not happen, though)
    cc = Genie.WebChannels.connected_clients()
    isempty(cc) || getchannel(m) ∉ reduce(vcat, getfield.(cc, :channels))
  else
    false
  end
end

function setup_purge_checker(@nospecialize(m::ReactiveModel))
  modelref = Ref(m)
  channel = Symbol(getchannel(m))
  function(timer)
      if ! isnothing(modelref[]) && Stipple.isendoflive(modelref[])
          println("deleting ", channel)
          Stipple.delete_channels(channel)
          delete!(Stipple.LAST_ACTIVITY, channel)
          # it seems that deleting the channels is sufficient
          # in case that in future we know better, there is room to do
          # some model-specific clean-up here, e.g.
          # striphandlers(modelref[])
          # modelref[] = nothing
          close(timer)
      else
          # @info "purge_checker of $channel is alive"
      end
  end
end

#===#

const WEB_TRANSPORT = Ref{Module}(Genie.WebChannels)
webtransport!(transport::Module) = WEB_TRANSPORT[] = transport
webtransport() = WEB_TRANSPORT[]
is_channels_webtransport() = webtransport() == Genie.WebChannels

#===#

export R, Reactive, ReactiveModel, @R_str, @js_str, client_data, setmode!
export PRIVATE, PUBLIC, READONLY, JSFUNCTION, NON_REACTIVE
export NO_WATCHER, NO_BACKEND_WATCHER, NO_FRONTEND_WATCHER
export newapp
export onbutton
export init
export isconnected

#===#

function setmode! end
function deletemode! end
function init_storage end

include("Tools.jl")
include("ReactiveTools.jl")

#===#

if !isdefined(Base, :get_extension)
  using Requires
end

function __init__()
  Genie.config.websockets_server = true
  deps_routes(core_theme = true)

  @static if !isdefined(Base, :get_extension)
    @require OffsetArrays  = "6fe1bfb0-de20-5000-8ca7-80f57d26f881" begin
      # evaluate the code of the extension without the surrounding module
      include(joinpath(@__DIR__, "..", "ext", "StippleOffsetArrays.jl"))
      # Core.eval(@__MODULE__, Meta.parse(join(jl, ';')).args[3])
    end

    @require DataFrames  = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0" begin
      # evaluate the code of the extension without the surrounding module
      include(joinpath(@__DIR__, "..", "ext", "StippleDataFrames.jl"))
      # Core.eval(@__MODULE__, Meta.parse(join(jl, ';')).args[3])
    end
  end
end

function rendertable end

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

  if fieldname == :isready
    output = """
      $vue_app_name.\$watch(function(){return this.$fieldname}, function(newVal, oldVal){$jsfunction}, {deep: true});
    """
  else
    output = """
      $vue_app_name.\$watch(function(){return this.$fieldname}, _.debounce(function(newVal, oldVal){$jsfunction}, $debounce), {deep: true});
    """
  end
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

@nospecialize

function accessmode_from_pattern!(model::ReactiveModel)
  for field in fieldnames(typeof(model))
    if !(field isa Reactive)
      if occursin(Stipple.SETTINGS.private_pattern, string(field))
        model.modes__[field] = PRIVATE
      elseif occursin(Stipple.SETTINGS.readonly_pattern, string(field))
        model.modes__[field] = READONLY
      end
    end
  end
  model
end

function setmode!(model::ReactiveModel, mode::Int, fieldnames::Symbol...)
  for fieldname in fieldnames
    if getfield(model, fieldname) isa Reactive
      delete!(model.modes__, fieldname)
    else
      setmode!(model.modes__, mode, fieldnames...)
    end
  end
end

function setmode!(dict::AbstractDict, mode, fieldnames::Symbol...)
  for fieldname in fieldnames
    fieldname in [Stipple.CHANNELFIELDNAME, :modes__] && continue
    mode == PUBLIC || mode == :PUBLIC ? delete!(dict, fieldname) : dict[fieldname] = Core.eval(Stipple, mode)
  end
  dict
end

function deletemode!(modes, fieldnames::Symbol...)
  setmode!(modes, PUBLIC, fieldnames...)
end

function init_storage()
  LittleDict{Symbol, Expr}(
    CHANNELFIELDNAME =>
      :($(Stipple.CHANNELFIELDNAME)::$(Stipple.ChannelName) = Stipple.channelfactory()),
    :modes__ => :(modes__::Stipple.LittleDict{Symbol, Int} = Stipple.LittleDict{Symbol, Int}()),
    :isready => :(isready::Stipple.R{Bool} = false),
    :isprocessing => :(isprocessing::Stipple.R{Bool} = false)
  )
end

function get_concrete_type(::Type{M})::Type{<:ReactiveModel} where M <: Stipple.ReactiveModel
  isabstracttype(M) ? Core.eval(Base.parentmodule(M), Symbol(Base.nameof(M), "!")) : M
end

function get_abstract_type(::Type{M})::Type{<:ReactiveModel} where M <: Stipple.ReactiveModel
  SM = supertype(M)
  SM <: ReactiveModel && SM != ReactiveModel ? SM : M
end

"""
    function init(::Type{M};
                    vue_app_name::S = Stipple.Elements.root(M),
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
function init(::Type{M};
              vue_app_name::S = Stipple.Elements.root(M),
              endpoint::S = vue_app_name,
              channel::Union{Any,Nothing} = channeldefault(),
              debounce::Int = JS_DEBOUNCE_TIME,
              transport::Module = Genie.WebChannels,
              core_theme::Bool = true)::M where {M<:ReactiveModel, S<:AbstractString}

  webtransport!(transport)
  AM = get_abstract_type(M)
  CM = get_concrete_type(M)
  model = CM |> Base.invokelatest

  transport == Genie.WebChannels || (Genie.config.websockets_server = false)
  ok_response = "OK"

  channel = if channel !== nothing
    setchannel(model, channel)
  elseif hasproperty(model, CHANNELFIELDNAME)
    getchannel(model)
  else
    setchannel(model, channelfactory())
  end

  # add a timer that checks if the model is outdated and if so prepare the model to be garbage collected
  LAST_ACTIVITY[Symbol(getchannel(model))] = now()

  Timer(setup_purge_checker(model), PURGE_CHECK_DELAY[], interval = PURGE_CHECK_DELAY[])

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
          Genie.Router.params!(:session,
                                Stipple.ModelStorage.Sessions.GenieSession.load(payload["sesstoken"] |> Genie.Encryption.decrypt))
      catch ex
        @error ex
      end

      field = Symbol(payload["field"])

      #check if field exists
      hasfield(CM, field) || return ok_response

      valtype = Dict(zip(fieldnames(CM), CM.types))[field]
      val = valtype <: Reactive ? getfield(model, field) : Ref{valtype}(getfield(model, field))

      # reject non-public types
      ( isprivate(field, model) || isreadonly(field, model) ) && return ok_response

      newval = convertvalue(val, payload["newval"])
      oldval = try
        convertvalue(val, payload["oldval"])
      catch ex
        val[]
      end

      push!(model, field => newval; channel = channel, except = client)
      LAST_ACTIVITY[Symbol(channel)] = now()

      try
        update!(model, field, newval, oldval)
      catch ex
        # send the error to the frontend
        if Genie.Configuration.isdev()
          return ex
        else
          return "An error has occured -- please check the logs"
        end
      end

      ok_response
    end
  end

  ch = "/$channel/keepalive"
  if ! Genie.Router.ischannel(Symbol(ch))
    Genie.Router.channel(ch, named = Symbol(ch)) do
      LAST_ACTIVITY[Symbol(channel)] = now()
      ok_response
    end
  end

  ch = "/$channel/events"
  if ! Genie.Router.ischannel(Symbol(ch))
    Genie.Router.channel(ch, named = Symbol(ch)) do
      # get event name
      event = Genie.Requests.payload(:payload)["event"]
      # form handler parameter & call event notifier
      handler = Symbol(get(event, "name", nothing))
      event_info = get(event, "event", nothing)
      isempty(methods(notify, (M, Val{handler}))) || notify(model, Val(handler))
      isempty(methods(notify, (M, Val{handler}, Any))) || notify(model, Val(handler), event_info)
      LAST_ACTIVITY[Symbol(channel)] = now()
      ok_response
    end
  end

  haskey(DEPS, AM) || (DEPS[AM] = stipple_deps(AM, vue_app_name, debounce, core_theme, endpoint, transport))

  setup(model, channel)
end
function init(m::M; kwargs...)::M where {M<:ReactiveModel}
  error("This method has been removed -- please use `init($M; kwargs...)` instead")``
end


function routename(::Type{M}) where M<:ReactiveModel
  AM = get_abstract_type(M)
  s = replace(replace(replace(string(AM), "." => "_"), r"^var\"#+" =>""), r"#+" => "_")
  replace(s, r"[^0-9a-zA-Z_]+" => "")
end

function stipple_deps(::Type{M}, vue_app_name, debounce, core_theme, endpoint, transport)::Function where {M<:ReactiveModel}
  () -> begin
    if ! Genie.Assets.external_assets(assets_config)
      if ! Genie.Router.isroute(Symbol(routename(M)))
        Genie.Router.route(Genie.Assets.asset_route(assets_config, :js, file = endpoint), named = Symbol(routename(M))) do
          Stipple.Elements.vue_integration(M; vue_app_name, debounce, core_theme, transport) |> Genie.Renderer.Js.js
        end
      end
    end

    [
      if ! Genie.Assets.external_assets(assets_config)
        Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file = vue_app_name), defer = true)
      else
        Genie.Renderer.Html.script([
          (Stipple.Elements.vue_integration(M; vue_app_name, core_theme, debounce) |> Genie.Renderer.Js.js).body |> String
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
    @debug ex
    false
  end
end

function Base.push!(model::M, vals::Pair{Symbol,Reactive{T}};
                    channel::String = getchannel(model),
                    except::Union{Genie.WebChannels.HTTP.WebSockets.WebSocket,Nothing,UInt} = nothing)::Bool where {T,M<:ReactiveModel}
                    v = vals[2].r_mode != JSFUNCTION ? vals[2][] : replace_jsfunction(vals[2][])
  push!(model, Symbol(julia_to_vue(vals[1])) => v; channel, except)
end

function Base.push!(model::M;
                    channel::String = getchannel(model),
                    skip::Vector{Symbol} = Symbol[])::Bool where {M<:ReactiveModel}

  result = true

  for field in fieldnames(M)
    (isprivate(field, model) || field in skip) && continue

    push!(model, field => getproperty(model, field); channel) === false && (result = false)
  end

  result
end

function Base.push!(model::M, field::Symbol; channel::String = getchannel(model))::Bool where {M<:ReactiveModel}
  isprivate(field, model) && return false
  push!(model, field => getproperty(model, field); channel)
end

@specialize

#===#

include("stipple/rendering.jl")
include("stipple/jsintegration.jl")

#===#

import OrderedCollections
const DEPS = OrderedCollections.LittleDict{Union{Any,AbstractString}, Function}()

"""
    function deps_routes(channel::String = Genie.config.webchannels_default_route) :: Nothing

Registers the `routes` for all the required JavaScript dependencies (scripts).
"""

@nospecialize

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
  AM = get_abstract_type(M)
  haskey(DEPS, AM) && push!(output, DEPS[AM]()...)

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

@specialize

"""
Create a js expression that is bound to a field of a vue component.
Internally this is nothing than conversion to a Symbol, but it's a short version for creating symbols with spaces.

### Example

```
julia> btn("", @click("toggleFullscreen"), icon = R"is_fullscreen ? 'fullscreen_exit' : 'fullscreen'")
"<q-btn label v-on:click=\"toggleFullscreen\" :icon=\"is_fullscreen ? 'fullscreen_exit' : 'fullscreen'\"></q-btn>"
```
Note: For expressions that contain only variable names, we recommend the Symbol notation
```
julia> btn("", @click("toggleFullscreen"), icon = :fullscreen_icon)
"<q-btn label v-on:click=\"toggleFullscreen\" :icon=\"fullscreen_icon\"></q-btn>"
```
"""
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

  if isa(T_old, Expr) && T_old.head == Symbol(".")
    T_old = (split(string(T_old), '.')[end] |> Symbol)
  end

  t[n] = T_new = gensym(T_old)

  esc(quote
    Base.@kwdef $expr
    $T_old = $T_new
    if Base.VERSION < v"1.8-"
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

# function _deepcopy(r::R{T}) where T
#   v_copy = deepcopy(r.o.val)
#   :(R{$T}($v_copy, $(r.r_mode), $(r.no_backend_watcher), $(r.no_frontend_watcher), $(r.__source__)))
# end
_deepcopy(r::R{T}) where T = R(deepcopy(r.o.val), r.r_mode, r.no_backend_watcher, r.no_frontend_watcher)

_deepcopy(x) = deepcopy(x)

"""
    function register_mixin is deprecated, `@mixin` now works without any predefinition
"""
function register_mixin end

"""
    macro mixin_old(expr, prefix, postfix)

`@mixin_old` is the former `@mixin` which has been refactored to be merged with the new reactive API.
It is deprecated and will be removed in the next major version of Stipple.

`@mixin_old` is used for inserting structs or struct types
in `ReactiveModel`s or other `Base.@kwdef` structs.

There are two modes of usage:
```
@vars PlotlyDemo begin
  @mixin PlotWithEvents "prefix_" "_postfix"
end

and

@vars PlotlyDemo begin
  @mixin prefix::PlotWithEvents
end
```
`prefix` and `postfix` both default to `""`
### Example

```
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

@vars PlotlyDemo begin
    @mixin prefix::PlotWithEvents
end

julia> fieldnames(PlotlyDemo)
(:plot, :plot_selected, :plot_hover, :plot_click, :plot_relayout, :channel__, :isready, :isprocessing)

The above code is part of StipplePlotly. The latest version of StipplePlotly exports `PlotlyEvents`, `PlotWithEvents`, `PBPlotWithEvents`

Note the usage of `var""` in mixin fields, which means that an empty name is appended to the prefix.
This is typically used for cases when there is a main entry with options. In that case the prefix
determines the name of the main field and the other fieldnames are typically prefixed with a hyphen.
```
"""
macro mixin_old(expr, prefix = "", postfix = "")
  if hasproperty(expr, :head) && expr.head == :(::)
      prefix = string(expr.args[1])
      expr = expr.args[2]
  end

  x = Core.eval(__module__, expr)
  pre = Core.eval(__module__, prefix)
  post = Core.eval(__module__, postfix)

  T = x isa DataType ? x : typeof(x)
  mix = x isa DataType ? x() : x
  fnames = fieldnames(get_concrete_type(T))
  values = getfield.(Ref(mix), fnames)
  output = quote end
  for (f, type, v) in zip(Symbol.(pre, fnames, post), fieldtypes(get_concrete_type(T)), values)
    f in Symbol.(prefix, [:channel__, :modes__, AUTOFIELDS...], postfix) && continue
    v_copy = Stipple._deepcopy(v)
    push!(output.args, v isa Symbol ? :($f::$type = $(QuoteNode(v))) : :($f::$type = $v_copy))
  end

  esc(:($output))
end

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

function striphandlers(m::M) where M <: ReactiveModel
  for (f, T) in zip(fieldnames(M), fieldtypes(M))
      T <: Reactive && off!(getfield(m, f))
  end
end

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")

@reexport using .Typography
@reexport using .Elements
@reexport using .Layout

end
