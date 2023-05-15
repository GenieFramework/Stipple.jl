"""
# Stipple.Layout

Utilities for rendering the general layout of a Stipple app, such as of a data dashboard web page or supporting themes.
"""
module Layout

using Genie, Stipple

export layout
export page, app, row, column, cell, container

export theme
const THEMES = Function[]

"""
    function layout(output::Union{String,Vector}; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                      head_content::String = "", channel::String = Genie.config.webchannels_default_route) :: String

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
function layout(output::Union{S,Vector}, m::M;
                partial::Bool = false, title::String = "", class::String = "", style::String = "", head_content::String = "",
                channel::String = Stipple.channel_js_name,
                core_theme::Bool = true)::ParsedHTMLString where {M<:ReactiveModel, S<:AbstractString}

  isa(output, Vector) && (output = join(output, '\n'))

  content = [
    output
    theme(; core_theme)
    Stipple.deps(m; core_theme)
  ]

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
    function page(elemid, args...; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                    channel::String = Genie.config.webchannels_default_route , head_content::String = "", kwargs...)

Generates the HTML code corresponding to an SPA (a single page application), defining the root element of the Vue app.

### Example

```julia
julia> page(:elemid, [
        span("Hello", @text(:greeting))
        ])
"<!DOCTYPE html>\n<html><head><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui\" /></head><body class style><link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><div id=elemid><span v-text='greeting'>Hello</span></div><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.js\"></script><script src=\"/js/quasar.umd.min.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script></body></html>"
```
"""
function page(model::M, args...;
              partial::Bool = false, title::String = "", class::String = "container", style::String = "",
              channel::String = Genie.config.webchannels_default_route, head_content::String = "",
              prepend::Union{S,Vector} = "", append::Union{T,Vector} = [],
              core_theme::Bool = true, kwargs...)::ParsedHTMLString where {M<:Stipple.ReactiveModel, S<:AbstractString,T<:AbstractString}

  layout(
    [
      join(prepend)
      Genie.Renderer.Html.div(id = vm(M), args...; class = class, kwargs...)
      join(append)
    ], model;
    partial = partial, title = title, style = style, head_content = head_content, channel = channel,
    core_theme = core_theme)
end

const app = page


function container(args...; fluid = false, kwargs...)
  cssclass = fluid ? "container-fluid" : "container"
  kwargs = NamedTuple(Dict{Symbol,Any}(kwargs...), :class, cssclass)

  Genie.Renderer.Html.div(args...; kwargs...)
end


"""
    function row(args...; kwargs...)

Creates a `div` HTML element with a CSS class named `row`. This works with Stipple's core layout and with [Quasar's Flex Grid](https://quasar.dev/layout/grid/introduction-to-flexbox) to create the
responsive CSS grid of the web page. The `row()` function creates rows which should include [`cell`](@ref)s.

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
    function column(args...; kwargs...)

Creates a `div` HTML element with a CSS class named `column`. This works with [Quasar's Flex Grid](https://quasar.dev/layout/grid/introduction-to-flexbox) to create the
responsive CSS grid of the web page. The `row()` function creates rows which should include [`cell`](@ref)s.

### Example

```julia
julia> column(span("Hello"))
"<div class=\"column\"><span>Hello</span></div>"
```
"""
function column(args...; kwargs...)
  kwargs = NamedTuple(Dict{Symbol,Any}(kwargs...), :class, "column")

  Genie.Renderer.Html.div(args...; kwargs...)
end

"""
    function cell(args...; size::Int=0, xs::Int=0, sm::Int=0, md::Int=0, lg::Int=0, xl::Int=0, kwargs...)

Creates a `div` HTML element with Quasar flex grid CSS class named `col`.
If size is specified, the class `col-\$size` is added instead.
[Quasar's Flex Grid](https://quasar.dev/layout/grid/introduction-to-flexbox) supports the following values for size arguments:
- Integer values between `0` and `12`; `0` means no specification
- AbStractString values `"1"` - `"12"`, `""` or `"auto"`; `""` means no specification, `"auto"` means height/width from content
If tag classes (`xs`, `sm`, `md`, `lg`, `xl`) are specified, the respective classes `col-\$tag-\$md` are added, e.g. `col-sm-6`.
The `cell`s should be included within `row`s or `column`s.

### Example

```julia
julia> row(cell(size = 2, md = 6, sm = 12, span("Hello")))
"<div class=\"row\"><div class=\"col-2 col-sm-12 col-md-6\"><span>Hello</span></div></div>"
```
"""
function cell(args...; size::Union{Int,AbstractString} = 0,
  xs::Union{Int,AbstractString} = 0, sm::Union{Int,AbstractString} = 0, md::Union{Int,AbstractString} = 0,
  lg::Union{Int,AbstractString} = 0, xl::Union{Int,AbstractString} = 0, kwargs...)

  colclass = join([sizetocol(size, tag) for (size, tag) in [(size, ""), (xs, "xs"), (sm, "sm"), (md, "md"), (lg, "lg"), (xl, "xl")] if length(tag) == 0 || size != 0], ' ')

  kwargs = NamedTuple(Dict{Symbol,Any}(kwargs...), :class, colclass)

  Genie.Renderer.Html.div(args...; kwargs...)
end

function sizetocol(size::Union{String, Int} = 0, tag::String = "")
  out = ["col"]
  length(tag) > 0 && push!(out, tag)
  if size isa Int
    size > 0 && push!(out, "$size")
  else
    length(size) > 0 && push!(out, size)
  end
  length(tag) > 0 && length(out) == 2 ? "" : join(out, '-')
end

"""
    function theme() :: String

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
function theme(; core_theme::Bool = true) :: Vector{String}
  output = String[]

  if core_theme
    push!(output,
      stylesheet("https://fonts.googleapis.com/css?family=Material+Icons"),
      stylesheet(Genie.Assets.asset_path(Stipple.assets_config, :css, file="stipplecore"))
    )
  end

  for f in THEMES
    push!(output, f()...)
  end

  output
end


end
