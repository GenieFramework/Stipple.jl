using Stipple
using Stipple.ReactiveTools

@binding const number = 2
@binding const number2 = 2

function process_data()
  @binding message = ""
  @binding reverse_message = ""
  @binding counter = 0

  # @private account_number = 1234
  # @readonly name = "Adrian"
  # @field cache = String[]

  # @binding a::Array = [3, 2, 1]

  # @jsfn d::Dict{Symbol, Any} = Dict(:hello => "World")
  # @jsfn f::JSONText = JSONText("function() { return Example.n + 1 }")
end

function handlers(model)
  on(model.isready) do val
    if val
      model.message[] = "Hello World!"
    end
  end

  on(model.message) do message
    model.reverse_message[] = uppercase(reverse(message))
  end

  on(model.counter) do counter
    @info counter
  end

  model
end

function ui(model)
  [
    page(model, [
      h1([
        span([], @text(:message))
        "<->"
        span([], @text(:reverse_message))
        " @ "
        span([], @text(:counter))
        input("", @bind(:counter))
      ])
    ], @iif(:isready))
  ]
end

global model

route("/") do
  process_data()
  global model = @init()
  model |> handlers |> ui |> html
  # @init() |> handlers |> ui |> html
end

up()