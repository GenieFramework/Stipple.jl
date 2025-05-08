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

import Base.RefValue

const ALWAYS_REGISTER_CHANNELS = RefValue(true)
const USE_MODEL_STORAGE = RefValue(true)
const PRECOMPILE = RefValue(false)

import MacroTools
import Pkg.TOML

function use_model_storage()
  USE_MODEL_STORAGE[]
end

"""
Disables the automatic storage and retrieval of the models in the session.
Useful for large models.
"""
function enable_model_storage(enable::Bool = true)
  USE_MODEL_STORAGE[] = enable
end

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
@reexport @using_except Genie.Renderers.Html: mark, div, time, view, render, Headers, menu
export render, htmldiv, js_attr
@reexport using JSON3
@reexport using StructTypes
@reexport using Parameters
@reexport using OrderedCollections

export setchannel, getchannel

# compatibility with Observables 0.3
isempty(methods(notify, Observables)) && (Base.notify(observable::AbstractObservable) = Observables.notify!(observable))

include("ParsingTools.jl")
include("NamedTuples.jl")
include("stipple/reactivity.jl")
use_model_storage() && include("ModelStorage.jl")
include("stipple/json.jl")
include("stipple/undefined.jl")
include("stipple/assets.jl")
include("stipple/converters.jl")
include("stipple/print.jl")

using .NamedTuples

export JSONParser, JSONText, json, @json, jsfunction, @jsfunction_str, JSFunction

const config = Genie.config
const channel_js_name = "'not_assigned'"

const OptDict = OrderedDict{Symbol, Any}
opts(;kwargs...) = OptDict(kwargs...)

const IF_ITS_THAT_LONG_IT_CANT_BE_A_FILENAME = 500

const LAST_ACTIVITY = Dict{Symbol, DateTime}()
const PURGE_TIME_LIMIT = Ref{Period}(Day(1))
const PURGE_NUMBER_LIMIT = RefValue(1000)
const PURGE_CHECK_DELAY = RefValue(60)

const DEBOUNCE = LittleDict{Type{<:ReactiveModel}, LittleDict{Symbol, Any}}()
const THROTTLE = LittleDict{Type{<:ReactiveModel}, LittleDict{Symbol, Any}}()

"""
    debounce(M::Type{<:ReactiveModel}, fieldnames::Union{Symbol, Vector{Symbol}}, debounce::Union{Int, Nothing} = nothing)

Add field-specific debounce times.
"""
function debounce(M::Type{<:ReactiveModel}, fieldnames::Union{Symbol, Vector{Symbol}, NTuple{N, Symbol} where N}, debounce::Union{Int, Nothing} = nothing)
  if debounce === nothing
    haskey(DEBOUNCE, M) || return
    d = DEBOUNCE[M]
    if fieldnames isa Symbol
      delete!(d, fieldnames)
    else
      for v in fieldnames
        delete!(d, v)
      end
    end
    isempty(d) && delete!(DEBOUNCE, M)
  else
    d = get!(LittleDict{Symbol, Any}, DEBOUNCE, M)
    if fieldnames isa Symbol
      d[fieldnames] = debounce
    else
      for v in fieldnames
        d[v] = debounce
      end
    end
  end
  return
end

debounce(M::Type{<:ReactiveModel}, ::Nothing) = delete!(DEBOUNCE, M)

import Observables.throttle
"""
    throttle(M::Type{<:ReactiveModel}, fieldnames::Union{Symbol, Vector{Symbol}}, debounce::Union{Int, Nothing} = nothing)

Add field-specific debounce times.
"""
function throttle(M::Type{<:ReactiveModel}, fieldnames::Union{Symbol, Vector{Symbol}, NTuple{N, Symbol} where N}, throttle::Union{Int, Nothing} = nothing)
  if throttle === nothing
    haskey(THROTTLE, M) || return
    d = THROTTLE[M]
    if fieldnames isa Symbol
      delete!(d, fieldnames)
    else
      for v in fieldnames
        delete!(d, v)
      end
    end
    isempty(d) && delete!(THROTTLE, M)
  else
    d = get!(LittleDict{Symbol, Any}, THROTTLE, M)
    if fieldnames isa Symbol
      d[fieldnames] = throttle
    else
      for v in fieldnames
        d[v] = throttle
      end
    end
  end
  return
