export page, container, row, cell, sidebar, content

function page(elemid, args...; kwargs...)
  Genie.Renderer.Html.div(id=elemid, args...; kwargs...)
end

function container(args...; kwargs...)
  Genie.Renderer.Html.div(class="row", args...; kwargs...)
end

const row = container

function cell(args...; size::Int=0, kwargs...)
  Genie.Renderer.Html.div(class="col-$(size > 0 ? size : "12")", args...; kwargs...)
end

function sidebar(args...; size::Int = 3, kwargs...)
  Genie.Renderer.Html.div(class="col-$size sidebar", args...; kwargs...)
end

function content(args...; size::Int = 9, kwargs...)
  Genie.Renderer.Html.div(class="col-$size", args...; kwargs...)
end