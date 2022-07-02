module ModelStorage

module Sessions

using Stipple
import GenieSession
import GenieSessionFileSession

export init_from_storage

function init_from_storage(m::Type{T};
                            channel::Union{Any,Nothing} = Stipple.channeldefault(),
                            kwargs...)::T where T <: ReactiveModel
  model_id = Symbol(m)
  model = Stipple.init(m; channel, kwargs...)
  stored_model = GenieSession.get(model_id, nothing)
  isnothing(stored_model) || @info("\n\nloading stored model from session...\n\n")

  for f in fieldnames(T)
    field = getfield(model, f)
    if field isa Reactive
      # restore fields only if a stored model exists, if the field is not part of the internal fields and is not write protected
      (
        isnothing(stored_model) || f ∈ [:channels__, Stipple.AUTOFIELDS...] || Stipple.isreadonly(f, model) || Stipple.isprivate(f, model) ||
        ! hasproperty(stored_model, f) || (field[!] = getfield(stored_model, f)[])
      )
      
      # register reactive handlers to automatically save model on session when model changes
      if f ∉ [:channels__, Stipple.AUTOFIELDS...]
        on(field) do _
          GenieSession.set!(model_id, model)
        end
      end
    else
      isnothing(stored_model) || Stipple.isprivate(f, model) || Stipple.isreadonly(f, model) || ! hasproperty(stored_model, f) || setfield!(model, f, getfield(stored_model, f))
    end
  end

  # on isready push model data from session
  on(model.isready) do isready
    isready || return
    push!(model)
  end

  model
end

end # module Sessions

end # module ModelStorage