end

throttle(M::Type{<:ReactiveModel}, ::Nothing) = delete!(THROTTLE, M)

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
  modelref = RefValue(m)
  channel = Symbol(getchannel(m))
  function(timer)
    if ! isnothing(modelref[]) && Stipple.isendoflive(modelref[])
      # trigger model finalizer
      notify(modelref[], Val(:finalize), nothing)

      # remove observers in case that :finalize was modified
      strip_observers(modelref[])
      strip_handlers(modelref[])

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
export @stipple_precompile

#===#

if !isdefined(Base, :get_extension)
  using Requires
end

function __init__()
  if (get(ENV, "STIPPLE_TRANSPORT", "webchannels") |> lowercase) == "webthreads"
    webtransport!(Genie.WebThreads)
  else
    Genie.config.websockets_server = true
  end
  deps_routes(core_theme = true)

  @static if !isdefined(Base, :get_extension)
    @require OffsetArrays  = "6fe1bfb0-de20-5000-8ca7-80f57d26f881" begin
      include(joinpath(@__DIR__, "..", "ext", "StippleOffsetArraysExt.jl"))
    end

    @require DataFrames  = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0" begin
      include(joinpath(@__DIR__, "..", "ext", "StippleDataFramesExt.jl"))
    end

    @require JSON  = "682c06a0-de6a-54ab-a142-c8b1cf79cde6" begin
      include(joinpath(@__DIR__, "..", "ext", "StippleJSONExt.jl"))
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
function watch(vue_app_name::String, fieldname::Symbol, channel::String, debounce::Int, throttle::Int, model::M; jsfunction::String = "")::String where {M<:ReactiveModel}
  isempty(jsfunction) &&
    (jsfunction = "$vue_app_name.push('$fieldname')")

  output = IOBuffer()
  if fieldname ∈ (:isready, :fileuploads)
    print(output, """
      // Don't remove this line: due to a bug we need to have a \$-sign in this function;
          ({ignoreUpdates: $vue_app_name._ignore_$fieldname} = $vue_app_name.watchIgnorable(function(){return $vue_app_name.$fieldname}, function(newVal, oldVal){$jsfunction}, {deep: true}));
      """)
  else
    AM = get_abstract_type(M)
    debounce = get(get(DEBOUNCE, AM, Dict{Symbol, Any}()), fieldname, debounce)
    throttle = get(get(THROTTLE, AM, Dict{Symbol, Any}()), fieldname, throttle)
    fn = "function(newVal, oldVal){$jsfunction}"
    throttle > 0 && (fn = "_.throttle($fn, $throttle)")
    debounce > 0 && (fn = "_.debounce($fn, $debounce)")
    print(output, """
        ({ignoreUpdates: $vue_app_name._ignore_$fieldname} = $vue_app_name.watchIgnorable(function(){return $vue_app_name.$fieldname}, $fn, {deep: true}));
    """)
  end

  String(take!(output))
end

#===#

include("stipple/parsers.jl")

#===#

function channelfactory(length::Int = 32)
  randstring('A':'Z', length)
end


const MODELDEPID = "!!MODEL!!"
const CHANNELPARAM = :CHANNEL__


function sessionid(; encrypt::Bool = true) :: Union{String,Nothing}
  sessid = Stipple.ModelStorage.Sessions.GenieSession.session().id

  encrypt ? Genie.Encryption.encrypt(sessid) : sessid
end


function sesstoken() :: ParsedHTMLString
  meta(name = "sesstoken", content=sessionid())
end


