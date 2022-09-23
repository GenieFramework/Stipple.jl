const UPDATE_MUTABLE = Ref(false)

"""
    setindex_withoutwatchers!(field::Reactive, val; notify=(x)->true)
    setindex_withoutwatchers!(field::Reactive, val, keys::Int...; notify=(x)->true)

Change the content of a Reactive field without triggering the listeners.
If keys are specified, only these listeners are exempted from triggering.
"""
function setindex_withoutwatchers!(field::Reactive{T}, val, keys::Int...; notify=(x)->true) where T
  field.o.val = val

  callwatchers(field, val, keys...; notify)

  return field
end

function callwatchers(field, val, keys...; notify)
  isempty(keys) && return field

  count = 1
  for f in Observables.listeners(field.o)
    if in(count, keys)
      count += 1

      continue
    end

    if notify(f)
      try
        Base.invokelatest(f, val)
      catch ex
        @error "Error attempting to invoke handler $count for field $field with value $val"
        @error ex
        Genie.Configuration.isdev() && rethrow(ex)
      end
    end

    count += 1
  end
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
    setindex_withoutwatchers!(f, val, keys...; notify)
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
  ischanged = false

  if f isa Reactive
    if UPDATE_MUTABLE[] # experimental
      if newval isa Vector || newval isa Dict
        push!(getproperty(model, field)[] |> empty!, newval...)
        ischanged = true
      elseif newval isa Ref
        getproperty(model, field)[][] = newval[]
        ischanged = true
      elseif isstructtype(typeof(newval)) && ! isa(newval, AbstractString)
        object = getproperty(model, field)[]
        for field in fieldnames(typeof(newval))
          setfield!(object, field, getfield(newval, field))
        end
        ischanged = true
      end
    end

    if ischanged
      f.r_mode == PRIVATE || f.no_backend_watcher ? nothing : callwatchers(f, newval, 1)
    else
      f.r_mode == PRIVATE || f.no_backend_watcher ? f[] = newval : setindex_withoutwatchers!(f, newval, 1)
    end
  else
    setfield!(model, field, newval)
  end

  model
end

function update!(model::M, field::Reactive{T}, newval::T, oldval::T)::M where {T, M<:ReactiveModel}
  update!(model, Symbol(field), newval, oldval)
end

function update!(model::M, field::Any, newval::T, oldval::T)::M where {T,M<:ReactiveModel}
  setfield!(model, field, newval)

  model
end