module ModelStorage

module Sessions

using Stipple
import GenieSession
import GenieSessionFileSession

export init_from_storage

function init_from_storage(m::Type{T})::T where T
  model_id = Symbol(m)
  model = m |> Stipple.init

  on(model.isready) do isready
    isready || return

    instance = GenieSession.get(model_id, nothing)

    if instance !== nothing
      for f in fieldnames(typeof(model))
        setfield!(model, f, getfield(instance, f))
      end

      sleep(0.1)

      push!(model)
    end
  end

  for f in fieldnames(typeof(model))
    if isa(getfield(model, f), Reactive)
      on(getfield(model, f)) do _
        GenieSession.set!(model_id, model)
      end
    end
  end

  model
end

end # module Sessions

end # module ModelStorage