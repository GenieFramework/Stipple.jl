module Elements

using Revise
import Genie
using Stipple

#===#

const MOUNT_ELEM = "__stipple_app_elem"

function elem(app::M)::String where {M<:ReactiveModel}
  "#$MOUNT_ELEM"
end

#===#

function vue_integration(model::Type{M}; name::String = Stipple.JS_APP_VAR_NAME, endpoint::String = Stipple.JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::String where {M<:ReactiveModel}
  vue_app = replace(Genie.Renderer.Json.JSONParser.json(model() |> Stipple.render), "\"{" => " {")
  vue_app = replace(vue_app, "}\"" => "} ")

  output = "var $name = new Vue($vue_app);"

  for field in fieldnames(model)
    output *= string(name, raw".\$watch('", field, "', function(newVal, oldVal){
      Genie.WebChannels.sendMessageTo('$channel', 'watchers', {'payload': {'field':'$field', 'newval': newVal, 'oldval': oldVal}});
    });")
  end

  output *= "window.parse_payload = function(payload){ window.$(Stipple.JS_APP_VAR_NAME)[payload.key] = payload.value; };"
end

#===#

function deps() :: String
  Genie.Router.route("/js/stipple/vue.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "vue.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/quasar.umd.min.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "quasar.umd.min.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  string(
    Genie.Assets.channels_support(),
    Genie.Renderer.Html.script(src="/js/stipple/vue.js"),
    Genie.Renderer.Html.script(src="/js/stipple/quasar.umd.min.js"),
    Genie.Renderer.Html.script(src="/$(Stipple.JS_SCRIPT_NAME)?v=$(Genie.Configuration.isdev() ? rand() : 1)")
  )
end

#===#

macro iif(expr)
  "v-if='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro elsiif(expr)
  "v-else-if='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro els(expr)
  "v-else='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro text(expr)
  "v-text='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro react(expr)
  "v-model='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro data(expr)
  :(Symbol($expr))
end

#===#

include(joinpath("elements", "stylesheet.jl"))
include(joinpath("elements", "table.jl"))

end