function channeldefault() :: Union{String,Nothing}
  params(CHANNELPARAM, (haskey(ENV, "$CHANNELPARAM") ? (Genie.Router.params!(CHANNELPARAM, ENV["$CHANNELPARAM"])) : nothing))
end
function channeldefault(::Type{M}) where M<:ReactiveModel
  haskey(ENV, "$CHANNELPARAM") && (Genie.Router.params!(CHANNELPARAM, ENV["$CHANNELPARAM"]))
  haskey(params(), CHANNELPARAM) && return params(CHANNELPARAM)

  if ! haskey(Genie.Router.params(), :CHANNEL) && ! haskey(Genie.Router.params(), :ROUTE)
    return nothing
  end

  model_id = Symbol(Stipple.routename(M))

  use_model_storage() || return nothing

  stored_model = Stipple.ModelStorage.Sessions.GenieSession.get(model_id, nothing)
  stored_model === nothing ? nothing : getchannel(stored_model)
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
    fieldname ∈ Stipple.INTERNALFIELDS && continue
    mode == PUBLIC || mode == :PUBLIC ? delete!(dict, fieldname) : dict[fieldname] = Core.eval(Stipple, mode)
  end
  dict
end

function deletemode!(modes, fieldnames::Symbol...)
  setmode!(modes, PUBLIC, fieldnames...)
end

function init_storage(handler::Union{Nothing, Symbol, Expr} = nothing)
  handlers = handler === nothing ? :(Function[]) : :(Function[$handler])

  LittleDict{Symbol, Expr}(
    :channel__ => :(channel__::String = Stipple.channelfactory()),
    :modes__ => :(modes__::Stipple.LittleDict{Symbol,Int} = Stipple.LittleDict{Symbol,Int}()),
    :handlers__ => :(handlers__::Vector{Function} = $handlers),
    :observerfunctions__ => :(observerfunctions__::Vector{ObserverFunction} = ObserverFunction[]),
    :isready => :(isready::Stipple.R{Bool} = false),
    :isprocessing => :(isprocessing::Stipple.R{Bool} = false),
    :fileuploads => :(fileuploads::Stipple.R{Dict{AbstractString,AbstractString}} = Dict{AbstractString,AbstractString}()),
    :ws_disconnected => :(ws_disconnected::Stipple.R{Bool} = false),
  )
end

function get_concrete_type(::Type{M})::Type{<:ReactiveModel} where M <: Stipple.ReactiveModel
  isabstracttype(M) ? Core.eval(Base.parentmodule(M), Symbol(Base.nameof(M), "!")) : M
end

function get_abstract_type(::Type{M})::Type{<:ReactiveModel} where M <: Stipple.ReactiveModel
  SM = supertype(M)
  SM <: ReactiveModel && SM != ReactiveModel ? SM : M
end

# fallback for event handling if no handler with event_info is defined
function Base.notify(model::ReactiveModel, event, event_info)
  notify(model, event)
end

# fallback for event handling without event_info
function Base.notify(model::ReactiveModel, event)
  T = typeof(event)
  event_name = T.name == Base.typename(Val) ? ":$(T.parameters[1])" : event
  @info("Warning: No event '$event_name' defined")
end

function Base.notify(model::ReactiveModel, ::Val{:finalize})
  @info("Calling finalizers")
  strip_observers(model)
  strip_handlers(model)
end


