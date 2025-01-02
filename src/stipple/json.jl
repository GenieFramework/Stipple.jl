const JSONParser = JSON3

# for inf values no reviver is necessary, but
stipple_inf_mapping(x) = x == Inf ? "1e1000" : x == -Inf ? "-1e1000" : "\"__nan__\""
json(args; inf_mapping::Function = stipple_inf_mapping, kwargs...) = JSON3.write(args; inf_mapping, kwargs...)

struct JSONText
  s::String
end

JSONText(sym::Symbol) = JSONText(String(sym))
JSONText(js::JSONText) = js

@inline StructTypes.StructType(::Type{JSONText}) = JSON3.RawType()
@inline StructTypes.construct(::Type{JSONText}, x::JSON3.RawValue) = JSONText(string(x))
@inline JSON3.rawbytes(x::JSONText) = codeunits(x.s)

macro json(expr)
  expr.args[1].args[1] = :(StructTypes.$(expr.args[1].args[1]))
  T = expr.args[1].args[2].args[2]

  quote
    $(esc(:(StructTypes.StructType(::Type{($T)}) = StructTypes.CustomStruct())))
    $(esc(expr))
  end
end