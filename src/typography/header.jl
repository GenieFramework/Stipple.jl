function header(args...; size::Int = 1, kwargs...)
  Genie.Renderer.Html.h1(class="h$size", args...; kwargs...)
end