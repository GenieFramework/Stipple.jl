const UPDATE_MUTABLE = RefValue(false)

"""
    setindex_withoutwatchers!(field::Reactive, val)
    setindex_withoutwatchers!(field::Reactive, val, priorities::Int...)

Change the content of a Reactive field without triggering the listeners.
If priorities are specified, the respective listeners are exempted from being triggered.
"""
function setindex_withoutwatchers!(field::Reactive{T}, val, priorities::Int...) where T
  field.o.val = val
  notify(field, ∉(priorities))

  return field
end

function callwatchers(field, val, keys...; notify)
  isempty(keys) && return field

  count = 1
  for x in Observables.listeners(field.o)
    if in(count, keys)
      count += 1

      continue
    end

    # compatibility with Observables 0.5
    f = x isa Pair ? x[2] : x

    if notify(f)
      try
        Base.invokelatest(f, val)
      catch ex
        error_message = """

        Error attempting to invoke handler.

          Handler:
          $(methods(f))
          $( code_lowered(f, (typeof(val),)) )

          Type of argument:
          $((isa(field, Reactive) ? field[] : field) |> typeof)

          Value:
          $val

          Exception:
          $ex

        """
        @error error_message exception=(ex, catch_backtrace())

        rethrow(ex)
      end
    end

    count += 1
  end
end

"""
    setfield_withoutwatchers!(app::ReactiveModel, field::Symmbol, val)
    setfield_withoutwatchers!(app::ReactiveModel, field::Symmbol, val, priorities...)

Change the field of a ReactiveModel without triggering the listeners.
If priorities are specified, only these listeners are exempted from triggering.
"""
function setfield_withoutwatchers!(app::T, field::Symbol, val, priorities...) where T <: ReactiveModel
  f = getfield(app, field)

  if f isa Reactive
    setindex_withoutwatchers!(f, val, priorities...)
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
    if UPDATE_MUTABLE[] # experimental, default is currently false
      object = f[]
      if newval isa Vector || newval isa Dict
        push!(object |> empty!, newval...)
        ischanged = true
      elseif newval isa Ref
        object[] = newval[]
        ischanged = true
      elseif isstructtype(typeof(newval)) && ! isa(newval, AbstractString)
        for field in fieldnames(typeof(newval))
          setfield!(object, field, getfield(newval, field))
        end
        ischanged = true
      end
    end

    if ischanged
      f.r_mode == PRIVATE || f.no_backend_watcher || notify(f, ≠(1))
    else
      # we changed filtering of watchers to priorities, so no need to differentiate here
      setindex_withoutwatchers!(f, newval, 1)
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