"""
    function init(::Type{M};
                    vue_app_name::S = Stipple.Elements.root(M),
                    endpoint::S = vue_app_name,
                    channel::Union{Any,Nothing} = nothing,
                    debounce::Int = JS_DEBOUNCE_TIME,
                    throttle::Int = JS_THROTTLE_TIME,
                    transport::Module = Genie.WebChannels,
                    core_theme::Bool = true)::M where {M<:ReactiveModel, S<:AbstractString}

Initializes the reactivity of the model `M` by setting up the custom JavaScript for integrating with the Vue.js
frontend and perform the 2-way backend-frontend data sync. Returns the instance of the model.

### Example

```julia
hs_model = Stipple.init(HelloPie)
```
"""
function init(t::Type{M};
              vue_app_name::S = Stipple.Elements.root(M),
              endpoint::S = vue_app_name,
              channel::Union{Any,Nothing} = channeldefault(t),
              debounce::Int = JS_DEBOUNCE_TIME,
              throttle::Int = JS_THROTTLE_TIME,
              transport::Module = Genie.WebChannels,
              core_theme::Bool = true,
              always_register_channels::Bool = ALWAYS_REGISTER_CHANNELS[])::M where {M<:ReactiveModel, S<:AbstractString}

  webtransport!(transport)
  AM = get_abstract_type(M)
  CM = get_concrete_type(M)
  model = CM |> Base.invokelatest

  transport == Genie.WebChannels || (Genie.config.websockets_server = false)
  ok_response = "OK"

  channel === nothing && (channel = channelfactory())
  setchannel(model, channel)

  # make sure we store the channel name in the model
  use_model_storage() && Stipple.ModelStorage.Sessions.store(model)

  # add a timer that checks if the model is outdated and if so prepare the model to be garbage collected
  LAST_ACTIVITY[Symbol(getchannel(model))] = now()

  PRECOMPILE[] || Timer(setup_purge_checker(model), PURGE_CHECK_DELAY[], interval = PURGE_CHECK_DELAY[])

  # register channels and routes only if within a request
  if haskey(Genie.Router.params(), :CHANNEL) || haskey(Genie.Router.params(), :ROUTE) || always_register_channels
    if is_channels_webtransport()
      Genie.Assets.channels_subscribe(channel)
    else
      Genie.Assets.webthreads_subscribe(channel)
      Genie.Assets.webthreads_push_pull(channel)
    end

    ch = "/$channel/watchers"
    Genie.Router.channel(ch, named = Router.channelname(ch)) do
      payload = Genie.Requests.payload(:payload)["payload"]
      client = transport == Genie.WebChannels ? Genie.WebChannels.id(Genie.Requests.wsclient()) : Genie.Requests.wtclient()

      try
        sesstoken = get(payload, "sesstoken", "")
        if !isempty(sesstoken) && use_model_storage()
          if sesstoken == "__undefined__"
            @warn """
            Session token not defined, make sure that `<% Stipple.sesstoken() %>` is part of the head section of your layout, e.g.
            
            <head>
              <meta charset="utf-8">
              
              <% Stipple.sesstoken() %>
              <title>Genie App</title>    
            </head>
            
            Alternatively, you can switch off model storage by calling
            
            `Stipple.enable_model_storage(false)`
            
            in your app.
            """
          else
            Genie.Router.params!(Stipple.ModelStorage.Sessions.GenieSession.PARAMS_SESSION_KEY,
                                 Stipple.ModelStorage.Sessions.GenieSession.load(sesstoken |> Genie.Encryption.decrypt))
          end
        end
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

    ch = "/$channel/keepalive"
    if ! Genie.Router.ischannel(Router.channelname(ch))
      Genie.Router.channel(ch, named = Router.channelname(ch)) do
        LAST_ACTIVITY[Symbol(channel)] = now()

        ok_response
      end
    end

    ch = "/$channel/events"
    Genie.Router.channel(ch, named = Router.channelname(ch)) do
      # get event name
      event = Genie.Requests.payload(:payload)["event"]
      # form handler parameter & call event notifier
      handler = Symbol(get(event, "name", nothing))
      event_info = get(event, "event", nothing)

      # add client id if requested
      if event_info isa Dict && get(event_info, "_addclient", false)
        client = transport == Genie.WebChannels ? Genie.WebChannels.id(Genie.Requests.wsclient()) : Genie.Requests.wtclient()
        push!(event_info, "_client" => client)
      end
      notify(model, Val(handler), event_info)

      LAST_ACTIVITY[Symbol(channel)] = now()

      ok_response
    end
  end

  haskey(DEPS, AM) || (DEPS[AM] = stipple_deps(AM, vue_app_name, debounce, throttle, core_theme, endpoint, transport))

  setup(model, channel)
