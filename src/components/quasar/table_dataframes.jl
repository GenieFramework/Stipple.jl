import DataFrames
import JSON
import Stipple
import Genie
import Genie.Renderer.Html: HTMLString, void_element

Genie.Renderer.Html.register_void_element("q_____table", context = @__MODULE__)

const ID = "__id"

function columns(t::DataFrames.DataFrame)
  [Dict(:name       => string(c),
        :required   => true,
        :label      => string(c),
        :align      => "left",
        :field      => string(c),
        :sortable   => true) for c in DataFrames.names(t)]
end

function rows(t::DataFrames.DataFrame)
  count = 0
  rows = []

  for row in DataFrames.eachrow(t)
    r = Dict()

    r[Symbol(ID)] = (count += 1)
    for name in DataFrames.names(t)
      r[name] = row[name]
    end

    push!(rows, r)
  end

  rows
end

function data(t::DataFrames.DataFrame, fieldname::Symbol; datakey = "data_$fieldname", columnskey = "columns_$fieldname")
  Dict(
    columnskey  => columns(t),
    datakey     => rows(t)
  )
end

function table(fieldname::Symbol; rowkey::String = ID, title::String = "", datakey::String = "data_$fieldname", columnskey::String = "columns_$fieldname", args...)
  Genie.Renderer.Html.div(class="q-pa-md") do
    q_____table(title=title; args..., NamedTuple{(Symbol(":data"),Symbol(":columns"),Symbol("row-key"))}(("$fieldname.$datakey","$fieldname.$columnskey",rowkey))...)
  end
end

function Stipple.render(t::DataFrames.DataFrame, fieldname::Symbol)
  JSON.json(data(t, fieldname))
end