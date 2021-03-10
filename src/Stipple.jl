"""
# Stipple
Stipple is a reactive UI library for Julia. It provides a rich API for building rich web UIs with 2-way bindings between HTML UI elements and Julia.
It requires minimum configuration, automatically setting up the WebSockets communication channels and automatically keeping the data in sync.

Stipple allows creating powerful reactive web data dashboards using only Julia coding. It employs a declarative programming model, the framework
taking care of the full data sync workflow.
"""
module Stipple

using Logging, Reexport

@reexport using Observables
@reexport using Genie
@reexport using Genie.Renderer.Html
import Genie.Renderer.Json.JSONParser.JSONText
import Base.@kwdef

const Reactive = Observables.Observable
const R = Reactive

WEB_TRANSPORT = Genie.WebChannels

export R, Reactive, ReactiveModel, @R_str
export newapp
export onbutton
export @kwdef, @kwredef

#===#

function __init__()
  Genie.config.websockets_server = true
end

#===#

abstract type ReactiveModel end

#===#

const JS_SCRIPT_NAME = "stipple.js"
const JS_DEBOUNCE_TIME = 300 #ms

#===#

function render end
function update! end
function watch end

"""
`function js_methods(app)`

Defines js functions for the methods section of the vue element\n
Usage is typically an app-specific method:

```
js_methods(MyDashboard) = \"\"\"
  mysquare: function (x) {
    return x^2
  }
  myadd: function (x, y) {
    return x + y
  }
\"\"\"
```
"""
function js_methods(m::Any) "" end
function js_computed(m::Any) "" end
function js_watch(m::Any) "" end

js_methods(app::M) where {M<:ReactiveModel} = js_methods(M)
js_computed(app::M) where {M<:ReactiveModel} = js_computed(M)
js_watch(app::M) where {M<:ReactiveModel} = js_watch(M)

#===#

const COMPONENTS = Dict()

function register_components(model::Type{M}, keysvals::AbstractVector) where {M<:ReactiveModel}
  haskey(COMPONENTS, model) || (COMPONENTS[model] = Any[])
  push!(COMPONENTS[model], keysvals...)
end

function components(m::Type{M}) where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  response = Dict(COMPONENTS[m]...) |> Genie.Renderer.Json.JSONParser.json
  replace(response, "\""=>"")
end

components(app::M) where {M<:ReactiveModel} = components(M)
#===#

function Observables.setindex!(observable::Observable, val, keys...; notify=(x)->true)
  count = 1
  observable.val = val

  for f in Observables.listeners(observable)
    if in(count, keys)
      count += 1
      continue
    end

    if notify(f)
        Base.invokelatest(f, val)
      end

    count += 1
  end

end

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")
include("Generator.jl")

@reexport using .Typography
@reexport using .Elements
@reexport using .Layout
using .Generator

const newapp = Generator.newapp

#===#

function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  update!(model, getfield(model, field), newval, oldval)
end

function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  field[1] = newval

  model
end

function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  setfield!(model, field, newval)

  model
end

#===#

function watch(vue_app_name::String, fieldtype::Any, fieldname::Symbol, channel::String, debounce::Int, model::M)::String where {M<:ReactiveModel}
  js_channel = channel == "" ? "window.Genie.Settings.webchannels_default_route" : "'$channel'"
  output = """
  $vue_app_name.\$watch(function () {return this.$fieldname}, _.debounce(function(newVal, oldVal){
    Genie.WebChannels.sendMessageTo($js_channel, 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal}});
  }, $debounce));
  """
  # in production mode vue does not fill `this.expression` in the watcher, so we do it manually
  if Genie.Configuration.isprod()
    output *= "$vue_app_name._watchers[$vue_app_name._watchers.length - 1].expression = 'function () {return this.$fieldname}'"
  end
  output *= "\n\n"
  return output
end

#===#

function Base.parse(::Type{T}, v::T) where {T}
  v::T
end

function init(model::M, ui::Union{String,Vector} = ""; vue_app_name::String = Stipple.Elements.root(model),
              endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route,
              debounce::Int = JS_DEBOUNCE_TIME, transport::Module = Genie.WebChannels)::M where {M<:ReactiveModel}

  global WEB_TRANSPORT = transport
  transport == Genie.WebChannels || (Genie.config.websockets_server = false)

  deps_routes(channel)

  Genie.Router.channel("/$(channel)/watchers") do
    payload = Genie.Router.@params(:payload)["payload"]
    client = Genie.Router.@params(:WS_CLIENT)

    payload["newval"] == payload["oldval"] && return "OK"

    field = Symbol(payload["field"])
    val = getfield(model, field)

    valtype = isa(val, Reactive) ? typeof(val[]) : typeof(val)

    newval = try
      if AbstractFloat >: valtype && Integer >: typeof(payload["newval"])
        convert(valtype, payload["newval"])
      else
        Base.parse(valtype, payload["newval"])
      end
    catch ex
      @error ex
      payload["newval"]
    end

    oldval = try
      if AbstractFloat >: valtype && Integer >: typeof(payload["oldval"])
        convert(valtype, payload["oldval"])
      else
        Base.parse(valtype, payload["oldval"])
      end
    catch ex
      @error ex
      payload["oldval"]
    end

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


