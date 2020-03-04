function theme() :: String
  string(
    Stipple.Renderer.Html.stylesheet("/css/stipple/bootstrap.min.css")
  )
end