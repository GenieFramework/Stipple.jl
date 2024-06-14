module StippleJSONExt

using Stipple

isdefined(Base, :get_extension) ? (using JSON) : (using ..JSON)

# garantee interoperability of different JSONTText definitions in Stipple and JSON
# for both JSON3 and JSON
# Note that `lower` for Stipple.JSONText is not defined as parse(json.s), because that would require
# pure proper JSON. For transmissions of bindings, though, we need to allow to pass object names.

JSON.JSONText(json::Stipple.JSONText) = JSON.JSONText(json.s)
JSON.show_json(io::JSON.Writer.CompactContext, ::JSON.Writer.CS, json::Stipple.JSONText) = write(io, json.s)
JSON.Writer.lower(json::Stipple.JSONText) = json

Stipple.JSONText(json::JSON.JSONText) = Stipple.JSONText(json.s)
@inline StructTypes.StructType(::Type{JSON.JSONText}) = JSON3.RawType()
@inline StructTypes.construct(::Type{JSON.JSONText}, json::JSON3.RawValue) = JSON.JSONText(string(json))
@inline JSON3.rawbytes(json::JSON.JSONText) = codeunits(json.s)

Stipple.js_print(io::IO, js::JSON.JSONText) = print(io, js.s)
end