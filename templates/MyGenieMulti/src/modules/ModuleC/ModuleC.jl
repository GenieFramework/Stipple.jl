module ModuleC

using Stipple, Stipple.ReactiveTools
using StippleUI

@app MyApp begin
    @in x = 1
    @in y = x + 2

    @onchange x on_x()
    @onchange x, y on_x_y()
end

@handler MyApp function on_x()
    @info "x changed"
end

@handler MyApp function on_x_y()
    @info "x or y changed to $x, $y"
end

modulename = String(Base.nameof(@__MODULE__))
ui() = cell(class = "st-module", [
    row(h1(modulename))
    row(h2("{{ x }}, {{ y }}"))

    card(class = "q-my-lg", style = "max-width = 300px", [
        cardsection(slider(1:100, :x))
        cardsection(slider(11:200, :y))
    ])

    separator(class = "q-my-lg")

    h3("Other Modules")
    row(gutter = "md", [
        a(href = "/", "Module A", @showif(modulename[end] != 'A'))
        a(href = "/b", "Module B", @showif(modulename[end] != 'B'))
        a(href = "/c", "Module C", @showif(modulename[end] != 'C'))
        a(href = "/d", "Module D", @showif(modulename[end] != 'D'))
    ])
])

@page("/c", ui, model = MyApp)

# ------------ optional initializing function  -------------
# required if module shall be loaded via `using MyGenieMulti`

@init_function

# ----- alternative customizable initializing function -----

# function __init__()
#     @init_routes
# end



end # module MyGenie
