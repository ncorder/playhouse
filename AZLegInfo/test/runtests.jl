using Test, AZLegInfo

data(name) = joinpath(@__DIR__, "data", name)
vote_row(i) = ["SB$(1000 + i)", "appropriation; item $i", "02/$(lpad(i % 28 + 1, 2, '0'))/2026",
               isodd(i) ? "3rd Read" : "Final Read", ["Y", "N", "NV", "EXC"][i % 4 + 1]]

@testset "AZLegInfo" begin
    @testset "Bill API" begin
        @test getBillId("SB1010", 130) == 83585
    end

    # Fixtures are an 80-row synthetic vote table spanning 3 pages, one
    # drawn with ruling lines (lattice) and one without (stream).
    @testset "extract_tables_from_pdf" begin
        ruled = extract_tables_from_pdf(data("votes_ruled.pdf"))
        @test names(ruled) == ["column_1", "column_2", "column_3", "column_4", "column_5"]
        @test Vector(ruled[1, :]) == ["Bill", "Short Title", "Date", "Motion", "Vote"]
        votes = ruled[ruled.column_1 .!= "Bill", :]
        @test [Vector(r) for r in eachrow(votes)] == vote_row.(0:79)

        # Guessed columns can merge cells (the title on page 1 does), but
        # no text is dropped and words keep their spaces.
        unruled = extract_tables_from_pdf(data("votes_unruled.pdf"))
        lines = Set(join(filter(!isempty, collect(r)), " ") for r in eachrow(unruled))
        @test all(join(vote_row(i), " ") in lines for i in 0:79)

        # Explicit column boundaries, in points from the left of the page.
        unruled = extract_tables_from_pdf(data("votes_unruled.pdf"); columns=[208, 306, 364, 420])
        votes = unruled[startswith.(unruled.column_1, "SB"), :]
        @test [Vector(r) for r in eachrow(votes)] == vote_row.(0:79)

        @test_throws ArgumentError extract_tables_from_pdf("does_not_exist.pdf")
    end

    # Same layout as the House Member Voting History PDFs; bills split
    # across page breaks, "NOW:" titles, and chapters V, 191, "1 E" and none.
    @testset "extract_voting_history" begin
        lines = split.(readlines(data("voting_history_expected.tsv")), '\t')
        header, expected = Symbol.(lines[1]), lines[2:end]

        votes = @test_logs extract_voting_history(data("voting_history.pdf"))

        @test size(votes, 1) == length(expected)
        @test all(==("TESTMEMBER"), votes.member)
        for (i, col) in enumerate(header)
            @test string.(votes[!, col]) == getindex.(expected, i)
        end

        @test_throws ArgumentError extract_voting_history(data("votes_ruled.pdf"))
    end
end
