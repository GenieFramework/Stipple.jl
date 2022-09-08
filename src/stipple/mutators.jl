"""
    setindex_withoutwatchers!(field::Reactive, val; notify=(x)->true)
    setindex_withoutwatchers!(field::Reactive, val, keys::Int...; notify=(x)->true)

Change the content of a Reactive field without triggering the listeners.
If keys are specified, only these listeners are exempted from triggering.
"""
function setindex_withoutwatchers!(field::Reactive{T}, val, keys::Int...; notify=(x)->true) where T
  count = 1
  field.o.val = val
  length(keys) == 0 && return field

  for f in Observables.listeners(field.o)
    if in(count, keys)
      count += 1

      continue
    end

    if notify(f)
      try
        Base.invokelatest(f, val)
      catch ex
        @error "Error attempting to invoke $f with $val"
        @error ex
        Genie.Configuration.isdev() && rethrow(ex)
      end
    end

    count += 1
  end

  return field
end

function Base.setindex!(r::Reactive{T}, val, args::Vector{Int}; notify=(x)->true) where T
  setindex_withoutwatchers!(r, val, args...)
end

"""
    setfield_withoutwatchers!(app::ReactiveModel, field::Symmbol, val; notify=(x)->true)
    setfield_withoutwatchers!(app::ReactiveModel, field::Symmbol, val, keys...; notify=(x)->true)

Change the field of a ReactiveModel without triggering the listeners.
If keys are specified, only these listeners are exempted from triggering.
"""
function setfield_withoutwatchers!(app::T, field::Symbol, val, keys...; notify=(x)->true) where T <: ReactiveModel
  f = getfield(app, field)

  if f isa Reactive
    setindex_withoutwatchers!(f, val, keys...; notify = notify)
  else
    setfield!(app, field, val)
  end

  app
end

#===#

function convertvalue(targetfield::Any, value)
  stipple_parse(eltype(targetfield), value)
end

"""
    function update!(model::M, field::Symbol, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
    function update!(model::M, field::Reactive, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
    function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}

Sets the value of `model.field` from `oldval` to `newval`. Returns the upated `model` instance.
"""
function update!(model::M, field::Symbol, newval::T1, oldval::T2)::M where {T1, T2, M<:ReactiveModel}
  f = getfield(model, field)
  if f isa Reactive
    f.r_mode == PRIVATE || f.no_backend_watcher ? f[] = newval : setindex_withoutwatchers!(f, newval, 1)
  else
    setfield!(model, field, newval)
  end
  model
end

function update!(model::M, field::Reactive{T}, newval::T, oldval::T)::M where {T, M<:ReactiveModel}
  field.r_mode == PRIVATE || field.no_backend_watcher ? field[] = newval : setindex_withoutwatchers!(field, newval, 1)

  model
end

function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  setfield!(model, field, newval)

  model
end