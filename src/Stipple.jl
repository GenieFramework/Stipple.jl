module Stipple

using Revise
using Logging, Reexport

import Genie
@reexport using Observables
const Reactive = Observables.Observable
const R = Reactive

export R, Reactive, ReactiveModel

#===#

abstract type ReactiveModel end

#===#

const JS_APP_VAR_NAME = "__stipple_app"
const JS_SCRIPT_NAME = "__stipple_app.js"

#===#

include("Elements.jl")
include("Layout.jl")
include("Components.jl")

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

Base.parse(::Type{String}, v::String) = v
Base.parse(::Type{Int}, v::Int) = v
Base.parse(::Type{Float64}, v::Float64) = v


function init(model::Type{M}, ui::Union{String,Vector} = ""; name::String = JS_APP_VAR_NAME, endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  Genie.config.websockets_server = true
  app = model()

  Genie.Router.channel("/$channel/watchers") do
    try
      payload = Genie.Router.@params(:payload)["payload"]

      payload["newval"] == payload["oldval"] && return nothing

      field = Symbol(payload["field"])
      val = getfield(app, field)

      valtype = isa(val, Reactive) ? typeof(val[]) : typeof(val)

      newval = parse(valtype, payload["newval"])
      oldval = parse(valtype, payload["oldval"])

      update!(app, field, newval, oldval)

      "OK"
    catch ex
      @error ex
      "ERROR : 500 - $ex"
    end
  end

  Genie.Router.route("/$endpoint") do
    Genie.WebChannels.unsubscribe_disconnected_clients()
    Stipple.Elements.vue_integration(model, name = name, endpoint = endpoint, channel = channel) |> Genie.Renderer.Js.js
  end

  # Genie.Router.route("/") do
  #   Genie.Renderer.Html.html(Stipple.Layout.layout(join(ui)))
  # end

  setup(app)
end


function setup(model::M)::M where {M<:ReactiveModel}
  for f in fieldnames(typeof(model))
    isa(getproperty(model, f), Reactive) || continue

    on(getproperty(model, f)) do v
      push!(model, f => getfield(model, f))
    end
  end

  model
end

#===#

function Base.push!(app::M, vals::Pair{Symbol,T}; channel::String = Genie.config.webchannels_default_route) where {T,M<:ReactiveModel}
  Genie.WebChannels.broadcast(channel, Genie.Renderer.Json.JSONParser.json(Dict("key" => vals[1], "value" => vals[2])))
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}}) where {T,M<:ReactiveModel}
  push!(app, vals[1] => vals[2][])
end

end