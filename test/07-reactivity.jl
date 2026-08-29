@testitem "Indexing with `end`" setup=[StippleTestSetup] begin
    using DataFrames
    r = R([1, 2, 3])
    on(r) do r
        r[end - 1] += 1
    end
    @test r[end] == 3
    r[end] = 4
    @test r[end - 1] == 3
    @test r[end] == 4

    df = DataFrame(:a => 1:3, :b => 12:14)
    @test df[end, 1] == 3
    @test df[end, end] == 14
    @test df[:, end] == 12:14
end

@testitem "Synchronization" setup=[StippleTestSetup] begin
    # synchronize! is defined for AbstractObservables, so works for both Observables and Reactives
    o = Observable(0)
    o1 = Observable(1)
    o2 = Observable(2)
    o3 = Observable(3)
    r1 = Reactive(4)

    synchronize!(o1, o, update = false)
    synchronize!(o2, o, update = false)
    synchronize!(o3, o, update = false)
    synchronize!(r1, o, update = false)

    @test o1[] == 1
    @test o2[] == 2
    @test o3[] == 3
    @test r1[] == 4

    o[] = 10
    @test o1[] == 10
    @test o2[] == 10
    @test o3[] == 10
    @test r1[] == 10

    o1[] = 20
    @test o[] == 20
    @test o2[] == 20
    @test o3[] == 20
    @test r1[] == 20

    o2[] = 30
    @test o[] == 30
    @test o1[] == 30
    @test o3[] == 30
    @test r1[] == 30

    r1[] = 40
    @test o[] == 40
    @test o1[] == 40
    @test o2[] == 40
    @test o3[] == 40

    @test_logs (:warn, "Synchronization loop detected, skipping synchronization") synchronize!(o1, o)
    @test_logs (:warn, "Synchronization loop detected, skipping synchronization") synchronize!(o, o3)

    unsynchronize!(o1)
    o1[] = 50
    @test o[] == 40
    @test o2[] == 40
    @test o3[] == 40
    @test r1[] == 40

    o[] = 60
    @test o1[] == 50

    unsynchronize!(o)
    o[] = 70
    @test o1[] == 50
    @test o2[] == 60
    @test o3[] == 60

    o = Observable(0)
    o1 = Observable(1)
    synchronize!(o1, o; bidirectional = false)

    @test length(o.listeners) == 1
    @test length(o1.listeners) == 0

    unsynchronize!(o1)
    @test length(o.listeners) == 1

    unsynchronize!(o1, o)
    @test length(o.listeners) == 0
end

