# try
#   Core.eval(Genie.Renderer.Html, :(function stylesheet end))
# catch ex
#   @error ex
# end

function stylesheet(href::String; args...) :: String
  Genie.Renderer.Html.link(href=href, rel="stylesheet", args...)
end