export page, row, cell

function page(elemid, content::Union{String,Vector}; kwargs...)
  content = if isa(content, Vector)
    push!(pushfirst!(content, "<st-dashboard>"), "</st-dashboard>")
  else
    string("<st-dashboard>", content, "</st-dashboard>")
  end
  kwargs = Stipple.kwargs_merge(delete!(Dict(kwargs...), :id), :id, elemid)

  Genie.Renderer.Html.div(content; kwargs...)
end

function row(args...; kwargs...)
  kwargs = Stipple.kwargs_merge(Dict(kwargs...), :class, "row")
  Genie.Renderer.Html.div(args...; kwargs...)
end

function cell(args...; size::Int=0, kwargs...)
  kwargs = Stipple.kwargs_merge(Dict(kwargs...), :class, "col col-12 col-sm$(size > 0 ? "-$size" : "")")
  Genie.Renderer.Html.div(args...; kwargs...)
end