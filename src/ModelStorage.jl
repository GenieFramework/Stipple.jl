module ModelStorage

module Sessions

using Stipple
import GenieSession
import GenieSessionFileSession

export init_from_storage

function init_from_storage(::Type{M};
                            channel::Union{Any,Nothing} = Stipple.channeldefault(),
                            kwargs...) where M
  model_id = Symbol(Stipple.routename(M))
  model = Stipple.init(M; channel, kwargs...)
  stored_model = GenieSession.get(model_id, nothing)

  CM = Stipple.get_concrete_type(M)
  for f in fieldnames(CM)
    field = getfield(model, f)
    if field isa Reactive
      # restore fields only if a stored model exists, if the field is not part of the internal fields and is not write protected
      (
        isnothing(stored_model) || f ∈ [Stipple.CHANNELFIELDNAME, Stipple.AUTOFIELDS...] || Stipple.isreadonly(f, model) || Stipple.isprivate(f, model) ||
        ! hasproperty(stored_model, f) || (field[!] = getfield(stored_model, f)[])
      )

      # register reactive handlers to automatically save model on session when model changes
      if f ∉ [Stipple.CHANNELFIELDNAME, Stipple.AUTOFIELDS...]
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