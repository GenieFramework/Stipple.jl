function stylesheet(href::String; args...) :: String
  Genie.Renderer.Html.link(href=href, rel="stylesheet", args...)
end