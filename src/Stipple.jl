module Stipple

using Logging, Reexport

@reexport using Observables
@reexport using Genie
@reexport using Genie.Renderer.Html

const Reactive = Observables.Observable
const R = Reactive

export R, Reactive, ReactiveModel, @R_str
export newapp

#===#

abstract type ReactiveModel end

#===#

const JS_SCRIPT_NAME = "stipple.js"
const JS_DEBOUNCE_TIME = 300 #ms
MULTI_USER_MODE = false

#===#

function render end
function update! end
function watch end

function js_methods(m::Any)
  ""
end

#===#

const COMPONENTS = Dict()

function register_components(model::Type{M}, keysvals::Vector{Pair{K,V}}) where {M<:ReactiveModel, K, V}
  haskey(COMPONENTS, model) || (COMPONENTS[model] = Pair{K,V}[])
  push!(COMPONENTS[model], keysvals...)
end

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
      if f isa Observables.InternalFunction
        f(val)
      else
        Base.invokelatest(f, val)
      end
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
  try
    setfield!(model, field, newval)
  catch ex
    # @error ex
  end

  model
end

#===#

function watch(vue_app_name::String, fieldtype::Any, fieldname::Symbol, channel::String, debounce::Int, model::M)::String where {M<:ReactiveModel}
  js_channel = channel == "" ? "window.Genie.Settings.webchannels_default_route" : "'$channel'"
  string(vue_app_name, raw".\$watch(", "function () {return this.$fieldname}, _.debounce(function(newVal, oldVal){
    window.console.log('ws to server: $fieldname: ' + newVal);
    Genie.WebChannels.sendMessageTo($js_channel, 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal}});
  }, $debounce));\n\n")
end

#===#

function Base.parse(::Type{T}, v::T) where {T}
  v::T
end

function init(model::M, ui::Union{String,Vector} = ""; vue_app_name::String = Stipple.Elements.root(model),
              endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route,
              debounce::Int = JS_DEBOUNCE_TIME)::M where {M<:ReactiveModel}
  Genie.config.websockets_server = true

  Genie.Router.channel("/$channel/watchers") do
    try
      payload = Genie.Router.@params(:payload)["payload"]

      payload["newval"] == payload["oldval"] && return nothing

      field = Symbol(payload["field"])
      rawval = getfield(model, field)

      val = isa(rawval, Reactive) ? rawval[] : rawval
      valtype = typeof(val)

      newval = payload["newval"]
      try
        newval = convert(valtype, payload["newval"])
      catch ex
        try
          newval = Base.parse(valtype, string(i))
        catch ex2
          # @error $ex2
          # @error valtype, payload["newval"]
        end
      end

      oldval = payload["oldval"]
      try
        oldval = convert(valtype, payload["oldval"])
      catch ex
        try
          newval = Base.parse(valtype, string(i))
        catch ex2
          # @error $ex2
          # @error valtype, payload["oldval"]
        end
      end

      value_changed = newval != val

      # if update was necessary, broadcast to other clients
      if value_changed && MULTI_USER_MODE
        ws_client = Genie.Router.@params(:WS_CLIENT)
        c_clients = getfield.(Genie.WebChannels.connected_clients(channel), :client)
        other_clients = setdiff(c_clients, [ws_client])

        msg = Genie.Renderer.Json.JSONParser.json(Dict("key" => field, "value" => Stipple.render(newval, field)))
        for client in other_clients
          try
            Genie.WebChannels.message(client, msg)
          catch ex
            @info "Error $ex in broadcasting to client id $(repr(Genie.WebChannels.id(client)))."
            @info "Removing client $(repr(Genie.WebChannels.id(client))) from subscriptions ..."
            @info "Debug info: subscriptions before `pop_subscription`: $(Genie.WebChannels.SUBSCRIPTIONS)"
            Genie.WebChannels.pop_subscription(Genie.WebChannels.id(client), channel)
            @info "Debug info: subscriptions after `pop_subscription`: $(Genie.WebChannels.SUBSCRIPTIONS)"
          end
        end
      end

      @async update!(model, field, newval, oldval)
      "OK"
    catch _
    end
  end

  ep = channel == Genie.config.webchannels_default_route ? endpoint : "$channel/$endpoint"
  Genie.Router.route("/$ep") do
    Genie.WebChannels.unsubscribe_disconnected_clients()
    Stipple.Elements.vue_integration(model, vue_app_name = vue_app_name, endpoint = ep, channel = "", debounce = debounce) |> Genie.Renderer.Js.js
  end

  setup(model, channel)
end


function setup(model::M, channel = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  for f in fieldnames(typeof(model))
    isa(getproperty(model, f), Reactive) || continue

    on(getproperty(model, f)) do v
      vstr = repr(v, context = :limit => true)
      vstr = length(vstr) <= 60 ? vstr : vstr[1:56] * " ..."
      @info "broadcast to $channel: $f => $vstr"
      push!(model, f => v, channel = channel)
    end
  end

  model
end

#===#

function Base.push!(app::M, vals::Pair{Symbol,T}; channel::String = Genie.config.webchannels_default_route) where {T,M<:ReactiveModel}
  Genie.WebChannels.broadcast(channel, Genie.Renderer.Json.JSONParser.json(Dict("key" => julia_to_vue(vals[1]), "value" => Stipple.render(vals[2], vals[1]))))
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}}) where {T,M<:ReactiveModel}
  push!(app, Symbol(julia_to_vue(vals[1])) => vals[2][])
end

#===#

function components(m::Type{M}) where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  response = Dict(COMPONENTS[m]...) |> Genie.Renderer.Json.JSONParser.json
  replace(response, "\""=>"")
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

  Dict(:el => Elements.elem(app), :data => result, :components => components(typeof(app)),
   :methods => "{ $(js_methods(app)) }", :mixins => Genie.Renderer.Json.JSONParser.JSONText("[watcherMixin]"))
end

function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  val
end

function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end

#===#

const DEPS = Function[]

function deps(channel::String = Genie.config.webchannels_default_route) :: String
  vuejs = Genie.Configuration.isprod() ? "vue.min.js" : "vue.js"
  Genie.Router.route("/js/stipple/$vuejs") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", vuejs), String),
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

  endpoint = channel == Genie.config.webchannels_default_route ? Stipple.JS_SCRIPT_NAME : "$(channel)/$(Stipple.JS_SCRIPT_NAME)"
  string(
    Genie.Assets.channels_support(channel),
    Genie.Renderer.Html.script(src="/js/stipple/underscore-min.js"),
    Genie.Renderer.Html.script(src="/js/stipple/$vuejs"),
    join([f() for f in DEPS], "\n"),
    Genie.Renderer.Html.script(src="/js/stipple/stipplecore.js"),
    Genie.Renderer.Html.script(src="/js/stipple/vue_filters.js"),

    # if the model is not configured and we don't generate the stipple.js file, no point in requesting it
    (in(Symbol("get_$(replace(endpoint, "/" => "_"))"), Genie.Router.named_routes() |> keys |> collect) ?
      string(
        Genie.Renderer.Html.script("Stipple.init({theme: 'stipple-blue'});"),
        Genie.Renderer.Html.script(src="/$endpoint?v=$(Genie.Configuration.isdev() ? rand() : 1)")
      ) : ""
    )
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

end
