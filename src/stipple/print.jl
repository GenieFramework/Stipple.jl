function print_object(io, obj::T, omit = nothing, compact = false) where T
    # currently no different printing for compact = true ...
    fields = [p for p in propertynames(obj)]
    omit !== nothing && setdiff!(fields, omit)

    println(io, match(r"^#*([^!]+)", String(T.name.name)).captures[1])
    for field in fields
        println(io, "    $field: ", Observables.to_value(getproperty(obj, field)))
    end
end

function print_object(io, obj::T, omit = nothing, compact = false) where T <: ReactiveModel
    fields = [p for p in propertynames(obj)]
    omit !== nothing && setdiff!(fields, omit)
    internal_or_auto = true

    println(io, "Instance of '" * match(r"^#*([^!]+)", String(T.name.name)).captures[1] * "'")
    for fieldname in fields
        field = getproperty(obj, fieldname)
        fieldmode = isprivate(fieldname, obj) ? "private" : isreadonly(fieldname, obj) ? "out" : "in"
        fieldtype = if field isa Reactive
            if fieldname in AUTOFIELDS
                "autofield, $fieldmode"
            else
                if internal_or_auto
                    println(io)
                    internal_or_auto = false
                end
                fieldmode
            end
        else
            if fieldname in INTERNALFIELDS
                "internal"
            else
                if internal_or_auto
                    println(io)
                    internal_or_auto = false
                end
                "$fieldmode, non-reactive"
            end
        end

        println(io, "    $fieldname ($fieldtype): ", Observables.to_value(field))
    end
end

# default show used by Array show
function Base.show(io::IO, obj::ReactiveModel)
    compact = get(io, :compact, true)
    print_object(io, obj, compact)
end

# default show used by display() on the REPL
function Base.show(io::IO, mime::MIME"text/plain", obj::ReactiveModel)
    compact = get(io, :compact, false)
    print_object(io, obj, compact)
end