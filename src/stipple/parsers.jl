# wrapper around Base.parse to prevent type piracy
stipple_parse(::Type{T}, value) where T = Base.parse(T, value)

function stipple_parse(::Type{T}, value::Dict) where T <: AbstractDict
  convert(T, value)
end

function stipple_parse(::Type{T}, value::Dict) where {Tval, T <: AbstractDict{Symbol, Tval}}
  T(zip(Symbol.(string.(keys(value))), values(value)))
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: Number, T2 <: Number}
  convert(T1, value)
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: Integer, T2 <: Number}
  round(T1, value)
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: AbstractArray, T2 <: AbstractArray}
  T1(stipple_parse.(eltype(T1), value))
end

function stipple_parse(::Type{T}, value) where T <: AbstractArray
  convert(T, eltype(T)[value])
end

function stipple_parse(::Type{T}, value) where T <: AbstractRange
  convert(T, value)
end

function stipple_parse(::Type{T}, v::T) where {T}
  v::T
end

function stipple_parse(::Type{Symbol}, s::String)
  Symbol(s)
end