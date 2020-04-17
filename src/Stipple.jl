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
function update! end
function watch end

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")
include("Components.jl")

#===#

function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  update!(model, getfield(model, field), newval, oldval)
end

function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  field[] = newval

  model
end

function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  try
    setfield!(model, field, newval)
  catch ex
    @error ex
  end

  model
end

#===#

function watch(vue_app_name::String, fieldtype::Any, fieldname::Symbol, channel::String, model::M)::String where {M<:ReactiveModel}
  string(vue_app_name, raw".\$watch('", fieldname, "', function(newVal, oldVal){
    Genie.WebChannels.sendMessageTo('$channel', 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal}});
  });\n\n")
end

#===#

function Base.parse(::Type{T}, v::T) where {T}
  v::T
end

function init(model::Type{M}, ui::Union{String,Vector} = ""; vue_app_name::String = JS_APP_VAR_NAME, endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  Genie.config.websockets_server = true
  app = model()

  Genie.Router.channel("/$channel/watchers") do
    try
      payload = Genie.Router.@params(:payload)["payload"]

      payload["newval"] == payload["oldval"] && return nothing

      field = Symbol(payload["field"])
      val = getfield(app, field)

      valtype = isa(val, Reactive) ? typeof(val[]) : typeof(val)

      newval = payload["newval"]
      try
        newval = parse(valtype, payload["newval"])
      catch ex
        @error ex
      end

      oldval = payload["oldval"]
      try
        oldval = parse(valtype, payload["oldval"])
      catch ex
        @error ex
      end

      update!(app, field, newval, oldval)

      "OK"
    catch ex
      @error ex
      "ERROR : 500 - $ex"
    end
  end

  Genie.Router.route("/$endpoint") do
    Genie.WebChannels.unsubscribe_disconnected_clients()
    Stipple.Elements.vue_integration(model, vue_app_name = vue_app_name, endpoint = endpoint, channel = channel) |> Genie.Renderer.Js.js
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
  Genie.WebChannels.broadcast(channel, Genie.Renderer.Json.JSONParser.json(Dict("key" => vals[1], "value" => Stipple.render(vals[2]))))
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}}) where {T,M<:ReactiveModel}
  push!(app, vals[1] => vals[2][])
end

#===#

function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    result[string(field)] = Stipple.render(getfield(app, field), field)
  end

  Dict(:el => Elements.elem(app), :data => result)
end

function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  val
end

function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end

#===#

end