end

function routename(::Type{M}) where M<:ReactiveModel
  AM = get_abstract_type(M)
  s = replace(replace(replace(string(AM), "." => "_"), r"^var\"#+" =>""), r"#+" => "_")
  replace(s, r"[^0-9a-zA-Z_]+" => "")
end

function gb_stipple_dir()
  gbdir = get(ENV, "GB_DIR", joinpath(Base.DEPOT_PATH[1], "geniebuilder"))
  replace(strip(read(`julia --project=$gbdir -E 'dirname(dirname(Base.locate_package(Base.PkgId(Base.UUID("4acbeb90-81a0-11ea-1966-bdaff8155998"), "Stipple"))))'`, String), ['"', '\n']), "\\\\" =>'/')
end

function gb_compat_deps(::Type{M}) where M <: ReactiveModel
  get(ENV, "GB_ROUTES", "false") == "true" && return
  basedir = gb_stipple_dir()
  remote_assets_config = deepcopy(Stipple.assets_config)
  remote_assets_config.version = TOML.parsefile(joinpath(basedir, "Project.toml"))["version"]
  Genie.Assets.add_fileroute(remote_assets_config, "stipplecore.css"; basedir)
  Genie.Assets.add_fileroute(remote_assets_config, "stipplecore.js"; basedir)
  Genie.Assets.add_fileroute(remote_assets_config, "vue.js"; basedir)
  Genie.Assets.add_fileroute(remote_assets_config, "vue_filters.js"; basedir)
  Genie.Router.route(Genie.Assets.asset_route(remote_assets_config, :js, file = vm(M))) do
    Stipple.Elements.vue2_integration(M) |> Genie.Renderer.Js.js
  end
  ENV["GB_ROUTES"] = true
end

function stipple_deps(::Type{M}, vue_app_name, debounce, throttle, core_theme, endpoint, transport)::Function where {M<:ReactiveModel}
  () -> begin
    if ! Genie.Assets.external_assets(assets_config)
      if ! Genie.Router.isroute(Symbol(routename(M)))
        Genie.Router.route(Genie.Assets.asset_route(assets_config, :js, file = endpoint), named = Symbol(routename(M))) do
          Stipple.Elements.vue_integration(M; vue_app_name, debounce, throttle, core_theme, transport) |> Genie.Renderer.Js.js
        end
      end
    end

    haskey(ENV, "GB_JULIA_PATH") && gb_compat_deps(M)

    [
      if ! Genie.Assets.external_assets(assets_config)
        Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file = vue_app_name), defer = true)
      else
        Genie.Renderer.Html.script([
          (Stipple.Elements.vue_integration(M; vue_app_name, debounce, throttle, core_theme, transport) |> Genie.Renderer.Js.js).body |> String
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

    on(field, priority = 1) do _
      push!(model, f => field, channel = channel)
    end
  end

  model
end

#===#

const max_retry_times = 10

"""
    Base.push!(app::M, vals::Pair{Symbol,T}; channel::String,
                except::Union{Nothing,UInt,Vector{UInt}}) where {T,M<:ReactiveModel}

Pushes data payloads over to the frontend by broadcasting the `vals` through the `channel`.
"""
function Base.push!(app::M, vals::Pair{Symbol,T};
                    channel::String = getchannel(app),
                    except::Union{Nothing,UInt,Vector{UInt}} = nothing,
                    restrict::Union{Nothing,UInt,Vector{UInt}} = nothing)::Bool where {T,M<:ReactiveModel}
  try
    use_model_storage() && Stipple.ModelStorage.Sessions.store(app)
  catch ex
    @error ex
  end

  try
    _push!(vals, channel; except, restrict)
  catch ex
    @debug ex
    false
  end
end

function _push!(vals::Pair{Symbol,T}, channel::String;
                except::Union{Nothing,UInt,Vector{UInt}} = nothing,
                restrict::Union{Nothing,UInt,Vector{UInt}} = nothing)::Bool where {T}
  try
    webtransport().broadcast(channel, json(Dict("key" => vals[1], "value" => Stipple.render(vals[2], vals[1]))); except, restrict)
  catch ex
    @debug ex
    false
  end
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}};
                    channel::String = getchannel(app),
                    except::Union{Nothing,UInt,Vector{UInt}} = nothing,
                    restrict::Union{Nothing,UInt,Vector{UInt}} = nothing)::Bool where {T,M<:ReactiveModel}
                    v = vals[2].r_mode != JSFUNCTION ? vals[2][] : replace_jsfunction(vals[2][])
  push!(app, vals[1] => v; channel, except, restrict)
