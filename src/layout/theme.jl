
export theme

const THEMES = Function[]

function theme() :: String
  Genie.Router.route("/css/stipple/stipplecore.min.css") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "..", "files", "css", "stipplecore.min.css"), String),
      :css) |> Genie.Renderer.respond
  end

  string(
    Stipple.Elements.stylesheet("https://fonts.googleapis.com/css?family=Material+Icons"),
    Stipple.Elements.stylesheet("https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap"),
    Stipple.Elements.stylesheet("/css/stipple/stipplecore.min.css"),
    join([f() for f in THEMES], "\n")
  )
end