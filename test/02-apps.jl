@testitem "Reactive API (explicit)" setup=[StippleTestSetup] begin
    #using .StippleTestSetup
    using Stipple.ReactiveTools
    # Disable model storage to prevent state pollution when TestApp2 is redefined later
    current_storage = Stipple.use_model_storage()
    Stipple.enable_model_storage(false)

    @app TestApp2 begin
        @in i = 100
        @out s = "Hello"

        @onchange i begin
            s = "$i"
        end
    end

    model = @init TestApp2
    model2 = @init TestApp2

    # channels have to be different
    @test model.channel__ != model2.channel__

    # check whether fields are correctly defined
    @test propertynames(model) == tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s)

    # check reactivity
    model.i[] = 20
    @test model.s[] == "20"

    Stipple.enable_model_storage(current_storage)
end

@testitem "Reactive API (explicit) with mixins and handlers" setup=[StippleTestSetup] begin
    @eval @app TestApp begin
        @in i = 100
        @out s = "Hello"

        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin "pre_" "_post"

        @onchange i begin
            s = "$i"
        end
    end

    @eval model = TestApp |> init |> TestApp_handlers
    @test propertynames(model) ==  tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i, :s, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)

    # check reactivity
    @eval model.i[] = 20
    @test model.s[] == "20"

    @eval @debounce TestApp i 101
    @eval @debounce TestApp (a, b, c) 101
    @test Stipple.DEBOUNCE[TestApp][:i] == 101

    @eval @clear_debounce TestApp
    @test haskey(Stipple.DEBOUNCE, TestApp) == false
end

@testitem "Reactive API (implicit)" setup=[StippleTestSetup] begin
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
    @eval @test propertynames(model) ==  tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i2, :s2)

    # check reactivity
    @eval model.i2[] = 20
    @test model.s2[] == "20"

    # check field-specific debouncing
    @eval @debounce i3 101
    @eval @debounce (a, b, c) 101
    @test Stipple.DEBOUNCE[Stipple.@type()][:i3] == 101

    @eval @clear_debounce
    @test haskey(Stipple.DEBOUNCE, Stipple.@type()) == false
end

@testitem "Reactive API (implicit) with mixins and handlers" setup=[StippleTestSetup] begin
    @eval @app begin
        @in i3 = 100
        @out s3 = "Hello"

        @mixin TestMixin
        @mixin mixin_::TestMixin
        @mixin TestMixin "pre_" "_post"

        @onchange i3 begin
            s3 = "$i3"
        end
    end

    @eval model = @init
    @eval @test propertynames(model) ==  tuple(Stipple.INTERNALFIELDS..., Stipple.AUTOFIELDS..., :i3, :s3, :j, :t, :mixin_j, :mixin_t, :pre_j_post, :pre_t_post)

    @eval model.i3[] = 20
    @test model.s3[] == "20"
end

@testitem "Reactive API with mixins and handlers" setup=[StippleTestSetup] begin
    @eval @app VueCopyButton begin
        @out copied = false
    end
    
    @eval @methods VueCopyButton [
        :handleCopy => js"""function () {
            const text = typeof this.text === 'function' ? this.text() : this.text;
            Quasar.copyToClipboard(text).then(() => {
                this.copied = true;
                setTimeout(() => {
                this.copied = false;
                }, 700);
            });
        }
        """
    ]
    
    @eval @props VueCopyButton Stipple.opts(
        text = Stipple.opts(
            type = [js"String", js"Function"],
            required = true
        )
    )
    
    @eval @template VueCopyButton button(
        icon = R"this.copied ? 'check' : 'content_copy'",
        aria__label = R"this.copied ? 'Copied!' : 'Copy to clipboard'",
        flat = true, size = "sm",
        @click("this.handleCopy")
    )
    
    # defining a simple app with a copy button
    @eval @app MyApp begin
        @in text = "Copy this text"
    end

    @eval @components MyApp VueCopyButton

    component_str = json(Stipple.COMPONENTS[MyApp][:VueCopyButton])
    @test contains(component_str, repr("props"))
    @test contains(component_str, "<button icon=")
end

@testitem "Adding and removing stylesheets" setup=[StippleTestSetup] begin
    function my_css()
        [style("""
            .stipple-core .q-table tbody tr { color: inherit; }
        """)]
    end

    add_css(my_css)
    @test Stipple.Layout.THEMES[][end] == my_css

    n = length(Stipple.Layout.THEMES[])
    remove_css(my_css)
    @test length(Stipple.Layout.THEMES[]) == n - 1
    @test findfirst(==(my_css), Stipple.Layout.THEMES[]) === nothing

    add_css(my_css)
    @test Stipple.Layout.THEMES[][end] == my_css
    remove_css(my_css, byname = true)
    @test findfirst(==(my_css), Stipple.Layout.THEMES[]) === nothing
end