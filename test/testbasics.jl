using Stipple 
import Stipple: opts, OptDict

# Define the model 
Stipple.@kwdef mutable struct Example <: ReactiveModel 
    s::R{String} = "..."
    n::R{Int} = 1
    a::R{Array} = [3, 2, 1]
end

model = Stipple.init(Example())

function ui()
    page(vm(model), class = "container", title = "Hello Stipple", [
        h1("Hello World")
        p("I am the first paragraph and I bring you")
        p("", @text(:s))
    ]) |> html
end

route("/", ui)
