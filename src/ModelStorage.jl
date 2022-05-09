module ModelStorage

module Sessions

using Stipple
import GenieSession
import GenieSessionFileSession

export init_from_storage

function init_from_storage(m::Type{T}; channel::Union{Any,Nothing} = params(Stipple.CHANNELPARAM, nothing), kwargs...)::T where T
  model_id = Symbol(m)
  instance = GenieSession.get(model_id, Stipple.init(m; channel, kwargs...))
  channel !== nothing && Stipple.setchannel(instance, channel) # allow explicit overriding of channel

  @show instance
  @show channel
  @show instance.no_of_clusters[]

  # register reactive handlers to automatically save model on session when model changes
  for f in fieldnames(typeof(instance))
    if isa(getfield(instance, f), Reactive) # let's not handle isready here, it has a separate handler
      on(getfield(instance, f)) do _
        GenieSession.set!(model_id, instance)
      end
    end
  end

  # on isready push model data from session
  on(instance.isready) do isready
    isready || return

    for f in fieldnames(typeof(instance))
      f in Stipple.AUTOFIELDS && continue # let's not set the value of the auto fields (eg isready, isprocessing)
      setfield!(instance, f, getfield(instance, f))
    end

    channel !== nothing && Stipple.setchannel(instance, channel) # allow explicit overriding of channel

    sleep(0.1)

    push!(instance)
  end

  instance
end

end # module Sessions

end # module ModelStorage