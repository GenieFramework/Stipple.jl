module MyGenie

using Stipple, Stipple.ReactiveTools
using StippleUI
using Genie

@app MyApp begin
    @in x = 1
    @in y = x + 2

    @onchange x on_x()
    @onchange x, y on_x_y()
end

#   New alternative handler syntax for
# - keeping long handler functions outside of the model definition
# - redefining handlers without redefining the model

@handler MyApp function on_x()
    @info "x changed"
end

@handler MyApp function on_x_y()
    @info "x or y changed to $x, $y"
end

ui() = cell(class = "st-module", [
    row("Hello World {{ x }}, {{ y }}")

    slider(1:10, :x)
    slider(11:20, :y)
])

@page("/", ui, model = MyApp)

@route("/page2", named = R"Page 3", begin
    model = @init(MyApp)
    html!(ui2; layout = DEFAULT_LAYOUT(), context = @__MODULE__, model)
end)

# ------------ optional initializing function  -------------
# required if module shall be loaded via `using MyGenie`

@init_function

# ----- alternative customizable initializing function -----

# function __init__()
#     @init_routes
# end

# ------------- optional precompilation statements -------------

@stipple_precompile begin
    @precompile_route("/", ui, MyApp)
    @precompile_route("/page2", ui, MyApp)

    precompile_get("/")
    precompile_get("/page2")

    # add whatever should be precompiled
    # <...>
end

end # module MyGenie
