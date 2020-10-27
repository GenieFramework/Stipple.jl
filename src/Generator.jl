module Generator

using Pkg
using Genie, Genie.Generator

function newapp(app_name::String; ui::Bool = true, charts::Bool = true, autostart::Bool = true, kwargs...)
  Genie.Generator.newapp(app_name; autostart = false, kwargs...)

  ui && Pkg.add("StippleUI")
  charts && Pkg.add("StippleCharts")

  autostart && Genie.up()
end

function scaffold(app_name::String)
  clean_name = Genie.Generator.validname(app_name)
  type_name = "$(uppercasefirst(clean_name))Model"
  var_name = "$(lowercase(clean_name))_model"

  Pkg.activate(".")
  Pkg.add("Revise")
  Pkg.add("Stipple")
  Pkg.add("StippleUI")
  Pkg.add("StippleCharts")

  open("$clean_name.jl", "w") do io
    write(io,
    """
    __revise_mode__ = :eval
    using Revise
    using Stipple
    using StippleUI
    using StippleCharts

    using GenieAutoReload
    GenieAutoReload.autoreload(pwd())

    #= Data =#

    Base.@kwdef mutable struct $type_name <: ReactiveModel
      # add fields here
      x::R{Int} = 100
      y::R{String} = "Hello"
    end

    #= Stipple setup =#

    Stipple.register_components($type_name, StippleCharts.COMPONENTS)
    $var_name = Stipple.init($type_name())

    #= Event handlers =#

    onany($var_name.x, $var_name.y) do (_...)
      # handle update events
      @show $var_name.x[] $var_name.y[]
    end

    #= UI =#

    function ui(model::$type_name)
    [
      dashboard(
        vm(model), class="container", title="$app_name", head_content=Genie.Assets.favicon_support(),
        [
          heading("$app_name")

          row([
            cell(class="st-module", [
              h6("X")
              span("", @text(:x))
            ])
            cell(class="st-module", [
              h6("Y")
              span("", @text(:y))
            ])
          ])

          footer(class="st-footer q-pa-md", [
            cell([
              span("$app_name")
            ])
          ])
        ]
      )
      GenieAutoReload.assets()
    ]
    end

    #= routing =#

    route("/") do
      ui($var_name) |> html
    end

    #= start server =#
    # up(rand((8000:9000)), open_browser=true)
    """)
  end
end

end