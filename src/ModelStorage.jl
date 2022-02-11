module ModelStorage

module Sessions

using Stipple
using Genie.Sessions

export init_from_storage

function init()
  Genie.Sessions.init()
end

function init_from_storage(m::Type{T})::T where T
  model_id = Symbol(m)
  instance = Genie.Sessions.get(model_id, nothing)

  model = if instance !== nothing
    Stipple.init(m; channel = getchannel(instance))
  else
    m |> Stipple.init
  end

  on(model.isready) do _
    if instance !== nothing
      for f in fieldnames(typeof(model))
        setfield!(model, f, getfield(instance, f))
      end

      push!(model)
    end
  end

  for f in fieldnames(typeof(model))
    if isa(getfield(model, f), Reactive)

      on(getfield(model, f)) do _
        Genie.Sessions.set!(model_id, model)
      end
    end
  end

  model
end

end # module Sessions

end # module ModelStorage