module Layout

using Revise
import Genie
using Stipple

export layout


function layout(output::Union{String,Vector}; title="", class="", style="") :: String
  isa(output, Vector) && (output = join(output, '\n'))

  Genie.Renderer.Html.doc(
    Genie.Renderer.Html.html([
      Genie.Renderer.Html.head([
        Genie.Renderer.Html.title(title)
        Genie.Renderer.Html.meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui")
      ])
      Genie.Renderer.Html.body([
        theme()
        output
        Stipple.deps()
      ], class=class, style=style
      )
    ])
  )
end

include(joinpath("layout", "page.jl"))
include(joinpath("layout", "theme.jl"))

end