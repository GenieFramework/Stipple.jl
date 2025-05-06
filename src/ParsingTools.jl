module ParsingTools

using Stipple

export symbol_dict, type_dict, serialize, serialize!, deserialize, deserialize!, serializedfields, typify

"""
    type_dict(T::DataType)

Generate a dict with the types of the fields.
"""
type_dict(T::DataType) = Dict(zip(fieldnames(T), fieldtypes(T)))

symbol_dict(x) = x
symbol_dict(d::AbstractDict) = Dict{Symbol,Any}([(Symbol(k), symbol_dict(v)) for (k, v) in d])

@nospecialize

"""
    function struct_to_dict(s::T, f::Union{Nothing, Function} = !isnothing) where T

Convert a struct to a dict
    - f: taking only those fields, where f(field == true)
"""
function struct_to_dict(s::T, f::Union{Nothing, Function} = !isnothing) where T <: Union{DataType, Type{<:Tuple}}
    ftest = isnothing(f) ? x -> true : f
    
    isempty(fieldnames(T)) && return s
    Dict{Symbol, Any}(k => struct_to_dict(v) for (k, v) in zip(fieldnames(T), getfield.(RefValue(s), fieldnames(T))) if ftest(v))
end

function deserialize!(d::Dict{T, Any}) where T
  for (k, v) in zip(keys(d), values(d))
    ks = String(k)
    (! occursin("_", ks) || startswith(ks, "_") || occursin("__", ks)) && continue
    
    kk = T.(split(ks, "_", keepempty = false))
    setindex!(foldl((x, y) -> get!(Dict{T, Any}, x, y), kk[1:end-1]; init = d), v, kk[end])
    
    delete!(d, k)
  end
  d
end

deserialize(d) = deserialize!(deepcopy(d))

function serialize!(d::Dict{T, Any}, key::T) where T
    haskey(d, key) && d[key] isa Dict || return d
    sd = d[key]
    for k in keys(sd)
        isnothing(sd[k]) && continue
        newkey = T("$(key)_$k")
        d[newkey] = sd[k]
        sd[k] isa Dict && serialize!(d, newkey)
    end
    delete!(d, key)
    d
end

function serialize!(d::Dict{T, Any}, kk::Vector{T}) where T
    for k in kk
        serialize!(d, k)
    end
    d
end

serialize!(d, T::Type) = serialize!(d, serializedfields(T))

serialize(d, key) = serialize!(deepcopy(d), key)

function serializedfields(T::Type)
  ff = String[String(f) for f in fieldnames(T)]
  index = occursin.("_", ff) .& .! startswith.(ff, "_") .& .! occursin.("__", ff)
  union([Symbol(match(r"[^_]+", f).match) for f in ff[index]])
end

function typify(T::Type, d::Dict{TD, Any}) where {TD <: Union{Symbol, String}}
    serialize!(TD == Symbol ? d : symbol_dict(d), T)
    T(; d...)
end

end