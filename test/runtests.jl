using Stipple

using Test

@testset "Hello" begin
    @test 1 == 1
end

@testset "World" begin
    @test VERSION <= v"1.11.1"
end