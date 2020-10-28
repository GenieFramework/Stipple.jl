export page, row, cell

function page(elemid, args...; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                                channel::String = Genie.config.webchannels_default_route , head_content::String = "", kwargs...)
  Stipple.Layout.layout(Genie.Renderer.Html.div(id=elemid, args...; kwargs...), partial=partial, title=title, class=class,
                        style=style, head_content=head_content, channel=channel)
end

function row(args...; kwargs...)
  kwargs = NamedTuple(Dict(kwargs...), :class, "row")
  Genie.Renderer.Html.div(args...; kwargs...)
end

function cell(args...; size::Int=0, kwargs...)
  kwargs = NamedTuple(Dict(kwargs...), :class, "col col-12 col-sm$(size > 0 ? "-$size" : "")")
  Genie.Renderer.Html.div(args...; kwargs...)
end
