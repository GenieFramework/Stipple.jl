module ModuleBB
# loading this module throws a warning, because the module name is not the same as the file name

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

ui() = cell(class = "st-module", [
    row(h1("Module B {{ x }}, {{ y }}"))

    card(class = "q-my-lg", style = "max-width = 300px", [
        cardsection(slider(1:10, :x))
        cardsection(slider(11:20, :y))
    ])
])

@page("/B", ui, model = MyApp)

# ------------ optional initializing function  -------------
# required if module shall be loaded via `using MyGenieMulti`

@init_function

# ----- alternative customizable initializing function -----

# function __init__()
#     @init_routes
# end



end # module MyGenie
