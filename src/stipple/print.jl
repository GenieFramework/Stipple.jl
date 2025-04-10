function print_object(io, obj::T, compact = false; omit = [:handlers__, :observerfunctions__]) where T <: ReactiveModel
    # currently no different printing for compact = true ...
    fields = [p for p in propertynames(obj)]
    omit !== nothing && setdiff!(fields, omit)
    internal_or_auto = true

    app = match(r"^#*([^!]+)", String(T.name.name)).captures[1]
    if app == "Main_ReactiveModel" && parentmodule(T) != Main
        app = String(nameof(parentmodule(T)))
    end
    println(io, "Instance of '$app'")
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
        displaysize = get(io, :displaysize, (1, 80))
        limit = get(io, :limit, true)
        ioc = IOContext(IOBuffer(), :compact => compact, :limit => limit, :displaysize => displaysize)
        show(ioc, "text/plain", Observables.to_value(field))
        println(io, "    $fieldname ($fieldtype): ", String(take!(ioc.io)))
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