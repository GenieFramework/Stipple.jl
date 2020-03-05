import DataFrames

function table(df::DataFrames.DataFrame)
  output = """
  <table class="table">

  </table>
  """
end

function thead()
  output = """
  <thead>

  </thead>
  """
end

function tr()
  output = """
  <tr>

  </tr>
  """
end

function th()
  output = """
  <th>

  </th>
  """
end

function tbody()
  output = """
  <tbody>

  </tbody>
  """
end

function td()
  output = """
  <td>

  </td>
  """
end