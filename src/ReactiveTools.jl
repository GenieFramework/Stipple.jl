module ReactiveTools

using Stipple
using MacroTools

export @binding, @rstruct, @model, @handler, @init

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
  # dump(expr)

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

function parse_expression(expr::Expr)
  expr = find_assignment(expr)
  # dump(expr)

  (isa(expr, Expr) && contains(string(expr.head), "=")) ||
    error("Invalid binding expression -- use it with variables assignment ex `@binding a = 2`")

  var = expr.args[1]
  op = expr.head
  val = expr.args[2]
  isa(val, String) && (val = "\"$val\"")

  field = "$var $op Stipple.Reactive($val)"
  field_expr = MacroTools.unblock(Meta.parse(field))

  field_expr
end

# works with
# @binding a = 2
# @binding const a = 2
# @binding const a::Int = 2
macro binding(expr)
  init_storage(__module__)

  field_expr = parse_expression(expr)

  push!(REACTIVE_STORAGE[__module__], field_expr)

  unique!(REACTIVE_STORAGE[__module__])

  clear_type(__module__)

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