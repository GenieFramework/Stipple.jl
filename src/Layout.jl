"""
# Stipple.Layout

Utilities for rendering the general layout of a Stipple app, such as of a data dashboard web page or supporting themes.
"""
module Layout

using Genie, Stipple

export layout, add_css, remove_css
export page, app, row, column, cell, container, flexgrid_kwargs, htmldiv

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
                partial::Bool = false, title::String = "", class::String = "", style::String = "", head_content::Union{AbstractString, Vector{<:AbstractString}} = "",
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
        join(head_content)
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
              channel::String = Genie.config.webchannels_default_route, head_content::Union{AbstractString, Vector{<:AbstractString}} = "",
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

function flexgrid_kwargs(; class = "", class! = nothing, symbol_class::Bool = true, flexgrid_mappings::Dict{Symbol,Symbol} = Dict{Symbol,Symbol}(), kwargs...)
  kwargs = Dict{Symbol,Any}(kwargs...)

  # support all different types of classes that vue supports: String, Expressions (Symbols), Arrays, Dicts
  # todo check if vector contains only strings ...
  if class! !== nothing
    class = if class isa Symbol
      Any[JSONText(class!), JSONText(class)]
    elseif class isa String
      vcat(JSONText(class!), split(class))
    elseif class isa AbstractDict
      class = LittleDict(k => JSONText(v)  for (k, v) in class)
      Any[JSONText(class!), class]
    elseif class isa Vector
      vcat([JSONText(class!)], class)
    else
      class
    end
  end

  classes = String[]
  for key in (:col, :xs, :sm, :md, :lg, :xl)
    newkey = get(flexgrid_mappings, key, key)
    if haskey(kwargs, newkey)
      colclass = sizetocol(kwargs[newkey], key)
      length(colclass) > 0 && push!(classes, colclass)
      delete!(kwargs, newkey)
    end
  end

  if length(classes) != 0
    class = if class isa Symbol
      vcat([JSONText(class)], classes)
    elseif class isa AbstractDict
      class = LittleDict(k => JSONText(v)  for (k, v) in class)
      vcat(class, classes)
    elseif class isa Vector
      vcat(class, classes)
    else
      join(pushfirst!(classes, class), ' ')
    end
  end
  
  (class isa Symbol || class isa String && length(class) > 0) && (kwargs[:class] = class)

  if ! symbol_class && class isa Symbol || class isa Vector || class isa AbstractDict
    kwargs[:class!] = if class isa Symbol || class isa String
      string(kwargs[:class])
    else
      js_attr(class)
    end
    delete!(kwargs, :class)
  end

  return kwargs
end

function append_class(class, subclass)
  subclass isa Symbol && (subclass = JSONText(subclass))
  if class isa Symbol
    [JSONText(class), subclass]
  elseif class isa String
    subclass isa String ? join(push!(split(class), subclass), " ") : vcat(split(class), [subclass])
  elseif class isa Vector
    vcat(class, [subclass])
  else # Dict
    [class, subclass]
  end
end

"""
    function row(args...; size=-1, xs=-1, sm=-1, md=-1, lg=-1, xl=-1, kwargs...)

Creates a `div` HTML element with Quasar's Flexgrid CSS class `row`. Such rows typically contain elements created with
[`cell`](@ref), `row`, [`column`](@ref) or other elements that manually receive grid classes, e.g. `"col"`, `"col-sm-5"`. 

The grid size kwargs `size`, `xs`, etc. are explained in more detail in the docs of [`cell`](@ref).
### Example

```julia
julia> row(span("Hello"))
"<div class=\"row\"><span>Hello</span></div>"
```
"""
function row(args...; 
  col::Union{Int,AbstractString,Symbol,Nothing} = -1,
  xs::Union{Int,AbstractString,Symbol,Nothing} = -1, sm::Union{Int,AbstractString,Symbol,Nothing} = -1, md::Union{Int,AbstractString,Symbol,Nothing} = -1,
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1, size::Union{Int,AbstractString,Symbol,Nothing} = -1,
  class = "", kwargs...)

  # for backward compatibility with `size` kwarg
  col == -1 && size != -1 && (col = size)

  # class = class isa Symbol ? Symbol("$class + ' row'") : class isa Vector ? push!(class, "row") : join(push!(split(class), "row"), " ")
  class = append_class(class, "row")
  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, symbol_class = false, kwargs...))

  Genie.Renderer.Html.div(args...; kwargs...)
end

