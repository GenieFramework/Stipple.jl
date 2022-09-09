using Stipple
using Stipple.ReactiveTools

function process_data()
  @binding message = ""
  @binding reverse_message = ""
  @binding counter = 0
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

# global model

route("/") do
  process_data()
  # global model = @init()
  # @show typeof(model)
  # model |> handlers |> ui |> html
  @init() |> handlers |> ui |> html
end

up()