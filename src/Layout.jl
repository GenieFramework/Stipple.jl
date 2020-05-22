module Layout

using Revise
import Genie
using Stipple


function layout(output::String; title="", class="", style="") :: String
  Genie.Renderer.Html.doc(
    Genie.Renderer.Html.html(() -> begin
      Genie.Renderer.Html.head() do
        Genie.Renderer.Html.title(title)
        Genie.Renderer.Html.meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui")
      end *
      Genie.Renderer.Html.body(
        string(theme(), output, Stipple.deps());
        class=class, style=style
      )
    end)
  )
end

function layout(output::Vector) :: String
  join(output, '\n') |> layout
end


include(joinpath("layout", "page.jl"))
include(joinpath("layout", "theme.jl"))

end