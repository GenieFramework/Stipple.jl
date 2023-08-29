module StippleDataFramesExt

@static if isdefined(Base, :get_extension)
  using Stipple
  using DataFrames
end

function Stipple.stipple_parse(::Type{DF} where DF <: DataFrames.AbstractDataFrame, d::Vector)
  isempty(d) ? DF() : reduce(vcat, DataFrames.DataFrame.(d))
end

function Stipple.render(df::DataFrames.AbstractDataFrame)
  OrderedDict(zip(names(df), eachcol(df)))
end
  
end