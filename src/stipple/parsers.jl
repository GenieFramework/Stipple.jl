# wrapper around Base.parse to prevent type piracy
stipple_parse(::Type{T}, value) where T = Base.parse(T, value)

# function stipple_parse(::Type{T}, value::Dict) where T <: AbstractDict
#   convert(T, value)
# end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: Number, T2 <: Number}
  convert(T1, value)
end

function stipple_parse(::Type{T1}, value::T2) where {T1 <: Integer, T2 <: Number}
  round(T1, value)
end

# AbstractArray's of same dimension
function stipple_parse(::Type{T1}, value::T2) where {N, T1 <: AbstractArray{<:Any, N}, T2 <: AbstractArray{<:Any, N}}
  T1(stipple_parse.(eltype(T1), value))
end

# atomic value to Array
function stipple_parse(::Type{T}, value) where {N, T <: AbstractArray{<:Any, N}}
  convert(T, Array{eltype(T), N}(reshape([value], fill(1, N)...)))
end

# Vector to Matrix, in particular Vector of Vectors to Matrix
function stipple_parse(::Type{T1}, value::T2) where {T1 <: AbstractArray{<:Any, 2}, T2 <: AbstractArray{<:Any, 1}}
  reduce(hcat, stipple_parse.(Vector{eltype(T1)}, value))
end

function stipple_parse(::Type{T}, value) where T <: AbstractRange
  convert(T, value)
end

function stipple_parse(::Type{T}, v::T) where {T}
  v::T
end

# String to Symbol
function stipple_parse(::Type{Symbol}, s::String)
  Symbol(s)
end
# untyped Dicts to typed Dict's
function stipple_parse(::Type{<:AbstractDict{K, V}}, value::AbstractDict{String, <:Any}) where {K, V}
  Dict( zip(Vector{K}(stipple_parse(Vector{K}, collect(keys(value)))), stipple_parse(Vector{V}, collect(values(value)))) )
end

# String to Integer
function stipple_parse(::Type{T}, value::String) where T <: Integer
  Base.parse(T, value)
end

#String to AbstractFloat
function stipple_parse(::Type{T}, value::String) where T<:AbstractFloat
  Base.parse(T, value)
end