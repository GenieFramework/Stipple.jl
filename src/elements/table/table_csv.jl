import CSV

function table(path::String; args...) :: String
  table(CSV.file(path))
end