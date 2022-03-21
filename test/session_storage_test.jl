using Genie
using Stipple, Stipple.ModelStorage.Sessions
using Stipple.Pages

isempty(Genie.SECRET_TOKEN[]) && Genie.Generator.write_secrets_file(@__DIR__)
Sessions.init()

@reactive mutable struct Person <: ReactiveModel
  name::String = "Bob"
end

function ui(model = init_from_storage(Person))
  on(model.isready) do _
    @show model.name[]
    @show getchannel(model)

    push!(model, channel = getchannel(model))
  end

  page(model, [
    input("", type="text", @bind(:name))
  ])
end

Page("/", view = ui())

up(async = false)