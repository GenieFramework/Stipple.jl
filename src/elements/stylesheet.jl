export stylesheet

"""
    `function stylesheet(href::String; args...) :: String`

Generates the corresponding HTML `link` tag to reference the CSS stylesheet at `href`.

### Example

```julia
julia> stylesheet("https://fonts.googleapis.com/css?family=Material+Icons")
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" />"
```
"""
function stylesheet(href::String; args...) :: String
  Genie.Renderer.Html.link(href=href, rel="stylesheet", args...)
end