module ReactiveTools

using Stipple
using MacroTools
using MacroTools: postwalk
using OrderedCollections

export @binding, @readonly, @private, @in, @out, @value, @jsfn
export @page, @rstruct, @type, @handlers, @init, @model, @onchange, @onchangeany

const REACTIVE_STORAGE = LittleDict{Module,LittleDict{Symbol,Expr}}()
const TYPES = LittleDict{Module,Union{<:DataType,Nothing}}()

function DEFAULT_LAYOUT(; title::String = "Genie App")
  """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <% Stipple.sesstoken() %>
    <title>$title</title>
    <% if isfile(joinpath(Genie.config.server_document_root), "app.css") %>
    <link rel='stylesheet' href='app.css'>
    <% else %>
    <% end %>
  </head>
  <body>
    <% page(model, partial = true, v__cloak = true, [@yield], @iif(:isready)) %>
    <% if isfile(joinpath(Genie.config.server_document_root), "app.js") %>
    <script src='app.js'></script>
    <% else %>
    <% end %>
  </body>
</html>
"""
end

function __init__()
  Stipple.UPDATE_MUTABLE[] = false
end

function default_struct_name(m::Module)
  "$(m)_ReactiveModel"
end

function init_storage(m::Module)
  haskey(REACTIVE_STORAGE, m) || (REACTIVE_STORAGE[m] = LittleDict{Symbol,Expr}())
  haskey(TYPES, m) || (TYPES[m] = nothing)

end

#===#

function clear_type(m::Module)
  TYPES[m] = nothing
end

function delete_bindings!(m::Module)
  clear_type(m)
  delete!(REACTIVE_STORAGE, m)
end

function bindings(m)
  init_storage(m)
  REACTIVE_STORAGE[m]
end

#===#

macro rstruct()
  init_storage(__module__)

  """
  @reactive! mutable struct $(default_struct_name(__module__)) <: ReactiveModel
    $(join(REACTIVE_STORAGE[__module__] |> values |> collect, "\n"))
  end
  """ |> Meta.parse |> esc
end

macro type()
  init_storage(__module__)

  """
  if Stipple.ReactiveTools.TYPES[@__MODULE__] !== nothing
    ReactiveTools.TYPES[@__MODULE__]
  else
    ReactiveTools.TYPES[@__MODULE__] = @eval ReactiveTools.@rstruct()
  end
  """ |> Meta.parse |> esc
end

macro model()
  init_storage(__module__)

  :(@type() |> Base.invokelatest)
end

#===#

function find_assignment(expr)
  assignment = nothing

  if isa(expr, Expr) && !contains(string(expr.head), "=")
    for arg in expr.args
      assignment = if isa(arg, Expr)
        find_assignment(arg)
      end
    end
  elseif isa(expr, Expr) && contains(string(expr.head), "=")
    assignment = expr
  else
    assignment = nothing
  end

  assignment
end

function parse_expression(expr::Expr, opts::String = "", typename::String = "Stipple.Reactive", reference::Bool = true)
  expr = find_assignment(expr)

  (isa(expr, Expr) && contains(string(expr.head), "=")) ||
    error("Invalid binding expression -- use it with variables assignment ex `@binding a = 2`")

  var = expr.args[1]
  rtype = ""

  if ! isempty(opts)
    rtype = "::R"
    typename = ""
  end

  if isa(var, Expr) && var.head == Symbol("::")
    rtype = "::R{$(var.args[2])}"
    var = var.args[1]
    typename = ""
  end

  op = expr.head

  field = if ! reference
    val = expr.args[2]
    isa(val, AbstractString) && (val = "\"$val\"")
    "$var$rtype $op $(typename)($(val))$(opts)"
  else
    "$var$rtype $op $(typename)($var)$(opts)"
  end

  var, MacroTools.unblock(Meta.parse(field))
end

function binding(expr::Symbol, m::Module, opts::String = "", typename::String = "Stipple.Reactive", reference::Bool = true)
  binding(:($expr = $expr), m, opts, typename)
end

function binding(expr::Expr, m::Module, opts::String = "", typename::String = "Stipple.Reactive", reference::Bool = true)
  init_storage(m)

  var, field_expr = parse_expression(expr, opts, typename, reference)
  REACTIVE_STORAGE[m][var] = field_expr

  # remove cached type and instance
  clear_type(m)
end

# works with
# @binding a = 2
# @binding const a = 2
# @binding const a::Int = 24
# @binding a::Vector = [1, 2, 3]
# @binding a::Vector{Int} = [1, 2, 3]
macro binding(expr)
  binding(expr, __module__)
  esc(expr)
end

macro value(expr)
  binding(expr, __module__, "", "Stipple.Reactive", false)
  esc(expr)
end

macro in(expr)
  binding(expr, __module__, "", "Stipple.Reactive", false)
  esc(expr)
end

macro out(expr)
  binding(expr, __module__, ", READONLY", "Stipple.Reactive", false)
  esc(expr)
end

macro readonly(expr)
  binding(expr, __module__, ", READONLY", "Stipple.Reactive", false)
  esc(expr)
end

macro private(expr)
  binding(expr, __module__, ", PRIVATE", "Stipple.Reactive", false)
  esc(expr)
end

macro jsfn(expr)
  binding(expr, __module__, ", JSFUNCTION", "Stipple.Reactive", false)
  esc(expr)
end

#===#

macro init()
  quote
    local initfn =  if isdefined($__module__, :init_from_storage)
                      $__module__.init_from_storage
                    else
                      $__module__.init
                    end
    local handlersfn =  if isdefined($__module__, :__GF_AUTO_HANDLERS__)
                          $__module__.__GF_AUTO_HANDLERS__
                        else
                          identity
                        end

    @type() |> initfn |> handlersfn
  end |> esc
end

macro handlers(expr)
  quote
    function __GF_AUTO_HANDLERS__(__model__)
      $expr

      __model__
    end
  end |> esc
end

macro onchange(var, expr)
  known_vars = push!(Stipple.ReactiveTools.REACTIVE_STORAGE[__module__] |> keys |> collect, :isready, :isprocessing) # add mixins

  if isa(var, Symbol) && in(var, known_vars)
    var = :(__model__.$var)
  else
    error("Unknown binding $var")
  end

  exp = postwalk(x -> isa(x, Symbol) && in(x, known_vars) ? :(__model__.$x[]) : x, expr)

  quote
    on($var) do __value__
      $exp
    end
  end |> esc
end

macro onchangeany(vars, expr)
  known_vars = push!(Stipple.ReactiveTools.REACTIVE_STORAGE[__module__] |> keys |> collect, :isready, :isprocessing) # add mixins

  va = postwalk(x -> isa(x, Symbol) && in(x, known_vars) ? :(__model__.$x) : x, vars)
  exp = postwalk(x -> isa(x, Symbol) && in(x, known_vars) ? :(__model__.$x[]) : x, expr)

  quote
    onany($va...) do (__values__...)
      $exp
    end
  end |> esc
end

#===#

macro page(url, view, layout)
  quote
    Stipple.Pages.Page( $url;
                        view = $view,
                        layout = $layout,
                        model = () -> @init(),
                        context = $__module__)
  end |> esc
end

macro page(url, view)
  :(@page($url, $view, Stipple.ReactiveTools.DEFAULT_LAYOUT())) |> esc
end

macro page(url)
  :(@page($url, "$(__file__).html", Stipple.ReactiveTools.DEFAULT_LAYOUT())) |> esc
end

end