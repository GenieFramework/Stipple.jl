const JSONParser = JSON3

# for inf values no reviver is necessary, but
stipple_inf_mapping(x) = x == Inf ? "1e1000" : x == -Inf ? "-1e1000" : "\"__nan__\""
json(args; inf_mapping::Function = stipple_inf_mapping, kwargs...) = JSON3.write(args; inf_mapping, kwargs...)

struct JSONText
  s::String
end

JSONText(sym::Symbol) = JSONText(String(sym))
JSONText(js::JSONText) = js

Base.string(js::JSONText) = js.s
Base.:(*)(js::JSONText, x) = js.s * x
Base.:(*)(x, js::JSONText) = x * js.s
Base.:(*)(js1::JSONText, js2::JSONText) = JSONText(js1.s * js2.s)

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

"""
    @js_str -> JSONText

Construct a JSONText, such as `js"button=false"`, without interpolation and unescaping
(except for quotation marks `"`` which still has to be escaped). Avoiding escaping `"`` can be done by
`js\"\"\"alert("Hello World")\"\"\"`.
"""
macro js_str(expr)
  :( JSONText($(esc(expr))) )
end