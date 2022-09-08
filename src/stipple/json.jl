const JSONParser = JSON3
const json = JSON3.write

struct JSONText
  s::String
end

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