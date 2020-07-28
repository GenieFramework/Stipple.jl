module Generator

using Pkg
using Genie, Genie.Generator

function newapp(app_name::String; ui::Bool = true, charts::Bool = true, autostart::Bool = true, kwargs...)
  Genie.Generator.newapp(app_name; autostart = false, kwargs...)

  ui && Pkg.add("StippleUI")
  charts && Pkg.add("StippleCharts")

  autostart && Genie.up()
end

end