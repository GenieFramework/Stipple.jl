import DataFrames

function table(df::DataFrames.DataFrame; args...) :: String
  grh = Genie.Renderer.Html

  grh.table(class="table"; args...) do
    grh.thead() do
      grh.tr() do
        grh.collection(names(df)) do item
          grh.th(scope="col") do
            item |> string
          end
        end
      end
    end *
    grh.tbody() do
      grh.collection(eachrow(df) |> collect) do row
        grh.tr() do
          grh.collection(Array(row)) do item
            grh.td() do
              item |> string
            end
          end
        end
      end
    end
  end
end