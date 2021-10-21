
export theme

const THEMES = Function[]

"""
    `function theme() :: String

Provides theming support for Stipple apps and pages. It includes Stipple's default CSS files and additional elements,
  in the form of HTML tags, can be injected by pushing to the `Stipple.Layout.THEMES` collection.

### Example

```julia
julia> theme()
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" />"

julia> StippleUI.theme()
"<link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" />"

julia> push!(Stipple.Layout.THEMES, StippleUI.theme)
```
"""
function theme(; core_theme::Bool = true) :: String
  output = ""

  if core_theme
    if ! Genie.Assets.external_assets()
      Genie.Router.route(Genie.Assets.asset_path(package="Stipple.jl", version="master", type="css", file="stipplecore")) do
        Genie.Renderer.WebRenderable(
          read(Genie.Assets.asset_file(cwd=abspath(joinpath(@__DIR__, "..", "..")), type="css", file="stipplecore"), String),
          :css) |> Genie.Renderer.respond
      end
    end

    output *= string(
      Stipple.Elements.stylesheet("https://fonts.googleapis.com/css?family=Material+Icons"),
      Stipple.Elements.stylesheet(Genie.Assets.asset_path(package="Stipple.jl", version="master", type="css", file="stipplecore"))
    )
  end

  string(output, join([f() for f in THEMES], "\n"))
end