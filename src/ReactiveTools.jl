module ReactiveTools

using Stipple
using MacroTools

export @binding, @rstruct, @model, @handler, @init, @readonly, @private, @field, @jsfn

const REACTIVE_STORAGE = Dict{Module,Vector{Expr}}()
const TYPES = Dict{Module,Union{<:DataType,Nothing}}()

function default_struct_name(m::Module)
  "$(m)_ReactiveModel"
end

function init_storage(m::Module)
  haskey(REACTIVE_STORAGE, m) || (REACTIVE_STORAGE[m] = Expr[])
  haskey(TYPES, m) || (TYPES[m] = nothing)
end

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

  val = expr.args[2]
  isa(val, AbstractString) && (val = "\"$val\"")

  field = "$var::$rtype $op $(typename)($val)$opts"
  field_expr = MacroTools.unblock(Meta.parse(field))

  field_expr
end

function binding(expr::Expr, m::Module, opts::String = "", typename::String = "Stipple.Reactive")
  init_storage(m)
  field_expr = parse_expression(expr, opts, typename)
  push!(REACTIVE_STORAGE[m], field_expr)
  unique!(REACTIVE_STORAGE[m])
  clear_type(m)
end

# works with
# @binding a = 2
# @binding const a = 2
# @binding const a::Int = 24
# @binding a::Vector = [1, 2, 3]
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

macro jsfn(expr)
  binding(expr, __module__, ", JSFUNCTION")
  esc(expr)
end

macro field(expr)
  binding(expr, __module__, "", "")
  esc(expr)
end

macro rstruct()
  init_storage(__module__)

  """
  @reactive! mutable struct $(default_struct_name(__module__)) <: ReactiveModel
    $(join(REACTIVE_STORAGE[__module__], "\n"))
  end
  """ |> Meta.parse |> esc
end

macro model()
  """
  if Stipple.ReactiveTools.TYPES[@__MODULE__] !== nothing
    ReactiveTools.TYPES[@__MODULE__]
  else
    type = @eval ReactiveTools.@rstruct()
    ReactiveTools.TYPES[@__MODULE__] = type

    type
  end
  """ |> Meta.parse |> esc
end

macro init()
  """
  begin
    local modeltype = @eval ReactiveTools.@model();
    Stipple.init(modeltype)
  end
  """ |> Meta.parse |> esc
end

end