end

function Base.push!(app::M;
                    channel::String = getchannel(app),
                    except::Union{Nothing,UInt,Vector{UInt}} = nothing,
                    restrict::Union{Nothing,UInt,Vector{UInt}} = nothing,
                    skip::Vector{Symbol} = Symbol[])::Bool where {M<:ReactiveModel}

  result = true

  for field in fieldnames(M)
    (isprivate(field, app) || field in skip) && continue

    push!(app, field => getproperty(app, field); channel, except, restrict) === false && (result = false)
  end

  result
end

function Base.push!(app::M, field::Symbol;
                  channel::String = getchannel(app),
                  except::Union{Nothing,UInt,Vector{UInt}} = nothing,
                  restrict::Union{Nothing,UInt,Vector{UInt}} = nothing)::Bool where {M<:ReactiveModel}
  isprivate(field, app) && return false
  push!(app, field => getproperty(app, field); channel, except, restrict)
end

@specialize

#===#

include("stipple/rendering.jl")
include("stipple/jsintegration.jl")

#===#

import OrderedCollections
const DEPS = OrderedCollections.LittleDict{Union{Any,AbstractString}, Function}()


const THEMES_FOLDER = "themes"

@nospecialize

"""
    function deps_routes(channel::String = Genie.config.webchannels_default_route) :: Nothing

Registers the `routes` for all the required JavaScript dependencies (scripts).
"""
function deps_routes(channel::String = Stipple.channel_js_name; core_theme::Bool = true) :: Nothing
  if ! Genie.Assets.external_assets(assets_config)
    if core_theme
      Genie.Router.route(Genie.Assets.asset_route(Stipple.assets_config, :css, file="stipplecore")) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", file="stipplecore")),
          :css) |> Genie.Renderer.respond
      end
    end

    Genie.Router.route(Genie.Assets.asset_route(Stipple.assets_config, :css, path=THEMES_FOLDER, file="theme-default-light")) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", path=THEMES_FOLDER, file="theme-default-light")),
        :css) |> Genie.Renderer.respond
    end

    Genie.Router.route(Genie.Assets.asset_route(Stipple.assets_config, :css, path=THEMES_FOLDER, file="theme-default-dark")) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", path=THEMES_FOLDER, file="theme-default-dark")),
        :css) |> Genie.Renderer.respond
    end

    Genie.Router.route(Genie.Assets.asset_route(Stipple.assets_config, :css, path=THEMES_FOLDER, file="theme-default-light")) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", path=THEMES_FOLDER, file="theme-default-light")),
        :css) |> Genie.Renderer.respond
    end

    Genie.Router.route(Genie.Assets.asset_route(Stipple.assets_config, :css, path=THEMES_FOLDER, file="theme-default-dark")) do
      Genie.Renderer.WebRenderable(
        Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", path=THEMES_FOLDER, file="theme-default-dark")),
        :css) |> Genie.Renderer.respond
    end

    if is_channels_webtransport()
      Genie.Assets.channels_route(Genie.Assets.jsliteral(channel))
    else
      Genie.Assets.webthreads_route(Genie.Assets.jsliteral(channel))
    end

    Genie.Assets.add_fileroute(assets_config, "underscore-min.js"; basedir = normpath(joinpath(@__DIR__, "..")))

    VUEJS = Genie.Configuration.isprod() ? "vue.global.prod.js" : "vue.global.js"
    Genie.Assets.add_fileroute(assets_config, VUEJS; basedir = normpath(joinpath(@__DIR__, "..")))
    Genie.Assets.add_fileroute(assets_config, "stipplecore.js"; basedir = normpath(joinpath(@__DIR__, "..")))
    Genie.Assets.add_fileroute(assets_config, "vue_filters.js"; basedir = normpath(joinpath(@__DIR__, "..")))
    Genie.Assets.add_fileroute(assets_config, "mixins.js"; basedir = normpath(joinpath(@__DIR__, "..")))

    if Genie.config.webchannels_keepalive_frequency > 0 && is_channels_webtransport()
      Genie.Assets.add_fileroute(assets_config, "keepalive.js"; basedir = normpath(joinpath(@__DIR__, "..")))
    end

    Genie.Assets.add_fileroute(assets_config, "vue2compat.js"; basedir = normpath(joinpath(@__DIR__, "..")))
  end

  nothing
