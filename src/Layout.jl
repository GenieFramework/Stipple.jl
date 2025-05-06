"""
# Stipple.Layout

Utilities for rendering the general layout of a Stipple app, such as of a data dashboard web page or supporting themes.
"""
module Layout

using Genie, Stipple, Stipple.Theme

export layout, add_css, remove_css
export page, app, row, column, cell, container, flexgrid_kwargs, htmldiv, @gutter

export theme, googlefonts_css, stipplecore_css, genie_footer

import Base.RefValue

const THEMES = RefValue(Function[])

const FLEXGRID_KWARGS = [:col, :xs, :sm, :md, :lg, :xl, :gutter, :xgutter, :ygutter]

"""
    make_unique!(src::Vector, condition::Union{Nothing, Function} = nothing)

Utility function for removing duplicates from a vector that fulfill a given condition.
"""
function make_unique!(src::Vector, condition::Union{Nothing, Function} = nothing)
  seen = Int[]
  dups = Int[]
  for (i, name) in enumerate(src)
      if name ∈ view(src, seen) && (condition === nothing || condition(name))
          push!(dups, i)
      else
          push!(seen, i)
      end
  end

  deleteat!(src, dups)
end

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
"<!DOCTYPE html>\n<html><head><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui\" /></head><body class style><link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><span v-text='greeting'>Hello</span><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.global.prod.js\"></script><script src=\"/js/quasar.umd.prod.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script></body></html>"
```

```julia
julia> layout([
        span("Hello", @text(:greeting))
        ], partial = true)
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><span v-text='greeting'>Hello</span><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.global.prod.js\"></script><script src=\"/js/quasar.umd.prod.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script>"
```
"""
function layout(output::Union{S,Vector}, m::Union{M, Vector{M}};
                partial::Bool = false, title::String = "", class::String = "", style::String = "", head_content::Union{AbstractString, Vector{<:AbstractString}} = "",
                channel::String = Stipple.channel_js_name,
                core_theme::Bool = true,
                sess_token::Bool = true)::ParsedHTMLString where {M<:ReactiveModel, S<:AbstractString}

  isa(output, Vector) && (output = join(output, '\n'))
  m isa Vector || (m = [m])

  content = [
    output
    theme(; core_theme)
    Stipple.deps.(m)...
  ]

  make_unique!(content, contains(r"src=|href="i))

  partial && return content
  
  head_content = join(head_content)
  if !contains(head_content, "<meta name=\"sesstoken\"") && sess_token
    head_content *= Stipple.sesstoken()
  end
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
"<!DOCTYPE html>\n<html><head><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui\" /></head><body class style><link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><div id=elemid><span v-text='greeting'>Hello</span></div><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/underscore-min.js\"></script><script src=\"/js/vue.global.prod.js\"></script><script src=\"/js/quasar.umd.prod.js\"></script>\n<script src=\"/js/apexcharts.min.js\"></script><script src=\"/js/vue-apexcharts.min.js\"></script><script src=\"/js/stipplecore.js\" defer></script><script src=\"/js/vue_filters.js\" defer></script></body></html>"
```
"""
function page(model::Union{M, Vector{M}}, args...;
              pagetemplate = (x...) -> join([x...], '\n'),
              partial::Bool = false, title::String = "", class::String = "container", style::String = "",
              channel::String = Genie.config.webchannels_default_route, head_content::Union{AbstractString, Vector{<:AbstractString}} = "",
              prepend::Union{S,Vector} = "", append::Union{T,Vector} = [],
              core_theme::Bool = true,
              sess_token::Bool = true,
              kwargs...)::ParsedHTMLString where {M<:Stipple.ReactiveModel, S<:AbstractString,T<:AbstractString}
  uis = if !isempty(args)
    args[1] isa Vector && model isa Vector ? args[1] : [args[1]]
  else
    ""
  end
  model isa Vector || (model = [model])
  counter = Dict{DataType, Int}()

  function rootselector(m::M) where M <:ReactiveModel
    AM = Stipple.get_abstract_type(M)
    counter[AM] = get(counter, AM, 0) + 1
    return (counter[AM] == 1) ? vm(m) : "$(vm(m))-$(counter[AM])"
  end

  layout(
    [
      join(prepend)
      pagetemplate([Genie.Renderer.Html.div(id = rootselector(m), ui, args[2:end]...; class = class, kwargs...) for (m, ui) in zip(model, uis)]...)
      join(append)
    ], model;
    partial, title, style, head_content, channel, core_theme, sess_token)
end

const app = page


function container(args...; fluid = false, kwargs...)
  cssclass = fluid ? "container-fluid" : "container"
  kwargs = NamedTuple(Dict{Symbol,Any}(kwargs...), :class, cssclass)

  Genie.Renderer.Html.div(args...; kwargs...)
end

function iscontainer(class::String)
  !isempty(intersect(split(class), ("row", "column")))
end

function iscontainer(class::Vector)
  length(class) > 0 && class[end] in ("row", "column")
end

function iscontainer(class)
    false
end

function genie_footer()
  ParsedHTMLString("""
  <style>
    ._genie_logo {
      background:url('https://genieframework.com/logos/genie/logo-simple-with-padding.svg') no-repeat;
      background-size:40px;
      padding-top:22px;
      padding-right:10px;
      color:transparent !important;
      font-size:9pt;
    }
    ._genie .row .col-12 { width:50%; margin:auto; }
  </style>
  <footer class='_genie container'>
    <div class='row'>
      <div class='col-12'>
        <p class='text-muted credit' style='text-align:center;color:#8d99ae;'>Built with
          <a href='https://genieframework.com' target='_blank' class='_genie_logo' ref='nofollow'>Genie</a>
        </p>
      </div>
    </div>
  </footer>
  """)
end

function flexgrid_class(tag::Symbol, value::Union{String,Int,Nothing,Symbol} = -1, container = false)
  gutter = container ? "q-col-gutter" : "q-gutter"
  (value == -1 || value === nothing) && return ""
  out = String[]
  if tag in (:col, :xs, :sm, :md, :lg, :xl)
    tag == :col || push!(out, "col")
    push!(out, "$tag")
  elseif tag == :gutter
    push!(out, gutter)
  elseif tag == :xgutter
    push!(out, "$gutter-x")
  elseif tag == :ygutter
    push!(out, "$gutter-y")
  else
    push!(out, "$tag")
  end

  if value isa Int
    value > 0 && push!(out, "$value")
  else
    value isa Symbol && (value = String(value))
    length(value) > 0 && value != "col" && push!(out, value)
  end
  return join(out, '-')
end

function flexgrid_kwargs(; class = "", class! = nothing, symbol_class::Bool = true, flexgrid_mappings::Dict{Symbol,Symbol} = Dict{Symbol,Symbol}(), kwargs...)
  container = iscontainer(class)
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
  for key in FLEXGRID_KWARGS
    newkey = get(flexgrid_mappings, key, key)
    if haskey(kwargs, newkey)
      colclass = flexgrid_class(key, kwargs[newkey], container)
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
      isempty(class) || pushfirst!(classes, class)
      join(classes, ' ')
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
    extract_kwargs!(args::Vector, kwarg_names)

Low-level function that finds all kwargs in kwargs names from an expression if the expression is a function call and returns them as an expression that
can be plugged in a function expression.
"""
function extract_kwargs!(args::Vector, kwarg_names)
  kwargs = Expr(:parameters)
  params = []
  for n in length(args):-1:1
    if args[n] isa Expr && args[n].head == :kw && args[n].args[1] in kwarg_names
      pushfirst!(kwargs.args, popat!(args, n))
    end
  end
  n = length(args)
  pos = n > 0 && args[1] isa Expr && args[1].head == :parameters ? 1 : n > 1 && args[2] isa Expr && args[2].head == :parameters ? 2 : 0
  
  pos == 0 && return kwargs

  parameters = args[pos].args
  for n in length(parameters):-1:1
    p = parameters[n]
    if p isa Expr && p.head == :kw && p.args[1] in kwarg_names || p isa Symbol && p in kwarg_names
      push!(params, popat!(parameters, n))
    end
  end
  append!(kwargs.args, reverse(params))
  kwargs
