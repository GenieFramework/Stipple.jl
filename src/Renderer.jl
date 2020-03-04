module Renderer

using Revise
import Genie
using Stipple

#===#

const MOUNT_ELEM = "#app"

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

function render(o::Synced{T})::T where {T}
  o[]
end

#===#

function vue_integration(app::M; name::String = Stipple.JS_APP_VAR_NAME, endpoint::String = Stipple.JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::String where {M<:SyncedModel}
  output = "var $name = new Vue($(Genie.Renderer.Json.JSONParser.json(app |> render)));"

  for field in fieldnames(typeof(app))
    output *= string(name, raw".\$watch('", field, "', function(newVal, oldVal){
      Genie.WebChannels.sendMessageTo('$channel', 'watchers', {'payload': {'field':'$field', 'newval': newVal, 'oldval': oldVal}});
    });")
  end

  output *= raw"window.parse_payload = function(payload){};"
end

function deps() :: String
  string(
    Genie.Assets.channels_support(),
    Genie.Renderer.Html.script(src="/js/stipple/vue.js"),
    Genie.Renderer.Html.script(src="$(Stipple.JS_SCRIPT_NAME)?v=$(Genie.Configuration.isdev() ? rand() : 1)")
  )
end


module Html

import Genie
using Stipple

include(joinpath("elements", "stylesheet.jl"))
include(joinpath("elements", "theme.jl"))

end

end