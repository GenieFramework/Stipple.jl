using TestItemRunner

@testmodule StippleTests begin
    using Stipple
    using Stipple.Genie.HTTPUtils.HTTP

    # Stipple.assets_config.version = version
    version = Genie.Assets.package_version(Stipple)

    function string_get(x; kwargs...)
        String(HTTP.get(x, retries = 0, status_exception = false; kwargs...).body)
    end

    function get_channel(s::String)
        match(r"\(\) => window.create[^']+'([^']+)'", s).captures[1]
    end

    function get_debounce(port, modelname)
        version = Genie.Assets.package_version("Stipple")
        s = string_get("http://localhost:$port/stipple.jl/$version/assets/js/$modelname.js")
        parse(Int, match(r"_.debounce\(.+?(\d+)\)", s).captures[1])
    end

    @vars TestMixin begin
        j = 101
        t = "World", PRIVATE
    end
end

@run_package_tests