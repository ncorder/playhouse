using Test, AZLegInfo

@testset "AZLegInfo" begin
    @testset "Bill API" begin
        @test getBillId("SB1010", 130) == 83585
    end

    # Fixtures are an 80-row synthetic vote history spanning 3 pages, one
    # drawn with ruling lines (lattice) and one without (stream).
    @testset "extract_tables_from_pdf: $name" for name in ("votes_ruled", "votes_unruled")
        df = extract_tables_from_pdf(joinpath(@__DIR__, "data", "$name.pdf"))

        @test names(df) == ["column_1", "column_2", "column_3", "column_4", "column_5"]
        @test Vector(df[1, :]) == ["Bill", "Short Title", "Date", "Motion", "Vote"]
        @test Vector(df[2, :]) == ["SB1000", "appropriation; item 0", "02/01/2026", "Final Read", "Y"]
        @test Vector(df[end, :]) == ["SB1079", "appropriation; item 79", "02/24/2026", "3rd Read", "EXC"]

        votes = df[df.column_1 .!= "Bill", :]
        @test size(votes, 1) == 80
        @test votes.column_1 == ["SB$(1000 + i)" for i in 0:79]
    end

    @test_throws ArgumentError extract_tables_from_pdf("does_not_exist.pdf")
end
