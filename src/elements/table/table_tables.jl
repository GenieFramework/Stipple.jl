import Tables

function table(t::Any; args...) :: String
  rows = Tables.rows(t)

  grh.table(class="table"; args...) do
    grh.thead() do
      grh.tr() do
        grh.collection(Tables.columnnames(Tables.columns(t))) do item
          grh.th(scope="col") do
            item |> string
          end
        end
      end
    end *
    grh.tbody() do
      grh.collection(rows |> collect) do row
        grh.tr() do
          grh.collection([Tables.getcolumn(row, col) for col in Tables.columnnames(row)]) do item
            grh.td() do
              item |> string
            end
          end
        end
      end
    end
  end
end