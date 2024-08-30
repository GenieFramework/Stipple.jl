module ModelStorage

module Sessions

using Stipple
import GenieSession
import GenieSessionFileSession

export init_from_storage

function model_id(::Type{M}) where M
  Symbol(Stipple.routename(M))
end

function store(model::M, force::Bool = false) where M
  # do not overwrite stored model
  (GenieSession.get(model_id(M), nothing) === nothing || force) && GenieSession.set!(model_id(M), model)

  nothing
end

function init_from_storage( t::Type{M};
                            channel::Union{Any,Nothing} = Stipple.channeldefault(t),
                            kwargs...) where M
  model = Stipple.init(M; channel, kwargs...)
  stored_model = GenieSession.get(model_id(M), nothing)
  CM = Stipple.get_concrete_type(M)

  for f in fieldnames(CM)
    field = getfield(model, f)

    if field isa Reactive
      # restore fields only if a stored model exists, if the field is not part of the internal fields and is not write protected
      if isnothing(stored_model) || f ∈ [Stipple.CHANNELFIELDNAME, Stipple.AUTOFIELDS...] ||
          Stipple.isprivate(f, model) || ! hasproperty(stored_model, f) || ! hasproperty(model, f)
      else
        # restore field value from stored model
        field[!] = getfield(stored_model, f)[]
      end

      # register reactive handlers to automatically save model on session when model changes
      if f ∉ [Stipple.AUTOFIELDS...]
        on(field) do _
          GenieSession.set!(model_id(M), model)
        end
      end
    else
      isnothing(stored_model) || Stipple.isprivate(f, model) || Stipple.isreadonly(f, model) ||
        ! hasproperty(stored_model, f) || ! hasproperty(model, f) || setfield!(model, f, getfield(stored_model, f))
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