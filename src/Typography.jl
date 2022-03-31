"""
# Stipple.Typography

Typography utilities for Stipple apps.
"""
module Typography

import Genie

"""
    function header(args...; size::Int = 1, kwargs...)

Generates code for HTML headers (H1 to H6) based on `size` which include styling for Twitter Bootstrap, the CSS
  framework used by Stipple.

### Example

```julia
julia> Typography.header("Hello", size = 2)
"<h2 class=\"text-h2\">Hello</h2>"
```
"""
function header(args...; size::Int = 1, kwargs...)
  1 <= size <= 6 || error("Invalid header size - expected 1:6")
  func = getproperty(Genie.Renderer.Html, Symbol("h$size"))
  func(class="text-h$size", args...; kwargs...) |> ParsedHTMLString
end

end