end

function _wrap_expression(expr, context)
  new_expr = if expr isa Expr && expr.head == :call
    for i in eachindex(expr.args)
      if expr.args[i] isa Expr && expr.args[i].head == :macrocall && 
              expr.args[i].args[1] ∈ (Symbol("@for"), Symbol("@if"), Symbol("@elseif"), Symbol("@else"), Symbol("@showif"))

        expr.args[i] = macroexpand(context, expr.args[i])
      end
    end
    kwargs = extract_kwargs!(expr.args, vcat(FLEXGRID_KWARGS[1:6], [:var"v-for", :var"v__for", :var"v-if", :var"v__if", :var"v-else", :var"v__else", :var"v-show", :var"v__show"]))
    # extra treatment for cell(), because col = 0 is default:
    # So if not set explicitly then add col = 0 to the wrapper kwargs and col = -1 in the child kwargs
    if expr.args[1] == :cell && :col ∉ [kwarg isa Expr ? kwarg.args[1] : kwarg for kwarg in kwargs.args]
      push!(kwargs.args, Expr(:kw, :col, 0))
      push!(expr.args, Expr(:kw, :col, -1))
    end
    new_expr = :(Stipple.htmldiv())
    push!(new_expr.args, kwargs, expr)
    new_expr
  else
    :(Stipple.htmldiv($expr))
  end

  new_expr
