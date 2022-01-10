"""
# Stipple.Layout

Utilities for rendering the general layout of a Stipple app, such as of a data dashboard web page or supporting themes.
"""
module Layout

using Genie, Stipple

export layout
export page, row, cell

export theme
const THEMES = Function[]

"""
    `function layout(output::Union{String,Vector}; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                      head_content::String = "", channel::String = Genie.config.webchannels_default_route) :: String`

Utility for creating a basic web page structure, including doctype as well as <HTML>, <HEAD>, <TITLE>, <META viewport>,
  and <BODY> tags, together with the output content.

If `partial` is `true`, the page layout HTML elements are not returned.

### Examples

```julia
julia> layout([
        span("Hello", @text(:greeting))
        ])
"<!DOCTYPE html>\n<html><head><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui\" /></head><body class style><link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><span v-text='greeting'>Hello</span><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.js\"></script><script src=\"/js/quasar.umd.min.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script></body></html>"
```

```julia
julia> layout([
        span("Hello", @text(:greeting))
        ], partial = true)
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><span v-text='greeting'>Hello</span><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.js\"></script><script src=\"/js/quasar.umd.min.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script>"
```
"""
function layout(output::Union{S,Vector}; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                head_content::String = "", channel::String = Genie.config.webchannels_default_route,
                core_theme::Bool = true)::ParsedHTMLString where {S<:AbstractString}

  isa(output, Vector) && (output = join(output, '\n'))

  content = string(
    output,
    theme(; core_theme = core_theme),
    Stipple.deps(channel; core_theme = core_theme)
  )

  partial && return content

  Genie.Renderer.Html.doc(
    Genie.Renderer.Html.html([
      Genie.Renderer.Html.head([
        Genie.Renderer.Html.title(title)
        Genie.Renderer.Html.meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no")
        head_content
      ])
      Genie.Renderer.Html.body(content, class=class, style=style)
    ])
  )
end


"""
    `function page(elemid, args...; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                    channel::String = Genie.config.webchannels_default_route , head_content::String = "", kwargs...)`

Generates the HTML code corresponding to an SPA (a single page application), defining the root element of the Vue app.

### Example

```julia
julia> page(:elemid, [
        span("Hello", @text(:greeting))
        ])
"<!DOCTYPE html>\n<html><head><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui\" /></head><body class style><link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><div id=elemid><span v-text='greeting'>Hello</span></div><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.js\"></script><script src=\"/js/quasar.umd.min.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script></body></html>"
```
"""
function page(elemid, args...; partial::Bool = false, title::String = "", class::String = "container", style::String = "",
              channel::String = Genie.config.webchannels_default_route, head_content::String = "",
              prepend::Union{S,Vector} = "", append::Union{T,Vector} = [],
              core_theme::Bool = true, kwargs...)::ParsedHTMLString where {S<:AbstractString,T<:AbstractString}

  layout(
    [
      join(prepend)
      Genie.Renderer.Html.div(id = elemid, args...; class = class, kwargs...)
      join(append)
    ],
    partial = partial, title = title, style = style, head_content = head_content, channel = channel,
    core_theme = core_theme)
end
function page(model::T, args...; kwargs...)::ParsedHTMLString where {T<:Stipple.ReactiveModel}
  page(vm(model), args...; channel = getchannel(model), kwargs...)
end

"""
    `function row(args...; kwargs...)`

Creates a `div` HTML element with a CSS class named `row`. This works with Stipple's Twitter Bootstrap to create the
responsive CSS grid of the web page. The `row` function creates rows which should include `cell`s.

### Example

```julia
julia> row(span("Hello"))
"<div class=\"row\"><span>Hello</span></div>"
```
"""
function row(args...; kwargs...)
  kwargs = NamedTuple(Dict{Symbol,Any}(kwargs...), :class, "row")

  Genie.Renderer.Html.div(args...; kwargs...)
end

"""
    `function cell(args...; size::Int=0, kwargs...)`

Creates a `div` HTML element with CSS classes named `col col-12` and `col-sm-$size`.
This works with Stipple's Twitter Bootstrap to create the responsive CSS grid of the web page. The `cell`s should be
included within `row`s.

### Example

```julia
julia> row(cell(size=2, span("Hello")))
"<div class=\"row\"><div class=\"col col-12 col-sm-2\"><span>Hello</span></div></div>"
```
"""
function cell(args...; size::Union{Int,AbstractString} = 0, kwargs...)
  isa(size, AbstractString) && (size = parse(Int, size))

  kwargs = NamedTuple(Dict{Symbol,Any}(kwargs...), :class, "col col-12 col-sm$(size > 0 ? "-$size" : "")")

  Genie.Renderer.Html.div(args...; kwargs...)
end


"""
    `function theme() :: String

Provides theming support for Stipple apps and pages. It includes Stipple's default CSS files and additional elements,
  in the form of HTML tags, can be injected by pushing to the `Stipple.Layout.THEMES` collection.

### Example

```julia
julia> theme()
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" />"

julia> StippleUI.theme()
"<link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" />"

julia> push!(Stipple.Layout.THEMES, StippleUI.theme)
```
"""
function theme(; core_theme::Bool = true) :: String
  if core_theme
    if ! Genie.Assets.external_assets(Stipple.assets_config)
      Genie.Router.route(Genie.Assets.asset_path(Stipple.assets_config, :css, file="stipplecore")) do
        Genie.Renderer.WebRenderable(
          Genie.Assets.embedded(Genie.Assets.asset_file(cwd=dirname(@__DIR__), type="css", file="stipplecore")),
          :css) |> Genie.Renderer.respond
      end
    end

    output = string(
      stylesheet("https://fonts.googleapis.com/css?family=Material+Icons"),
      stylesheet(Genie.Assets.asset_path(Stipple.assets_config, :css, file="stipplecore"))
    )
  end

  string(output, join([f() for f in THEMES], "\n")) |> ParsedHTMLString
end


end
