# wrapper around Base.parse to prevent type piracy
function stipple_parse(::Type{T}, value) where T
  if isstructtype(T) && value isa Dict
    ff = [String(f) for f in fieldnames(T)]
    kk = String.(keys(value))
    # if all fieldnames are present, generate the type directly from the fields
    if all(ff .∈ RefValue(kk))
      T([stipple_parse(Ft, value[String(f)]) for (f, Ft) in zip(ff, fieldtypes(T))]...)
    # otherwise, try to generate it via kwargs, e.g. when the type is defined via @kwdef
    else
      T(; (Symbol(k) => v for (k,v) in value)...)
    end
  else
    Base.parse(T, value)
  end
end

function stipple_parse(::Type{T}, value::AbstractString) where T<:AbstractString
  convert(T, value)
end

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
function stipple_parse(D::Type{<:AbstractDict{K, V}}, value::AbstractDict) where {K, V}
  if D isa LittleDict
    D( stipple_parse(Vector{K}, collect(keys(value))), stipple_parse(Vector{V}, collect(values(value))) )
  else
    D( zip(Vector{K}(stipple_parse(Vector{K}, collect(keys(value)))), stipple_parse(Vector{V}, collect(values(value)))) )
  end
end

# String to Integer
function stipple_parse(::Type{T}, value::String) where T <: Integer
  Base.parse(T, value)
end

#String to AbstractFloat
function stipple_parse(::Type{T}, value::String) where T<:AbstractFloat
  if value == "__nan__"
    NaN
  elseif value == "__inf__"
    Inf
  elseif value == "__neginf__"
    -Inf
  else
    Base.parse(T, value)
  end
end

# Union with Nothing
function stipple_parse(::Type{Union{Nothing, T}}, ::Nothing) where T
  nothing
end

# Union with Nothing, part I
function stipple_parse(::Type{Union{Nothing, T}}, value) where T
  stipple_parse(T, value)
end

# Union with Nothing, part II
function stipple_parse(::Type{Union{Nothing, T}}, value::Union{Nothing, T}) where T
  stipple_parse(T, value)
end

# define an explicit function for Type{Any} to avoid ambiguities between Type{Union{Nothing, T}} and Type{T} (line 35 and line 64) in case of T == Any
function stipple_parse(::Type{Any}, v::T) where {T}
  v::T
end

# parsing of enum types
function stipple_parse(::Type{T}, s::String) where T<:Enum
    instances(T)[findfirst(==(Symbol(s)), Symbol.(instances(T)))]
end
function stipple_parse(::Type{T}, n::Integer) where T<:Enum
  T(n)
end