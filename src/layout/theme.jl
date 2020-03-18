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
    Stipple.Elements.stylesheet("/css/stipple/bootstrap.min.css")
  )
end