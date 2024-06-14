module StippleOffsetArraysExt

using Stipple

isdefined(Base, :get_extension) ? (using OffsetArrays) : (using ..OffsetArrays)

function Stipple.convertvalue(targetfield::Union{Ref{T}, Reactive{T}}, value) where T <: OffsetArrays.OffsetArray
  a = Stipple.stipple_parse(eltype(targetfield), value)

  # if value is not an OffsetArray use the offset of the current array
  if ! isa(value, OffsetArrays.OffsetArray)
    o = targetfield[].offsets
    OffsetArrays.OffsetArray(a, OffsetArrays.Origin(1 .+ o))
  # otherwise use the existing value
  else
    a
  end
end

end