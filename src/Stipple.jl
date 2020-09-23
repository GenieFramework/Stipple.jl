module Stipple

using Logging, Reexport

using Genie
@reexport using Observables

const Reactive = Observables.Observable
const R = Reactive

export R, Reactive, ReactiveModel, @R_str
export newapp

#===#

abstract type ReactiveModel end

#===#

const JS_SCRIPT_NAME = "stipple.js"

#===#

function render end
function update! end
function watch end

function js_methods(m::Any)
  ""
end

#===#

const COMPONENTS = Dict()

function register_components(model::Type{M}, keysvals::Vector{Pair{K,V}}) where {M<:ReactiveModel, K, V}
  haskey(COMPONENTS, model) || (COMPONENTS[model] = Pair{K,V}[])
  push!(COMPONENTS[model], keysvals...)
end

#===#

function Observables.setindex!(observable::Observable, val, keys...; notify=(x)->true)
  count = 1
  observable.val = val

  for f in Observables.listeners(observable)
    if in(count, keys)
      count += 1
      continue
    end

    if notify(f)
      if f isa Observables.InternalFunction
        f(val)
      else
        Base.invokelatest(f, val)
      end
    end

    count += 1
  end

end

#===#

include("Typography.jl")
include("Elements.jl")
include("Layout.jl")
include("Generator.jl")

@reexport using .Typography
@reexport using .Elements
@reexport using .Layout
using .Generator

const newapp = Generator.newapp

#===#

function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  update!(model, getfield(model, field), newval, oldval)
end

function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  field[1] = newval

  model
end

function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  try
    setfield!(model, field, newval)
  catch ex
    # @error ex
  end

  model
end

#===#

function watch(vue_app_name::String, fieldtype::Any, fieldname::Symbol, channel::String, model::M)::String where {M<:ReactiveModel}
  string(vue_app_name, raw".\$watch('", fieldname, "', _.debounce(function(newVal, oldVal){
    Genie.WebChannels.sendMessageTo('$channel', 'watchers', {'payload': {'field':'$fieldname', 'newval': newVal, 'oldval': oldVal}});
  }, 300));\n\n")
end

#===#

function Base.parse(::Type{T}, v::T) where {T}
  v::T
end

function init(model::M, ui::Union{String,Vector} = ""; vue_app_name::String = Stipple.Elements.root(model), endpoint::String = JS_SCRIPT_NAME, channel::String = Genie.config.webchannels_default_route)::M where {M<:ReactiveModel}
  Genie.config.websockets_server = true

  Genie.Router.channel("/$channel/watchers") do
    try
      payload = Genie.Router.@params(:payload)["payload"]

      payload["newval"] == payload["oldval"] && return nothing

      field = Symbol(payload["field"])
      val = getfield(model, field)

      valtype = isa(val, Reactive) ? typeof(val[]) : typeof(val)

      newval = payload["newval"]
      try
        newval = Base.parse(valtype, payload["newval"])
      catch ex
        # @error ex
        # @error valtype, payload["newval"]
      end

      oldval = payload["oldval"]
      try
        oldval = Base.parse(valtype, payload["oldval"])
      catch ex
        # @error ex
        # @error valtype, payload["newval"]
      end

      update!(model, field, newval, oldval)

      "OK"
    catch ex
      # @error ex
    end
  end

  Genie.Router.route("/$endpoint") do
    Genie.WebChannels.unsubscribe_disconnected_clients()
    Stipple.Elements.vue_integration(model, vue_app_name = vue_app_name, endpoint = endpoint, channel = channel) |> Genie.Renderer.Js.js
  end

  setup(model)
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
  Genie.WebChannels.broadcast(channel, Genie.Renderer.Json.JSONParser.json(Dict("key" => julia_to_vue(vals[1]), "value" => Stipple.render(vals[2], vals[1]))))
end

