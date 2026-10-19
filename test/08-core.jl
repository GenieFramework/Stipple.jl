@testitem "Exporting and loading model field values" setup=[StippleTestSetup] begin
    # Disable model storage to prevent loading stale TestApp2 from previous test
    current_storage = Stipple.use_model_storage()
    Stipple.enable_model_storage(false)

    @app TestApp2 begin
        @in i = 100
        @out s = "Hello"
        @private x = 4
    end

    model = @init TestApp2

    exported_values = Stipple.ModelStorage.model_values(model)
    @test exported_values[:i] == 100
    @test exported_values[:s] == "Hello"
    @test exported_values[:x] == 4

    values_json = Stipple.json(exported_values)
    exported_values_json = Stipple.ModelStorage.model_values(model, json = true)
    @test values_json == exported_values_json

    values_dict = Dict(:i => 20, :s => "world", :x => 5)
    Stipple.ModelStorage.load_model_values!(model, values_dict)
    @test model.i[] == 20
    @test model.s[] == "world"
    @test model.x[] == 5

    values_json = Dict(:i => 30, :s => "zero", :x => 50) |> Stipple.json |> string
    Stipple.ModelStorage.load_model_values!(model, values_json)
    @test model.i[] == 30
    @test model.s[] == "zero"
    @test model.x[] == 50

    Stipple.enable_model_storage(current_storage)
end

@testitem "Finalizers" setup=[StippleTestSetup] begin
    current_storage = Stipple.use_model_storage()
    Stipple.enable_model_storage(false)
    @app MyApp begin
        @in i = 100
        @out s = "Hello"
        @private x = 4

        @onchange isready begin
            @info "Model is ready"
        end
    end

    model = @init MyApp
    @test length(model.isready.o.listeners) == 2
    @test_logs (:info, "Calling finalizers") notify(model, Val(:finalize), "")
    @test length(model.isready.o.listeners) == 0

    model = @init MyApp
    @event MyApp :finalize begin
        @info "Custom finalizer"
    end

    @test_logs (:info, "Custom finalizer") notify(model, Val(:finalize), "")
    @test length(model.isready.o.listeners) == 2

    Stipple.enable_model_storage(current_storage)
end

@testitem "String Macro js\" with and without interpolation" setup=[StippleTestSetup] begin
    who = "World"
    @test json(js"console.log('Hello World')") == "console.log('Hello World')"
    @test json(js"""console.log("Hello $who")""") == raw"""console.log("Hello $who")"""
    @test json(js"console.log('Hello $who')"i) == "console.log('Hello World')"
    @test json(js"""console.log("Hello $who")"""i) == """console.log("Hello World")"""

    # \n and \t are unescaped regardless of the `i` flag
    @test json(js"line1\nline2\ttab") == "line1\nline2\ttab"
    @test json(js"line1\nline2\ttab"i) == "line1\nline2\ttab"

    # \$ yields a literal '$', even with interpolation enabled (escapes it from parsing)
    @test json(js"price: \$5"i) == raw"price: $5"
    @test json(js"price: \$5") == raw"price: $5"

    # consecutive backslashes are halved, regardless of the `i` flag
    @test json(js"a\\b") == raw"a\b"
    @test json(js"a\\b"i) == raw"a\b"
    @test json(js"""a\\\\b""") == raw"a\\b"

    # an unsupported flag warns but still constructs a JSONText
    @test_logs (:warn, r"Only 'i' flag") eval(Meta.parse(raw"""js"text"x"""))

    # an invalid escape character throws instead of being silently passed through
    threw = try
        eval(Meta.parse(raw"""js"bad \x escape" """))
        false
    catch e
        e isa LoadError && e.error isa ArgumentError && occursin("invalid escape character", e.error.msg)
    end
    @test threw
end
