using Stipple
using Test

@vars TestMixin begin
    j = 101
    t = "World", PRIVATE
end

@testset "Classic API" begin
    @vars TestApp begin
        i = 100
        s = "Hello", READONLY
    end
    
    function handlers(model)
        on(model.i) do i
            model.s[] = "$i"
        end

        model
    end

    model = TestApp |> init |> handlers
    model2 = TestApp |> init |> handlers
    
    # channels have to be different
    @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @test propertynames(model) == (:channel__, :modes__, :isready, :isprocessing, :i, :s)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"
end

@testset "Classic API with mixins" begin
    @vars TestApp begin
        i = 100
        s = "Hello"
        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin pre_ _post
    end

    function handlers(model)
        on(model.i) do i
            model.s[] = "$i"
        end

        model
    end

    model = TestApp |> init |> handlers
    @test propertynames(model) == (:channel__, :modes__, :isready, :isprocessing, :i, :s, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)
end

using Stipple.ReactiveTools

@testset "Reactive API (explicit)" begin
    @app TestApp2 begin
        @in i = 100
        @out s = "Hello"
    
        @onchange i begin
            s = "$i"
        end
    end

    model = TestApp2 |> init |> handlers
    model2 = TestApp2 |> init |> handlers
    
    # channels have to be different
    @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @test propertynames(model) == (:channel__, :modes__, :isready, :isprocessing, :i, :s)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"
end

@testset "Reactive API (explicit) with mixins" begin
    @app TestApp begin
        @in i = 100
        @out s = "Hello"
    
        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin "pre_" "_post"
    end

    model = TestApp |> init |> handlers
    @test propertynames(model) == (:channel__, :modes__, :isready, :isprocessing, :i, :s, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)
end

@testset "Reactive API (implicit)" begin
    @eval @app begin
        @in i2 = 100
        @out s2 = "Hello"

        @onchange i2 begin
            s2 = "$i2"
        end
    end

    @eval model = @init
    @eval model2 = @init
    
    # channels have to be different
    @eval @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @eval @test propertynames(model) == (:channel__, :modes__, :isready, :isprocessing, :i2, :s2)

    # check reactivity
    @eval model.i2[] = 20
    @test model.s2[] == "20"
end

@testset "Reactive API (implicit) with mixins" begin
    @eval @app begin
        @in i3 = 100
        @out s3 = "Hello"
    
        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin "pre_" "_post"
    end

    @eval model = @init
    @eval @test propertynames(model) == (:channel__, :modes__, :isready, :isprocessing, :i3, :s3, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)
end
