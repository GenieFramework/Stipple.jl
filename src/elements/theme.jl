
# try
#   Core.eval(Genie.Renderer.Html, :(function theme end))
# catch ex
#   @error ex
# end

function theme() :: String
  string(
    Stipple.Renderer.Html.stylesheet("/css/stipple/bootstrap.min.css")
  )
end