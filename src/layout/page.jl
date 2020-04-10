function page(args...; fluid::Bool = false, elemid::String = Stipple.Elements.MOUNT_ELEM, kwargs...)
  Genie.Renderer.Html.div(id=elemid, class="container$(fluid ? "-fluid" : "")", args...; kwargs...)
end

function footer(args...; kwargs...)
  Genie.Renderer.Html.div(class="row", args...; kwargs...)
end

function container(args...; kwargs...)
  Genie.Renderer.Html.div(class="row", args...; kwargs...)
end

function cell(args...; size::Int = 12, kwargs...)
  Genie.Renderer.Html.div(class="col-$size", args...; kwargs...)
end

function sidebar(args...; size::Int = 3, kwargs...)
  Genie.Renderer.Html.div(class="col-$size sidebar", args...; kwargs...)
end

function content(args...; size::Int = 9, kwargs...)
  Genie.Renderer.Html.div(class="col-$size", args...; kwargs...)
end