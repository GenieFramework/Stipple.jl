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

function render end

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")
include("Components.jl")

#===#

function update!(app::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  update!(app, getfield(app, field), newval, oldval)
end

function update!(app::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  field[] = newval

  app
end

function update!(app::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  setfield!(app, field, newval)

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

#===#

function Stipple.render(app::M)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    result[string(field)] = Stipple.render(getfield(app, field), field)
  end

  Dict(:el => Elements.elem(app), :data => result)
end

function Stipple.render(val::T, fieldname::Symbol) where {T}
  val
end

function Stipple.render(o::Reactive{T}, fieldname::Symbol) where {T}
  Stipple.render(o[], fieldname)
end

#===#

end