module Layout

using Revise
import Genie
using Stipple


function layout(output::Vector)
  Genie.Renderer.Html.doc(
    Genie.Renderer.Html.html(() -> begin
      Genie.Renderer.Html.head() *
      Genie.Renderer.Html.body(join(output, '\n'))
    end)
  )
end


include(joinpath("layout", "page.jl"))
include(joinpath("layout", "theme.jl"))

end