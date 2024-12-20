module ModelStorage
using JSON3
using Stipple
import Stipple: INTERNALFIELDS, AUTOFIELDS, Reactive

const DEFAULT_EXCLUDE = vcat(INTERNALFIELDS, AUTOFIELDS)

"""
    model_values(model::M; fields::Vector{Symbol} = Symbol[], exclude::Vector{Symbol} = Symbol[], json::Bool = false) where M

Exports the values of reactive fields from a Stipple model. Returns either a Dict of field-value pairs or a JSON string
if json=true.

### Example

    @app TestApp2 begin
        @in i = 100
        @out s = "Hello"
        @private x = 4
    end

    model = @init TestApp2
    exported_values = Stipple.ModelStorage.model_values(model)
"""
function model_values(model::M; fields::Vector{Symbol} = Symbol[], exclude::Vector{Symbol} = Symbol[], json::Bool = false) where M
  field_list = isempty(fields) ? fieldnames(M) : fields
  excluded_fields = vcat(DEFAULT_EXCLUDE, exclude)

  field_dict = Dict(field => getfield(model, field)[] for field in field_list 
                  if field ∉ excluded_fields && getfield(model, field) isa Stipple.Reactive)

  json ? JSON3.write(field_dict) : field_dict
end

"""
    load_model_values!(model::M, values::Dict{Symbol, Any}) where M
    load_model_values!(model::M, values::String) where M

Loads values into the fields of a ReactiveModel. Accepts either a Dict of field-value pairs or a JSON string.

### Example

    values_dict = Dict(:i => 20, :s => "world", :x => 5)
    Stipple.ModelStorage.load_model_values!(model, values_dict)
"""
function load_model_values!(model::M, values::Dict{Symbol, Any}) where M
  model_field_list = fieldnames(M)
  excluded_fields = DEFAULT_EXCLUDE

  for (field, value) in values
    if field ∉ excluded_fields && field ∈ model_field_list
      model_field = getfield(model, field)

      if model_field isa Reactive
        model_field[] = value
      end
    end
  end

  return model
end

function load_model_values!(model::M, values::String) where M
  load_model_values!(model, Dict(JSON3.read(values)))
end

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
      if isnothing(stored_model) || f ∈ [Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS...] ||
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