end


"""
    @gutter(child_or_children)

Wraps an element in a div-element to be part of a gutter container.
(For the two-argument version of the macro that sets the gutter size see below.)

### Example 1
```julia
julia> @gutter [
         card("Hello", sm = 12, lg = 4)
         card("World", sm = 12, md = 8)
       ]

2-element Vector{ParsedHTMLString}:
 "<div class=\"col col-sm-12 col-lg-4\"><q-card>Hello</q-card></div>"
 "<div class=\"col col-sm-12 col-md-8\"><q-card>World</q-card></div>"
```
Note that the child elements need to be explicitly written in the code, for more info see below.
### Example 2
```
julia> row(gutter = :md, @gutter [
         card("Hello", sm = 12, lg = 4)
         card("World", sm = 12, md = 8)
       ]) |> prettify |> println
<div class="row col q-col-gutter-md">
    <div class="col col-sm-12 col-lg-4">
        <q-card>
            Hello
        </q-card>
    </div>
    <div class="col col-sm-12 col-md-8">
        <q-card>
            World
        </q-card>
    </div>
</div>
```
"""
macro gutter(expr)
  if expr isa Expr && expr.head ∈ (:vcat, :vect)
      expr.args = _wrap_expression.(expr.args, Base.RefValue(__module__))
  else
      expr = _wrap_expression(expr, __module__)
  end
  expr |> esc
end

