import DataFrames
import JSON
import Stipple
import Genie
import Genie.Renderer.Html: HTMLString, void_element
using Stipple

Genie.Renderer.Html.register_void_element("q!!table", context = @__MODULE__)

const ID = "__id"

Base.@kwdef mutable struct DataTableOptions
  addid::Bool = true
  idcolumn::String = "ID"
  columns::Union{Vector{Symbol},Nothing} = nothing
end

Base.@kwdef mutable struct DataTable{T<:DataFrames.DataFrame}
  data::T = DataFrames.DataFrame()
  opts::DataTableOptions = DataTableOptions()
end

function DataTable(data::T) where {T<:DataFrames.DataFrame}
  DataTable(data, DataTableOptions())
end

function active_columns(t::T) where {T<:DataTable}
  t.opts.columns !== nothing ? t.opts.columns : DataFrames.names(t.data)
end

function columns(t::T) where {T<:DataTable}
  columns = [
    Dict(
        :name       => string(c),
        :required   => true,
        :label      => string(c),
        :align      => "left",
        :field      => string(c),
        :sortable   => true) for c in active_columns(t)
  ]

  if t.opts.addid
    pushfirst!(columns, Dict(:name => t.opts.idcolumn,
                        :required => true,
                        :label => t.opts.idcolumn,
                        :align => "right",
                        :field => t.opts.idcolumn,
                        :sortable => true))
  end

  columns
end

function rows(t::T) where {T<:DataTable}
  count = 0
  rows = []

  for row in DataFrames.eachrow(t.data)
    r = Dict()

    if t.opts.addid
      r[t.opts.idcolumn] = (count += 1)
    end

    r[Symbol(ID)] = count
    for name in active_columns(t)
      r[name] = row[name]
    end

    push!(rows, r)
  end

  rows
end

function data(t::T, fieldname::Symbol;
              datakey = "data_$fieldname", columnskey = "columns_$fieldname") where {T<:DataTable}
  Dict(
    columnskey  => columns(t),
    datakey     => rows(t)
  )
end

function table(fieldname::Symbol;
                rowkey::String = ID, title::String = "",
                datakey::String = "data_$fieldname", columnskey::String = "columns_$fieldname",
                selected::Union{Symbol,Nothing} = nothing,
                hideheader::Bool = false,
                hidebottom::Bool = false,
                args...)

  k = (Symbol(":data"), Symbol(":columns"), Symbol("row-key"))
  v = Any["$fieldname.$datakey", "$fieldname.$columnskey", rowkey]

  if selected !== nothing
    k = (k..., Symbol("selected!sync!"))
    push!(v, selected)
  end

  if hideheader
    k = (k..., Symbol("hide__header"))
    push!(v, true)
  end

  if hidebottom
    k = (k..., Symbol("hide__bottom"))
    push!(v, true)
  end

  Genie.Renderer.Html.div(class="q-pa-md") do
    q!!table(title=title; args..., NamedTuple{k}(v)...)
  end
end

function Stipple.render(t::T, fieldname::Symbol) where {T<:DataTable}
  JSON.json(data(t, fieldname))
end

function Stipple.watch(vue_app_name::String, fieldtype::R{T}, fieldname::Symbol, channel::String, model::M)::String where {M<:Stipple.ReactiveModel,T<:DataTable}
  string(vue_app_name, raw".\$watch('", fieldname, "', function(newVal, oldVal){
    console.log('Table updated');
  });\n\n")
end