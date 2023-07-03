function Stipple.stipple_parse(::Type{DF} where DF <: DataFrames.AbstractDataFrame, d::Vector)
  isempty(d) ? DF() : reduce(vcat, DataFrames.DataFrame.(d))
end

function Stipple.render(df::DataFrames.DataFrame)
  OrderedDict(zip(names(df), eachcol(df)))
end