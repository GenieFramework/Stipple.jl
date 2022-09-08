"""
    const assets_config :: Genie.Assets.AssetsConfig

Manages the configuration of the assets (path, version, etc). Overwrite in order to customize:

### Example

```julia
Stipple.assets_config.package = "Foo"
```
"""
const assets_config = Genie.Assets.AssetsConfig(package = "Stipple.jl")

function Genie.Renderer.Html.attrparser(k::Symbol, v::JSONText) :: String
  if startswith(v.s, ":")
    ":$(k |> Genie.Renderer.Html.parseattr)=$(v.s[2:end]) "
  else
    "$(k |> Genie.Renderer.Html.parseattr)=$(v.s) "
  end
end