"""
    @gutter(size, children)

Sets the spacing of child elements.
(We use `card()` and `prettify()` from `StippleUI` for the examples.) 

```julia
julia> row(@gutter :md [
         card("Hello", sm = 12, lg = 4)
         card("World", sm = 12, md = 8)
       ]) |> prettify |> println
<div class="row col q-col-gutter-md">
    <div class="col col-sm-12 col-lg-4">
        <q-card>
            Hello
        </q-card>
    </div>
    <div class="col col-sm-12 col-md-8">
        <q-card>
            World
        </q-card>
    </div>
</div>
```
The internal reason for this macro is that elements in a gutter need to be wrapped in div-elements as you can see above.

# Caveats
The macro can only handle children if they are explicitily written in the command. The macro cannot handle content of a variable,
so `row(@gutter [c1, c2])` will fail.

Instead, you'd move the gutter macro to the definition of c1 and pass the gutter size to the parent element

```
c1 = @gutter card("Hello", sm = 2,  md = 8)
c2 = @gutter card("World", sm = 10, md = 4)

row(gutter = :md, [c1, c2])
```
  
If you need c1 unwrapped in a different context you'd go for manual wrapping. You can also go for a mixed approach.

```
c1 = card("Hello", sm = 2,  md = 8)
row(gutter = :md, [
    cell(c1, sm = 12, md = 8, lg = 4, xl = 12)
    @gutter card("World", sm = 12, md = 8, lg = 4, xl = 12)
])
```
Due to restrictions in the Julia macro language the macro needs to go in the first
position of the expression, so
```julia
row(class = "myclass", @gutter(:md, [
    card("Hello", sm = 2,  md = 8)
    card("World", sm = 10, md = 4)
])
```
will fail.

Place the class as second argument instead
```julia
row(@gutter(:md, [
    card("Hello", sm = 2,  md = 8)
    card("World", sm = 10, md = 4)
], class = "myclass"))
```
"""
macro gutter(size, expr)
  Expr(:parameters, Expr(:kw, :gutter, size), Expr(:kw, :inner, :(@gutter($expr)))) |> esc
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
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1,
  gutter::Union{AbstractString,Symbol,Nothing} = nothing, xgutter::Union{AbstractString,Symbol,Nothing} = nothing, ygutter::Union{AbstractString,Symbol,Nothing} = nothing,
  class::Union{AbstractString,Symbol,AbstractDict,Vector} = "", size::Union{Int,AbstractString,Symbol,Nothing} = -1, kwargs...)

  # for backward compatibility with `size` kwarg
  col == -1 && size != -1 && (col = size)

  # class = class isa Symbol ? Symbol("$class + ' row'") : class isa Vector ? push!(class, "row") : join(push!(split(class), "row"), " ")
  class = append_class(class, "row")
  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, gutter, xgutter, ygutter, symbol_class = false, kwargs...))

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
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1,
  gutter::Union{AbstractString,Symbol,Nothing} = nothing, xgutter::Union{AbstractString,Symbol,Nothing} = nothing, ygutter::Union{AbstractString,Symbol,Nothing} = nothing,
  class::Union{AbstractString,Symbol,AbstractDict,Vector} = "", size::Union{Int,AbstractString,Symbol,Nothing} = -1, kwargs...)
  # for backward compatibility with `size` kwarg
  col == -1 && size != -1 && (col = size)
  class = append_class(class, "column")
  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, gutter, xgutter, ygutter, symbol_class = false, kwargs...))

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
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1,
  gutter::Union{AbstractString,Symbol,Nothing} = nothing, xgutter::Union{AbstractString,Symbol,Nothing} = nothing, ygutter::Union{AbstractString,Symbol,Nothing} = nothing,
  class::Union{AbstractString,Symbol,AbstractDict,Vector} = "", size::Union{Int,AbstractString,Symbol,Nothing} = 0, kwargs...
)
  # for backward compatibility with `size` kwarg
  col == 0 && size != 0 && (col = size)

  # class = class isa Symbol ? Symbol("$class + ' st-col'") : join(push!(split(class), "st-col"), " ")
  class = append_class(class, "st-col")
  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, gutter, xgutter, ygutter, symbol_class = false, kwargs...))

  Genie.Renderer.Html.div(args...; kwargs...)
end

