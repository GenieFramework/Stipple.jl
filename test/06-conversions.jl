@testitem "Extensions" setup=[StippleTestSetup] begin
    using DataFrames
    d1 = Dict(:a => [1, 2, 3], :b => ["a", "b", "c"])
    d2 = Dict(:a => [2, 3, 4], :b => ["b", "c", "d"])
    df1 = DataFrame(d1)
    df2 = DataFrame(:a => [[1, 2, 3], [2, 3, 4]], :b => [["a", "b", "c"], ["b", "c", "d"]])
    @test Stipple.stipple_parse(DataFrame, d1) == df1
    @test Stipple.stipple_parse(DataFrame, [d1, d2]) == df2
    @test render(df1) == OrderedDict("a" => [1, 2, 3], "b" => ["a", "b", "c"])

    using OffsetArrays
    @test Stipple.convertvalue(R(OffsetArray([1, 2, 3], -2)), [2, 3, 4]) == OffsetArray([2, 3, 4], -2)
end


# Basic rendering tests (should be enhanced over time perhaps...)
# These tests should probably be repeated in StippleUI to make sure rendering is not overwritten
@testitem "Rendering" setup=[StippleTestSetup] begin
    using DataFrames
    using Tables

    ds = Dict("hello" => [1, 2, 3, 4], "world" => ["five", "six"])
    @test render(ds) == ds

    vd = [Dict("hello" => 1, "world" => 2)]
    @test render(vd) == vd

    df = DataFrame(:a => [1, 2, 3], :b => ["a", "b", "c"])
    @test render(df) == OrderedDict("a" => [1, 2, 3], "b" => ["a", "b", "c"])

    mt = Tables.table([1 2; 3 4])
    @test render(mt) == OrderedDict(:Column1 => [1, 3], :Column2 => [2, 4])
end

@testitem "Parsing" setup=[StippleTestSetup] begin
    struct T1
        c::Int
        d::Int
    end

    struct T2
        a::Int
        b::T1
    end

    t2 = T2(1, T1(2, 3))
    t2_dict = JSON.parse(Stipple.json(t2), dicttype = Dict{String, Any})

    Base.@kwdef struct T3
        c::Int = 1
        d::Int = 3
    end

    Base.@kwdef struct T4
        a::Int = 1
        b::T3 = T3()
    end

    @test Stipple.stipple_parse(T2, t2_dict) == T2(1, T1(2, 3))
    @test Stipple.stipple_parse(T3, Dict()) == T3(1, 3)
    @test Stipple.stipple_parse(T4, Dict()) == T4(1, T3(1, 3))

    @test Stipple.stipple_parse(Union{Nothing, String}, "hi") == "hi"
    @test Stipple.stipple_parse(Union{Nothing, String}, SubString("hi")) == "hi"
    # the following test is only valid for Julia 1.7 and above because specifity of methods
    # changed in Julia 1.7. As the latest LTS version of Julia is now 1.10, we accept that
    # this specific stipple_parse for Union{Nothing, T} fails for Julia 1.6
    # people can define explicit methods for their types if they need this functionality
    @static if VERSION ≥ v"1.7"
        @test Stipple.stipple_parse(Union{Nothing, SubString}, "hi") == SubString("hi")
    end
    @test Stipple.stipple_parse(Union{Nothing, String}, nothing) === nothing

    # defined above
    # @enum Fruit apple=1 orange=2 kiwi=3
    @test Stipple.stipple_parse(Fruit, "apple") == apple
end
