module Elements

using Revise
import Genie
using Stipple

#===#

function root(app::M)::String where {M<:ReactiveModel}
  Genie.Generator.validname(typeof(app) |> string)
end

function elem(app::M)::String where {M<:ReactiveModel}
  "#$(root(app))"
end

#===#

function vue_integration(model::M; vue_app_name::String, endpoint::String, channel::String)::String where {M<:ReactiveModel}
  vue_app = replace(Genie.Renderer.Json.JSONParser.json(model |> Stipple.render), "\"{" => " {")
  vue_app = replace(vue_app, "}\"" => "} ")

  output = "var $vue_app_name = new Vue($vue_app);\n\n"

  for field in fieldnames(typeof(model))
    output *= Stipple.watch(vue_app_name, getfield(model, field), field, channel, model)
  end

  output *= "\n\nwindow.parse_payload = function(payload){ window.$(vue_app_name)[payload.key] = payload.value; };"
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