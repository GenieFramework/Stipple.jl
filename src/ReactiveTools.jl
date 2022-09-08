module ReactiveTools

using Stipple
using MacroTools
using Random

export @binding, @rstruct, @model, @handler, @init

randsuffix() = randstring(2) |> uppercasefirst

const DEFAULT_STRUCT_NAME = string("ReactiveModel_", randsuffix())
const REACTIVE_STORAGE = Dict{Module,Any}()

macro binding(expr)
  (isa(expr, Expr) && contains(string(expr.head), "=")) ||
    error("Invalid binding expression -- use it with variables assignment ex `@binding a = 2`")
  haskey(REACTIVE_STORAGE, __module__) ||
    (REACTIVE_STORAGE[__module__] = Expr[])

  local var = expr.args[1]
  local op = expr.head
  local val = expr.args[2]
  isa(val, String) && (val = "\"$val\"")
  local field = "$var $op Stipple.Reactive($val)"

  push!(REACTIVE_STORAGE[__module__], MacroTools.unblock(Meta.parse(field)))

  unique!(REACTIVE_STORAGE[__module__])

  esc(expr)
end

macro rstruct()
  """
  @reactive! mutable struct $DEFAULT_STRUCT_NAME <: ReactiveModel
    $(join(REACTIVE_STORAGE[__module__], "\n"))
  end
  """ |> Meta.parse |> esc
end

macro model()
  :(@eval ReactiveTools.@rstruct()) |> esc
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