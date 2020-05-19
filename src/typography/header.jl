function header(args...; size::Int = 1, kwargs...)
  1 <= size <= 6 || error("Invalid header size - expected 1:6")
  func = getproperty(Genie.Renderer.Html, Symbol("h$size"))
  func(class="text-h$size", args...; kwargs...)
end