end


function injectdeps(output::Vector{AbstractString}, M::Type{<:ReactiveModel}) :: Vector{AbstractString}
  for (key, f) in DEPS
    key isa DataType && key <: ReactiveModel && continue
    # exclude keys starting with '_'
    key isa Symbol && startswith("$key", '_') && continue
    push!(output, f()...)
  end
  AM = get_abstract_type(M)
  if haskey(DEPS, AM)
    # DEPS[AM] contains the stipple-generated deps
    push!(output, DEPS[AM]()...)
    # furthermore, include deps who's keys start with "_<name of the ReactiveModel>_"
    model_prefix = "_$(vm(AM))_"
    for (key, f) in DEPS
      key isa Symbol || continue
      startswith("$key", model_prefix) && push!(output, f()...)
    end
  end
  output
end

# no longer needed, replaced by initscript
function channelscript(channel::String) :: String
  Genie.Renderer.Html.script(["""
  document.addEventListener('DOMContentLoaded', () => window.Genie.initWebChannel('$channel') );
  """])
end

function initscript(vue_app_name, channel) :: String
  Genie.Renderer.Html.script(["""
  window.CHANNEL = null;
  document.addEventListener('DOMContentLoaded', () => window.create$vue_app_name('$channel') );
  """])
end

"""
    function deps(channel::String = Genie.config.webchannels_default_route)

Outputs the HTML code necessary for injecting the dependencies in the page (the <script> tags).
"""
function deps(m::M) :: Vector{String} where {M<:ReactiveModel}
  channel = getchannel(m)
  output = [
    initscript(vm(m), channel),
    (is_channels_webtransport() ? Genie.Assets.channels_script_tag(channel) : Genie.Assets.webthreads_script_tag(channel)),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="underscore-min")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file=(Genie.Configuration.isprod() ? "vue.global.prod" : "vue.global"))),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="stipplecore")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="vue_filters"), defer=true),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="mixins")),
    Genie.Renderer.Html.script(src = Genie.Assets.asset_path(assets_config, :js, file="vue2compat")),

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

function deps!(m::Any, M::Module)
  DEPS[m] = M.deps
end

function deps!(M::Type{<:ReactiveModel}, f::Function; extra_deps = true)
  key = extra_deps ? Symbol("_$(vm(M))_$(nameof(f))") : M
  DEPS[key] = f isa Function ? f : f.deps
end

deps!(M::Type{<:ReactiveModel}, modul::Module; extra_deps = true) = deps!(M, modul.deps; extra_deps)

deps!(m::Any, v::Vector{Union{Function, Module}}) = deps!.(RefValue(m), v)
deps!(m::Any, t::Tuple) = [deps!(m, f) for f in t]
deps!(m, args...) = [deps!(m, f) for f in args]

