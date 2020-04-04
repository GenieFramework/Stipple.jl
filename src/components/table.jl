import Tables
import JSON

mutable struct TableData{T}
  data::T
end

mutable struct TableDataColumnsCollection{T}
  columns::T
end

function columns(table::TableData)
  [Dict(:name => string(c),
        :required => true,
        :label => string(c),
        :align => "left",
        :field => string(c),
        :sortable => true) for c in Tables.columnnames(table.data)] |> TableDataColumnsCollection
end

Base.string(columns::TableDataColumnsCollection) = JSON.json(columns)

function rows(table::TableData)

end