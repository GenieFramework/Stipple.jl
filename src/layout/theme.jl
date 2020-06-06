
export theme

const THEMES = Function[]

function theme() :: String
  Genie.Router.route("/css/stipple/stipple.css") do
    Genie.Renderer.WebRenderable(
      read(joinpath(@__DIR__, "..", "..", "files", "css", "stipple.css"), String),
      :css) |> Genie.Renderer.respond
  end

  string(
    Stipple.Elements.stylesheet("https://fonts.googleapis.com/css?family=Roboto:100,300,400,500,700,900|Material+Icons"),
    Stipple.Elements.stylesheet("/css/stipple/stipple.css"),
    join([f() for f in THEMES], "\n")
  )
end