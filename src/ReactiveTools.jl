module ReactiveTools

using Stipple
using MacroTools
using OrderedCollections

export @binding, @rstruct, @type, @handlers, @init, @readonly, @private, @field, @model, @page

const REACTIVE_STORAGE = LittleDict{Module,LittleDict{Symbol,Expr}}()
const TYPES = LittleDict{Module,Union{<:DataType,Nothing}}()

function __init__()
  Stipple.UPDATE_MUTABLE[] = true
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

function parse_expression(expr::Expr, opts::String = "", typename::String = "Stipple.Reactive")
  expr = find_assignment(expr)

  (isa(expr, Expr) && contains(string(expr.head), "=")) ||
    error("Invalid binding expression -- use it with variables assignment ex `@binding a = 2`")

  var = expr.args[1]
  rtype = "R"
  if isa(var, Expr) && var.head == Symbol("::")
    rtype = "R{$(var.args[2])}"
    var = var.args[1]
  end

  op = expr.head

  field = "$var::$rtype $op $(typename)($var)$opts"
  var, MacroTools.unblock(Meta.parse(field))
end

function binding(expr::Symbol, m::Module, opts::String = "", typename::String = "Stipple.Reactive")
  binding(:($expr = $expr), m, opts, typename)
end

function binding(expr::Expr, m::Module, opts::String = "", typename::String = "Stipple.Reactive")
  init_storage(m)

  var, field_expr = parse_expression(expr, opts, typename)
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

macro readonly(expr)
  binding(expr, __module__, ", READONLY")
  esc(expr)
end

macro private(expr)
  binding(expr, __module__, ", PRIVATE")
  esc(expr)
end

# does not work
# macro jsfn(expr)
#   binding(expr, __module__, ", JSFUNCTION")
#   esc(expr)
# end

macro field(expr)
  binding(expr, __module__, "", "")
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
    local handlersfn =  if isdefined($__module__, :handlers)
                          $__module__.handlers
                        else
                          identity
                        end

    @type() |> initfn |> handlersfn
  end |> esc
end

macro handlers(expr)
  quote
    function handlers(model)
      $expr

      model
    end
  end |> esc
end

#===#

macro page(url, view, layout)
  quote
    Stipple.Pages.Page( $url;
                        view = $view,
                        layout = $layout,
                        model = :(@init()),
                        context = $__module__)
  end |> esc
end

macro page(url, view)
  :(@page($url, $view, string("<% page(model, partial = true, [@yield]) %>"))) |> esc
end

end