function htmldiv(args...;
  col::Union{Int,AbstractString,Symbol,Nothing} = -1,
  xs::Union{Int,AbstractString,Symbol,Nothing} = -1, sm::Union{Int,AbstractString,Symbol,Nothing} = -1, md::Union{Int,AbstractString,Symbol,Nothing} = -1,
  lg::Union{Int,AbstractString,Symbol,Nothing} = -1, xl::Union{Int,AbstractString,Symbol,Nothing} = -1,
  gutter::Union{AbstractString,Symbol,Nothing} = nothing, xgutter::Union{AbstractString,Symbol,Nothing} = nothing, ygutter::Union{AbstractString,Symbol,Nothing} = nothing,
  class::Union{AbstractString,Symbol,AbstractDict,Vector} = "", size::Union{Int,AbstractString,Symbol,Nothing} = -1, kwargs...)

  # for backward compatibility with `size` kwarg
  col == -1 && size != -1 && (col = size)

  kwargs = Stipple.attributes(flexgrid_kwargs(; class, col, xs, sm, md, lg, xl, gutter, xgutter, ygutter, symbol_class = false, kwargs...))

  Genie.Renderer.Html.div(args...; kwargs...)
end

function googlefonts_css()
  (stylesheet("https://fonts.googleapis.com/css?family=Material+Icons"),)
end

function stipplecore_css()
  (stylesheet(Genie.Assets.asset_path(Stipple.assets_config, :css, file="stipplecore")),)
end

function coretheme()
    stylesheet("https://fonts.googleapis.com/css?family=Material+Icons"),
    stylesheet(Genie.Assets.asset_path(Stipple.assets_config, :css, file="stipplecore"))
end


"""
Sets the app theme to the given theme. Returns the index of the theme in the `THEMES[]` array.
"""
function set_theme!(theme::Symbol)
  if Stipple.Theme.THEME_INDEX[] == 0
    push!(THEMES[], Stipple.Theme.to_asset(theme)) # automatically load the current/default theme
    Stipple.Theme.THEME_INDEX[] = length(THEMES[]) # store the index of the current theme
  else
    THEMES[][Stipple.Theme.THEME_INDEX[]] = Stipple.Theme.to_asset(theme)
  end

  theme == :usertheme && ! Stipple.Theme.theme_exists(:usertheme) && register_usertheme()
  Stipple.Theme.set_theme(theme)

  try
    read_theme_dotfile() != theme && write_theme_dotfile(theme)
  catch ex
    @warn "Could not write theme to dotfile: $ex"
  end

  nothing
end
const set_theme = set_theme!


const THEME_DOTFILE = joinpath(".theme")
const DEFAULT_USER_THEME_FILE = joinpath("css", Stipple.THEMES_FOLDER, "theme.css")
const USER_THEME_WATCHER = RefValue(false)
const DOTTHEME_WATCHER = RefValue(false)


function set_user_theme_watcher() :: Bool
  (USER_THEME_WATCHER[] || Stipple.PRECOMPILE[] || ! Genie.Configuration.isdev()) && return false

  path_to_user_theme = joinpath(Genie.config.server_document_root, DEFAULT_USER_THEME_FILE)
  @async Genie.Revise.entr([path_to_user_theme]) do
    if ! isfile(path_to_user_theme) && Stipple.Theme.get_theme() == :usertheme
      set_theme!(:default)
      Stipple.Theme.unregister_theme(:usertheme)
    end
  end
  USER_THEME_WATCHER[] = true

  true
end


function set_dottheme_watcher() :: Bool
  (DOTTHEME_WATCHER[] || Stipple.PRECOMPILE[] || ! Genie.Configuration.isdev()) && return false

  @async Genie.Revise.entr([THEME_DOTFILE]) do
    theme_from_dotfile = read_theme_dotfile()
    if theme_from_dotfile !== nothing && Stipple.Theme.get_theme() != theme_from_dotfile
      if theme_from_dotfile == :usertheme && ! Stipple.Theme.theme_exists(:usertheme)
        register_usertheme()
      end
      set_theme!(theme_from_dotfile)
    end
  end
  DOTTHEME_WATCHER[] = true

  true
end


function read_theme_dotfile() :: Union{Symbol,Nothing}
  if ! isfile(THEME_DOTFILE)
    try
      touch(THEME_DOTFILE) # create the file if it doesn't exist
    catch ex
      @warn "Could not create theme dotfile: $ex"
    end

    return nothing
  end

  try
    read(THEME_DOTFILE, String) |> Symbol
  catch
    nothing
  end
