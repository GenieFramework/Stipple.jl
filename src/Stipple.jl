module Stipple

using Revise
using Logging, Reexport

import Genie
@reexport using Observables

#===#

const JS_APP_VAR_NAME = "__app"
const JS_SCRIPT_NAME = "__app.js"
const MOUNT_ELEM = "#app"

#===#

abstract type SyncedModel end

#===#

function elem(app::M)::String where {M<:SyncedModel}
  MOUNT_ELEM
end

#===#

function render(app::M)::Dict{Symbol,Any} where {M<:SyncedModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    result[string(field)] = render(getfield(app, field))
  end

  Dict(:el => elem(app), :data => result)
end

function render(val::T)::T where {T}
  val
end

function render(o::Observables.Observable{T})::T where {T}
  o[]
end

#===#

function update!(app::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:SyncedModel}
  v = getfield(app, field)

  if isa(v, Observables.Observable)
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

      valtype = isa(val, Observable) ? typeof(val[]) : typeof(val)

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
    output = """
      var $name = new Vue($(Genie.Renderer.Json.JSONParser.json(app |> render)))
    """

    for field in fieldnames(typeof(app))
      output *= """
        $name.\\\$watch('$field', function(newVal, oldVal) {
                      Genie.WebChannels.sendMessageTo('$channel', 'watchers', {'payload': {'field':'$field', 'newval': newVal, 'oldval': oldVal}});
                    });
      """
    end

    output *= """
    window.parse_payload = function(payload) {

    };
    """

    output |> Genie.Renderer.Js.js
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

function Base.push!(app::M, vals::Pair{Symbol,Observable{T}}) where {T,M<:SyncedModel}
  push!(app, vals[1] => vals[2][])
end

#===#

function deps() :: String
  """
  <script src="/js/stipple/vue.js"></script>
  <script src="$JS_SCRIPT_NAME?rand=$(Genie.Configuration.isdev() ? rand() : 0)"></script>
  """
end

end