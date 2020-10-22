module Elements

import Genie
using Stipple

import Genie.Renderer.Html: HTMLString, normal_element

export root, elem, vm, @iif, @elsiif, @els, @text, @bind, @data, @click, @on

#===#

function root(app::M)::String where {M<:ReactiveModel}
  Genie.Generator.validname(typeof(app) |> string)
end

function root(app::Type{M})::String where {M<:ReactiveModel}
  Genie.Generator.validname(app |> string)
end

function elem(app::M)::String where {M<:ReactiveModel}
  "#$(root(app))"
end

const vm = root

#===#

function vue_integration(model::M; vue_app_name::String, endpoint::String, channel::String, debounce::Int)::String where {M<:ReactiveModel}
  vue_app = replace(Genie.Renderer.Json.JSONParser.json(model |> Stipple.render), "\"{" => " {")
  vue_app = replace(vue_app, "}\"" => "} ")
  vue_app = replace(vue_app, "\\\\" => "\\")

  output = "var $vue_app_name = new Vue($vue_app);\n\n"

  for field in fieldnames(typeof(model))
    output *= Stipple.watch(vue_app_name, getfield(model, field), field, channel, debounce, model)
  end

  output *= """

    window.parse_payload = function(payload){
      if (payload.key) {
        let ww = [];
        window.$(vue_app_name)._watchers.forEach( (w) => { if (w.expression == payload.key) { ww.push(w) } } );

        const watchers = ww.map((watcher) => ({ cb: watcher.cb, sync: watcher.sync }));

        for (let index in ww) {
          ww[index].cb = () => null;
          ww[index].sync = true
        }

        window.$(vue_app_name)[payload.key] = payload.value;
        window.console.log("ws update: ", payload.key + ': ' + payload.value);

        for (let index in ww) {
          ww[index].cb = watchers[index].cb;
          ww[index].sync = watchers[index].sync
        }
      } else {
        window.console.log("ws update: ", payload)
      }
    }
    """
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
  directive = occursin(" | ", string(expr)) ? ":text-content.prop" : "v-text"
  "$(directive)='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro bind(expr)
  "v-model='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro data(expr)
  :(Symbol($expr))
end

macro click(expr)
  "@click='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

macro on(args, expr)
  "v-on:$(string(args))='$(startswith(string(expr), ":") ? string(expr)[2:end] : expr)'"
end

#===#

include(joinpath("elements", "stylesheet.jl"))

end