end


function write_theme_dotfile(theme::Symbol)
  isfile(THEME_DOTFILE) || return
  
  write(THEME_DOTFILE, String(theme))
  nothing
end


function register_usertheme() :: Bool
  isfile(joinpath(Genie.config.server_document_root, DEFAULT_USER_THEME_FILE)) || return false
  register_theme(:usertheme, "/" * join(splitpath(DEFAULT_USER_THEME_FILE), "/")) # make this a relative URL

  true
end


"""
    function theme() :: String

Provides theming support for Stipple apps and pages. It includes Stipple's default CSS files and additional elements,
  in the form of HTML tags, can be injected by pushing to the `Stipple.Layout.THEMES[][]` collection.

### Example

```julia
julia> theme()
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.css\" rel=\"stylesheet\" />"

julia> StippleUI.theme()
"<link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" />"

julia> push!(Stipple.Layout.THEMES[], StippleUI.theme)
```
"""
function theme(; core_theme::Bool = true) :: Vector{String}
  output = String[]

  core_theme && coretheme ∉ THEMES[] && push!(output, coretheme()...)

  has_custom_theme = false
  has_dottheme = false

  user_theme_file = joinpath(Genie.config.server_document_root, DEFAULT_USER_THEME_FILE)
  if isfile(user_theme_file)
    register_usertheme()
    has_custom_theme = true
  end

  theme_from_dotfile = read_theme_dotfile()
  if theme_from_dotfile !== nothing && Stipple.Theme.theme_exists(theme_from_dotfile)
    has_dottheme = true
  end

  if has_dottheme
    set_theme!(theme_from_dotfile)
  elseif has_custom_theme
    set_theme!(:usertheme)
  else
    set_theme!(:default)
  end

  set_dottheme_watcher()
  set_user_theme_watcher()

  for f in THEMES[]
    _o = f()
    if _o isa Vector || _o isa Tuple
      push!(output, _o...)
      continue
    end
    push!(output, _o)
  end
  
  output
end

"""
Register a theme with a given name and path to the CSS file.
"""
function register_theme(name::Symbol, theme::String; apply_theme = false)
  Stipple.Theme.register_theme(name, theme)
  apply_theme && set_theme!(name)
end
function register_theme(theme::String)
  register_theme(Symbol(theme), theme)
end


"""
    add_css(css::Function; update = true)

Add a css function to the `THEMES[]`.

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
  push!(THEMES[], css)
  unique!(THEMES[])
end

"""
    add_css(css...; update = false)

Adds a css file to the layout.

### Example
```julia
Stipple.Layout.add_css("froop.css", "bootstrap.css", "https://cdn.tailwindcss.com/tailwind.css")
```
"""
function add_css(css...; update = false)
  css = [Stipple.Elements.stylesheet(c) for c in css]
  add_css(() -> css; update = update)
end

"""
    add_script(script...; update = false)

Adds a script file to the layout.

### Example
```julia
Stipple.Layout.add_script("froop.js", "bootstrap.js", "https://cdn.tailwindcss.com/tailwind.js")
```
"""
function add_script(script...; update = false)
  script = [Stipple.Elements.script(src=s) for s in script]
  add_css(() -> script; update = update)
end

"""
    remove_css(css::Function, byname::Bool = false)

Remove a stylesheet function from the stack (`THEMES[]`)
If called with `byname = true`, the function will be identified by name rather than by the function itself.
"""
function remove_css(css::Function; byname::Bool = false)
  inds = byname ? nameof.(THEMES[]) .== nameof(css) : THEMES[] .== css
  deleteat!(THEMES[], inds)
end

"""
    theme!(css::Function)

Replace the current themes with new ones.
"""
function theme!(css::Function)
  THEMES[] = [css]
end

end
