# checking properties of Reactive types
@nospecialize

isprivate(field::Reactive) = field.r_mode == PRIVATE

function isprivate(fieldname::Symbol, model::M)::Bool where {M<:ReactiveModel}
  fieldname ∈ INTERNALFIELDS && return true

  field = getfield(model, fieldname)
  field isa Reactive ? isprivate(field) : get(model.modes__, fieldname, 0) == PRIVATE
end


isreadonly(field::Reactive) = field.r_mode  ∈ [READONLY, JSFUNCTION]

function isreadonly(fieldname::Symbol, model::M)::Bool where {M<:ReactiveModel}
  field = getfield(model, fieldname)
  field isa Reactive ? isreadonly(field) : get(model.modes__, fieldname, 0) == READONLY
end


has_frontend_watcher(field::Reactive) = ! (field.r_mode in [READONLY, PRIVATE] || field.no_frontend_watcher)

function has_frontend_watcher(fieldname::Symbol, model::M)::Bool where {M<:ReactiveModel}
  getfield(model, fieldname) isa Reactive && has_frontend_watcher(getfield(model, fieldname))
end


has_backend_watcher(field::Reactive) = ! (field.r_mode == PRIVATE || field.no_backend_watcher)

function has_backend_watcher(fieldname::Symbol, model::M)::Bool where {M<:ReactiveModel}
  getfield(model, fieldname) isa Reactive && has_backend_watcher(getfield(model, fieldname))
end

@specialize