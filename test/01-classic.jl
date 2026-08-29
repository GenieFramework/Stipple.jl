# This file tests the legacy classic API of Stipple.
# For modern apps we strongly recommend to use the reactive API instead, which is more flexible and powerful.
@testitem "Classic API" setup=[StippleTestSetup] begin
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
    @test propertynames(model) == tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"
end

@testitem "Classic API with mixins" setup=[StippleTestSetup] begin
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
    @test propertynames(model) == tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)
end