"""
    function column(args...; size=-1, xs=-1, sm=-1, md=-1, lg=-1, xl=-1, kwargs...)

Creates a `div` HTML element with Quasar's Flexgrid CSS class `column`. Such columns typically contain elements created with
[`cell`](@ref), [`row`](@ref), `column`, or other elements that manually receive grid classes, e.g. `"col"`, `"col-sm-5"`. 

The grid size kwargs `size`, `xs`, etc. are explained in more detail in the docs of [`cell`](@ref).

### Example

```julia
julia> column(span("Hello"))
"<div class=\"column\"><span>Hello</span></div>"
```
"""
function column(args...;
  col::Union{Int,AbstractString,Symbol,Nothing} = -1,
  xs::Union{Int,AbstractString,Symbol,Nothing} = -1, sm::Union{Int,AbstractString,Symbol,Nothing} = -1, md::Union{Int,AbstractString,Symbol,Nothing} = -1,
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1, size::Union{Int,AbstractString,Symbol,Nothing} = -1,
  class = "", kwargs...)

  # for backward compatibility with `size` kwarg
  col == -1 && size != -1 && (col = size)
  class = append_class(class, "column")
  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, symbol_class = false, kwargs...))

  Genie.Renderer.Html.div(args...; kwargs...)
end

"""
    function cell(args...; size::Int=0, xs::Int=0, sm::Int=0, md::Int=0, lg::Int=0, xl::Int=0, kwargs...)

Creates a `div` HTML element with Quasar's flex grid CSS class `col`.
Moreover, cells are of the class `st-col`, which is controlled by the Stipple theme.

If size is specified, the class `col-\$size` is added instead.

If tag classes (`xs`, `sm`, `md`, `lg`, `xl`) are specified, the respective classes `col-\$tag-\$md` are added, e.g. `col-sm-6`.

Parameters:

- `""` / `0`: shared remaining space (e.g. `"col"`, `"col-sm"`)
- `1` - `12` / `"1"` - `"12"`: column width (e.g. `"col-5"`, `"col-sm-5"`)
- `"auto"`/`:auto`: height/width from content (`"col-auto"`, `"col-sm-auto"`)
- `-1` / `nothing`: no specification

The cells are typically included within [`row`](@ref)s or [`column`](@ref)s.
See [Quasar's Flex Grid](https://quasar.dev/layout/grid/introduction-to-flexbox) for more information.


### Example

```julia
julia> row(cell(size = 2, md = 6, sm = 12, span("Hello")))
"<div class=\"row\"><div class=\"st-col col-2 col-sm-12 col-md-6\"><span>Hello</span></div></div>"
```
"""
function cell(args...;
  col::Union{Int,AbstractString,Symbol,Nothing} = 0,
  xs::Union{Int,AbstractString,Symbol,Nothing} = -1, sm::Union{Int,AbstractString,Symbol,Nothing} = -1, md::Union{Int,AbstractString,Symbol,Nothing} = -1,
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1, size::Union{Int,AbstractString,Symbol,Nothing} = 0,
  class = "", kwargs...
)
  # for backward compatibility with `size` kwarg
  col == 0 && size != 0 && (col = size)
  
  # class = class isa Symbol ? Symbol("$class + ' st-col'") : join(push!(split(class), "st-col"), " ")
  class = append_class(class, "st-col")
  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, symbol_class = false, kwargs...))

  Genie.Renderer.Html.div(args...; kwargs...)
end

function htmldiv(args...;
  col::Union{Int,AbstractString,Symbol,Nothing} = -1,
  xs::Union{Int,AbstractString,Symbol,Nothing} = -1, sm::Union{Int,AbstractString,Symbol,Nothing} = -1, md::Union{Int,AbstractString,Symbol,Nothing} = -1,
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1, size::Union{Int,AbstractString,Symbol,Nothing} = -1,
  class = "", kwargs...)

  # for backward compatibility with `size` kwarg
  col == -1 && size != -1 && (col = size)

  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, symbol_class = false, kwargs...))

  Genie.Renderer.Html.div(args...; kwargs...)
end

function sizetocol(size::Union{String,Int,Nothing,Symbol} = -1, tag::Symbol = :col)
  (size == -1 || size === nothing) && return ""
  out = ["col"]
  tag != :col && push!(out, String(tag))
  if size isa Int
    size > 0 && push!(out, "$size")
  else
    size isa Symbol && (size = String(size))
    length(size) > 0 && size != "col" && push!(out, size)
  end
  return join(out, '-')
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

"""
    add_css(css::Function; update = true)

Add a css function to the `THEMES`.

### Params
* `css::Function` - a function that results in a vector of style elements
* `update` - determines, whether existing style sheets with the same name shall be removed

### Example
```julia
# css to remove the stipple-core color format of q-table rows
# (this will enable font color setting by the attribute `table-class`)

function mycss()
  [
    style(\"\"\"
    .stipple-core .q-table tbody tr { color: inherit; }
    \"\"\")
  ]
end

add_css(mycss)
```
`
"""
function add_css(css::Function; update = true)
  # removal can only be done by name, as the old function has already been overwritten
  update && remove_css(css::Function, byname = true)
  push!(Stipple.Layout.THEMES, css)
end

"""
    remove_css(css::Function, byname::Bool = false)

Remove a stylesheet function from the stack (`Stipple.Layout.THEMES`)
If called with `byname = true`, the function will be identified by name rather than by the function itself.
"""
function remove_css(css::Function; byname::Bool = false)
  inds = byname ? nameof.(Stipple.Layout.THEMES) .== nameof(css) : Stipple.Layout.THEMES .== css
  deleteat!(Stipple.Layout.THEMES, inds)
end

end