function Base.push!(app::M, vals::Pair{Symbol,Reactive{T}}) where {T,M<:ReactiveModel}
  push!(app, Symbol(julia_to_vue(vals[1])) => vals[2][])
end

#===#

function components(m::Type{M}) where {M<:ReactiveModel}
  haskey(COMPONENTS, m) || return ""

  response = Dict(COMPONENTS[m]...) |> Genie.Renderer.Json.JSONParser.json
  replace(response, "\""=>"")
end

#===#

RENDERING_MAPPINGS = Dict{String,String}()
mapping_keys() = collect(keys(RENDERING_MAPPINGS))

function rendering_mappings(mappings = Dict{String,String})
  merge!(RENDERING_MAPPINGS, mappings)
end

function julia_to_vue(field, mapping_keys = mapping_keys())
  if in(string(field), mapping_keys)
    parts = split(RENDERING_MAPPINGS[string(field)], "-")

    if length(parts) > 1
      extraparts = map((x) -> uppercasefirst(string(x)), parts[2:end])
      string(parts[1], join(extraparts))
    else
      parts |> string
    end
  else
    field |> string
  end
end

function Stipple.render(app::M, fieldname::Union{Symbol,Nothing} = nothing)::Dict{Symbol,Any} where {M<:ReactiveModel}
  result = Dict{String,Any}()

  for field in fieldnames(typeof(app))
    result[julia_to_vue(field)] = Stipple.render(getfield(app, field), field)
  end

  Dict(:el => Elements.elem(app), :data => result, :components => components(typeof(app)), :methods => "{ $(js_methods(app)) }")
end

function Stipple.render(val::T, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  val
end

function Stipple.render(o::Reactive{T}, fieldname::Union{Symbol,Nothing} = nothing) where {T}
  Stipple.render(o[], fieldname)
end

#===#

const DEPS = Function[]

function deps() :: String
  Genie.Router.route("/js/stipple/vue.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "vue.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/vue_filters.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "vue_filters.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/underscore-min.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "underscore-min.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  Genie.Router.route("/js/stipple/stipplecore.js") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "files", "js", "stipplecore.js"), String),
      :javascript) |> Genie.Renderer.respond
  end

  string(
    Genie.Assets.channels_support(),
    Genie.Renderer.Html.script(src="/js/stipple/underscore-min.js"),
    Genie.Renderer.Html.script(src="/js/stipple/vue.js"),
    join([f() for f in DEPS], "\n"),
    Genie.Renderer.Html.script(src="/js/stipple/stipplecore.js"),
    Genie.Renderer.Html.script(src="/js/stipple/vue_filters.js"),

    # if the model is not configured and we don't generate the stipple.js file, no point in requesting it
    (in(Symbol("get_$(Stipple.JS_SCRIPT_NAME)"), Genie.Router.named_routes() |> keys |> collect) ?
      string(
        Genie.Renderer.Html.script("Stipple.init({theme: 'stipple-blue'});"),
        Genie.Renderer.Html.script(src="/$(Stipple.JS_SCRIPT_NAME)?v=$(Genie.Configuration.isdev() ? rand() : 1)")
      ) : ""
    )
  )
end

#===#

function camelcase(s::String) :: String
  replacements = [replace(s, r.match=>uppercase(r.match[2:end])) for r in eachmatch(r"_.", s) |> collect] |> unique
  isempty(replacements) ? s : first(replacements)
end

function Core.NamedTuple(kwargs::Dict) :: NamedTuple
  NamedTuple{Tuple(keys(kwargs))}(collect(values(kwargs)))
end

function Core.NamedTuple(kwargs::Dict, property::Symbol, value::String) :: NamedTuple
  value = "$value $(get!(kwargs, property, ""))" |> strip
  kwargs = delete!(kwargs, property)
  kwargs[property] = value

  NamedTuple(kwargs)
end

macro R_str(s)
  :(Symbol($s))
end

end