function clear_deps!(M::Type{<:ReactiveModel})
  delete!(DEPS, M)
  model_prefix = "_$(vm(M))_"
  for k in keys(Stipple.DEPS)
    k isa Symbol && startswith("$k", model_prefix) && delete!(DEPS, k)
  end
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
on(observable::Observables.AbstractObservable, f::Function; weak = true, kwargs...) = on(f, observable; weak, kwargs...)

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
          finally
            button[] = false
          end
      end
  else
      try
        f()
      finally
        button[] = false
      end
  end
  return
end

onbutton(button::R{Bool}, f::Function; kwargs...) = onbutton(f, button; kwargs...)

function mygensym(sym::Symbol, context = @__MODULE__)
  i = 1
  while isdefined(context, Symbol(sym, :_, i))
    i += 1
  end
  Symbol(sym, :_, i)
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
    n = 1
  end

  T = t[n]

  # Revise executes macros during compilation.
  # This leads to redefining a new struct even when the there is no change in the struct definition.
  # Most of the resulting definitions, e.g. function / constructor definitions are rewinded to not
  # pollute the name space, however, gensym executions cannot be rewinded, moreover Revise seems to add a
  # an extra level in the gensym variable names, which results to stackoverflow errors in our case.
  # Hence we define our own gensym without level nesting and we store the defining expression after successful
  # struct definition to track whether any changes occurred.
  #  Upon reevaluation of the same expression we reuse the existing name and avoid the stackoverflow.
  expr_qn = QuoteNode(copy(expr))
  expr_name = Symbol(T, :_expr)

  if isa(T, Expr) && T.head == Symbol(".")
    T = (split(string(T), '.')[end] |> Symbol)
  end
  
  t[n] = T_new = mygensym(T, __module__)
  quote
    Base.@kwdef $expr
    $T = $T_new
    if Base.VERSION < v"1.8-"
      $curly ? $T_new.body.name.name = $(QuoteNode(T)) : $T_new.name.name = $(QuoteNode(T)) # fix the name
    end
    $expr_name = $expr_qn
    $T_new
  end |> esc
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

    k_str = "$k"

    if haskey(mappings, k_str)
      k_str = mappings[k_str]
    end

    k_str == "inner" && (v = join(v))

    v_isa_jsexpr = !isa(v, Union{Symbol, AbstractString, Bool, Number})

    attr_key = (v isa Symbol || v_isa_jsexpr) && !startswith(k_str, ":") && !endswith(k_str, "!") &&
      !startswith(k_str, "v-") && !startswith(k_str, "v" * Genie.config.html_parser_char_dash) ? Symbol(":", k_str) : Symbol(k_str)

    attrs[attr_key] = v_isa_jsexpr ? js_attr(v) : v
  end

  NamedTuple(attrs)
end

#===#

include("Pages.jl")

#===#

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
  values = getfield.(RefValue(mix), fnames)
  output = quote end
  for (f, type, v) in zip(Symbol.(pre, fnames, post), fieldtypes(get_concrete_type(T)), values)
    f in Symbol.(prefix, [INTERNALFIELDS..., AUTOFIELDS...], postfix) && continue
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
const strip_handlers = striphandlers

function strip_observers(model)
  Observables.off.(model.observerfunctions__)
  empty!(model.observerfunctions__)
end

#===#

include("Typography.jl")
include("Elements.jl")
include("Theme.jl")
include("Layout.jl")

@reexport using .Typography
@reexport using .Elements
@reexport using .Theme
@reexport using .Layout

using Stipple.ReactiveTools

# precompilation ...

@app PrecompileApp begin
  @in demo_i = 1
  @out demo_s = "Hi"

  @onchange demo_i begin
    println(demo_i)
  end
end

using Stipple.ReactiveTools
@stipple_precompile begin
  ui() = [cell("hello"), row("world"), htmldiv("Hello World")]

  route("/") do
    model = Stipple.ReactiveTools.@init PrecompileApp
    page(model, ui) |> html
  end
  precompile_get("/")
  deps_routes(core_theme = true)
  precompile_get(Genie.Assets.asset_path(assets_config, :js, file = "stipplecore"))
end

end
