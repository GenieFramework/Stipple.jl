module Stipple

using Revise
using Logging, Reexport

import Genie
@reexport using Observables
const Synced = Observables.Observable

export Synced, SyncedModel

#===#

const JS_APP_VAR_NAME = "__app"
const JS_SCRIPT_NAME = "__app.js"

#===#

abstract type SyncedModel end

#===#

include("Elements.jl")
include("Layout.jl")

#===#

function update!(app::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:SyncedModel}
  v = getfield(app, field)

  if isa(v, Synced)
    v[] = newval
  else
    setfield!(app, field, newval)
  end

  app
end

#===#

function Genie.Router.channel(app::M; channel::String = Genie.config.webchannels_default_route)::Genie.Router.Channel where {M<:SyncedModel}
  Genie.Router.channel("/$channel/watchers") do
    try
      payload = Genie.Router.@params(:payload)["payload"]

      payload["newval"] == payload["oldval"] && return nothing

      field = Symbol(payload["field"])
      val = getfield(app, field)

      valtype = isa(val, Synced) ? typeof(val[]) : typeof(val)

      newval = parse(valtype, payload["newval"])
      oldval = parse(valtype, string(payload["oldval"]))

      update!(app, field, newval, oldval)

      "OK"
    catch ex
      @error ex

      "ERROR : 500 - $ex"
    end
  end
end

function Genie.Router.route(app::M; name::String = JS_APP_VAR_NAME, endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::Genie.Router.Route where {M<:SyncedModel}
  r = Genie.Router.route("/$endpoint") do
    Stipple.Renderer.vue_integration(app, name = name, endpoint = endpoint, channel = channel) |> Genie.Renderer.Js.js
  end
end

function setup(app::M; name::String = JS_APP_VAR_NAME, endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::M where {M<:SyncedModel}
  Genie.Router.channel(app, channel = channel)
  Genie.Router.route(app, name = name, endpoint = endpoint, channel = channel)

  app
end

#===#

function Base.push!(app::M, vals::Pair{Symbol,T}; channel::String = Genie.config.webchannels_default_route) where {T,M<:SyncedModel}
  Genie.WebChannels.broadcast(channel, Genie.Renderer.Json.JSONParser.json(Dict("key" => vals[1], "value" => vals[2])))
end

function Base.push!(app::M, vals::Pair{Symbol,Synced{T}}) where {T,M<:SyncedModel}
  push!(app, vals[1] => vals[2][])
end

end