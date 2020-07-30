module Layout

using Revise
import Genie
using Stipple

export layout


function layout(output::Union{String,Vector}; partial::Bool = false, title::String = "", class::String = "", style::String = "") :: String
  isa(output, Vector) && (output = join(output, '\n'))

  content = string(
    theme(),
    output,
    Stipple.deps()
  )

  partial && return content

  Genie.Renderer.Html.doc(
    Genie.Renderer.Html.html([
      Genie.Renderer.Html.head([
        Genie.Renderer.Html.title(title)
        Genie.Renderer.Html.meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui")
      ])
      Genie.Renderer.Html.body(content, class=class, style=style)
    ])
  )
end

include(joinpath("layout", "page.jl"))
include(joinpath("layout", "theme.jl"))

end