module StippleDataFramesExt

using Stipple

isdefined(Base, :get_extension) ? (using DataFrames) : (using ..DataFrames)

# DataFrame(d::Dict) will generate multiple rows if a field contains a Vector
# to prevent this we need to wrap vectors in a RefValue()
function dataframe(d::AbstractDict)
  DataFrame([p[1] => p[2] isa Vector ? Base.RefValue(p[2]) : p[2] for p in d])
end

function Stipple.stipple_parse(::Type{DF} where DF <: DataFrames.AbstractDataFrame, d::Vector)
  isempty(d) ? DF() : reduce(vcat, dataframe.(d))
end

function Stipple.stipple_parse(::Type{DF} where DF <: DataFrames.AbstractDataFrame, d::Dict)
  DataFrame(d)
end

function Stipple.render(df::DataFrames.AbstractDataFrame)
  OrderedDict(zip(names(df), eachcol(df)))
end
  
end