module StippleJSONExt

using Stipple
using JSON

# garantee interoperability of different JSONTText definitions in Stipple and JSON
# for both JSON3 and JSON

JSON.JSONText(json::Stipple.JSONText) = JSON.JSONText(json.s)
JSON.show_json(io::JSON.Writer.CompactContext, s::JSON.Writer.CS, json::Stipple.JSONText) = write(io, json.s)
JSON.Writer.lower(json::Stipple.JSONText) = JSON.parse(json.s)

Stipple.JSONText(json::JSON.JSONText) = Stipple.JSONText(json.s)
@inline StructTypes.StructType(::Type{JSON.JSONText}) = JSON3.RawType()
@inline StructTypes.construct(::Type{JSON.JSONText}, json::JSON3.RawValue) = JSONText(string(json))
@inline JSON3.rawbytes(json::JSON.JSONText) = codeunits(json.s)

end