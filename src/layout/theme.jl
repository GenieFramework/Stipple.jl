const THEMES = Function[]

function theme() :: String
  Genie.Router.route("/css/stipple/bootstrap.min.css") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "..", "files", "css", "bootstrap.min.css"), String),
      :css) |> Genie.Renderer.respond
  end

  Genie.Router.route("/css/stipple/bootstrap.min.css.map") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "..", "files", "css", "bootstrap.min.css.map"), String),
      :css) |> Genie.Renderer.respond
  end

  string(
    Stipple.Elements.stylesheet("/css/stipple/bootstrap.min.css"),
    Stipple.Elements.stylesheet("https://fonts.googleapis.com/css?family=Roboto:100,300,400,500,700,900|Material+Icons"),
    join([f() for f in THEMES], "\n")
  )
end