function setup(model::M, channel = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  for f in fieldnames(typeof(model))
    isa(getproperty(model, f), Reactive) || continue

    on(getproperty(model, f)) do v
      push!(model, f => v, channel = channel)
    end
  end

  model
end

#===#

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
  push!(app, Symbol(julia_to_vue(vals[1])) => vals[2][], channel = channel, except = except)
end

#===#

RENDERING_MAPPINGS = Dict{String,String}()
mapping_keys() = collect(keys(RENDERING_MAPPINGS))

function rendering_mappings(mappings = Dict{String,String})
  merge!(RENDERING_MAPPINGS, mappings)
end

function julia_to_vue(field, mapping_keys = mapping_keys())
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

function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    result[julia_to_vue(field)] = Stipple.render(getfield(app, field), field)
  end

  vue = Dict(:el => Elements.elem(app), :mixins =>JSONText("[watcherMixin]"), :data => result)
  components(app)  != "" && push!(vue, :components => components(app))
  js_methods(app)  != "" && push!(vue, :methods    => JSONText("{ $(js_methods(app)) }"))
  js_computed(app) != "" && push!(vue, :computed   => JSONText("{ $(js_computed(app)) }"))
  js_watch(app)    != "" && push!(vue, :watch      => JSONText("{ $(js_watch(app)) }"))
  vue

end

function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  val
end

function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end

#===#


const DEPS = Function[]


vuejs() = Genie.Configuration.isprod() ? "vue.min.js" : "vue.js"


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
    in(Symbol("get_$(replace(endpoint, '/' => '_'))"), Genie.Router.named_routes() |> keys |> collect) ?
      string(
        Genie.Renderer.Html.script(src="$(Genie.config.base_path)$(endpoint)?v=$(Genie.Configuration.isdev() ? rand() : 1)",
                                    defer=true, onload="Stipple.init({theme: 'stipple-blue'});")
      ) :
      @warn "The Reactive Model is not initialized - make sure you call Stipple.init(YourModel()) to initialize it"
  )
end

#===#

function camelcase(s::String) :: String
  replacements = [replace(s, r.match=>uppercase(r.match[2:end])) for r in eachmatch(r"_.", s) |> collect] |> unique
  isempty(replacements) ? s : first(replacements)
end

function Core.NamedTuple(kwargs::Dict) :: NamedTuple
  NamedTuple{Tuple(keys(kwargs))}(collect(values(kwargs)))
end

function Core.NamedTuple(kwargs::Dict, property::Symbol, value::String) :: NamedTuple
  value = "$value $(get!(kwargs, property, ""))" |> strip
  kwargs = delete!(kwargs, property)
  kwargs[property] = value

  NamedTuple(kwargs)
end

macro R_str(s)
  :(Symbol($s))
end

function set_multi_user_mode(value)
  global MULTI_USER_MODE = value
end

function jsonify(val; escape_untitled::Bool = true) :: String
  escape_untitled ?
    replace(Genie.Renderer.Json.JSONParser.json(val), "\"undefined\""=>"undefined") :
    Genie.Renderer.Json.JSONParser.json(val)
end

# add a method to Observables.on to accept inverted order of arguments similar to route()
import Observables.on
on(observable::Observables.AbstractObservable, f::Function; weak = false) = on(f, observable; weak = weak)

"""
`onbutton(f::Function, button::R{Bool}; async = false, weak = false)`

Links a function to a reactive boolean parameter, typically a representing a button of an app.
After the function is called, the parameter is set back to false. The `async` keyword
specifies whether the call should be made asynchroneously or not.

```
onbutton(model.save_button) do
  # save what has to be saved
end
```
"""
onbutton(f::Function, button::R{Bool}; async = false, kwargs...) = on(button; kwargs...) do pressed
  pressed || return
  if async
      @async begin
          f()
          button[] = false
      end
  else
      f()
      button[] = false
  end
  return
end
onbutton(button::R{Bool}, f::Function; kwargs...) = onbutton(f, button; kwargs...)

"""
```
@kwredef
```
Helper function during development that is a one-to-one replacement
for `@kwdef` but allows for redefintion of the struct.
  
Internally it defines a new struct with a number appended to the original struct name
and assigns this struct to a variable with the original struct name.
"""
macro kwredef(expr)
  expr = macroexpand(__module__, expr) # to expand @static
  expr isa Expr && expr.head === :struct || error("Invalid usage of @kwdef")
  expr = expr::Expr

  t = expr.args; n = 2
  T = expr.args[2]
  if T isa Expr && T.head === :<:
      t = T.args; n = 1
      T = T.args[1]
  end
  if T isa Expr && T.head === :curly
      t = T.args; n=1
  end

  T_old = t[n]
  i = 1
  T_new = Symbol("$(T_old)_$i")
  while isdefined(__module__, T_new)
      i += 1
      T_new = Symbol("$(T_old)_$i")
  end
  t[n] = T_new

  quote
      Base.@kwdef $expr
      $(esc(T_old)) = $(esc(T_new))
  end
end

end
