module Stipple

using Revise
using Logging, Reexport

import Genie
@reexport using Observables
const Reactive = Observables.Observable
const R = Reactive

export R, Reactive, ReactiveModel

#===#

const JS_APP_VAR_NAME = "__stipple_app"
const JS_SCRIPT_NAME = "__stipple_app.js"

#===#

abstract type ReactiveModel end

#===#

include("Elements.jl")
include("Layout.jl")

#===#

function update!(app::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  v = getfield(app, field)

  if isa(v, Reactive)
    v[] = newval
  else
    setfield!(app, field, newval)
  end

  app
end

#===#

function Genie.Router.channel(app::M; channel::String = Genie.config.webchannels_default_route)::Genie.Router.Channel where {M<:ReactiveModel}
  Genie.Router.channel("/$channel/watchers") do
    try
      payload = Genie.Router.@params(:payload)["payload"]

      payload["newval"] == payload["oldval"] && return nothing

      field = Symbol(payload["field"])
      val = getfield(app, field)

      valtype = isa(val, Reactive) ? typeof(val[]) : typeof(val)

      newval = parse(valtype, string(payload["newval"]))
      oldval = parse(valtype, string(payload["oldval"]))

      update!(app, field, newval, oldval)

      "OK"
    catch ex
      @error ex
      "ERROR : 500 - $ex"
    end
  end
end

function Genie.Router.route(app::M; name::String = JS_APP_VAR_NAME, endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::Genie.Router.Route where {M<:ReactiveModel}
  r = Genie.Router.route("/$endpoint") do
    Stipple.Elements.vue_integration(app, name = name, endpoint = endpoint, channel = channel) |> Genie.Renderer.Js.js
  end

  Genie.WebChannels.unsubscribe_disconnected_clients()

  r
end

function init(app::M; name::String = JS_APP_VAR_NAME, endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  Genie.Router.channel(app, channel = channel)
  Genie.Router.route(app, name = name, endpoint = endpoint, channel = channel)

  attach_default_handlers(app)

  app
end

function attach_default_handlers(model::M)::Nothing where {M<:ReactiveModel}
  for f in fieldnames(typeof(model))
    isa(getproperty(model, f), Reactive) || continue

    on(getproperty(model, f)) do v
      push!(model, f => getfield(model, f))
    end
  end

  nothing
end

#===#

function Base.push!(app::M, vals::Pair{Symbol,T}; channel::String = Genie.config.webchannels_default_route) where {T,M<:ReactiveModel}
  Genie.WebChannels.broadcast(channel, Genie.Renderer.Json.JSONParser.json(Dict("key" => vals[1], "value" => vals[2])))
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}}) where {T,M<:ReactiveModel}
  push!(app, vals[1] => vals[2][])
end

end