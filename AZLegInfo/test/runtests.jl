using Test, AZLegInfo, HTTP, Sockets, p7zip_jll

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

    @testset "download_voting_histories" begin
        error_message(f) = try f(); "" catch err; sprint(showerror, err) end
        file_url(path) = "file://" * (Sys.iswindows() ? "/" * replace(path, '\\' => '/') : path)

        mktempdir() do dir
            function make_zip(name, files)
                for (path, source) in files
                    mkpath(dirname(joinpath(dir, path)))
                    source isa String ? cp(source, joinpath(dir, path)) : write(joinpath(dir, path), source)
                end
                cd(dir) do
                    run(pipeline(`$(p7zip()) a -tzip $name $(unique(first.(splitpath.(first.(files)))))`, stdout=devnull))
                end
                joinpath(dir, name)
            end

            folder = "57L 2R Member Voting History"
            histories_zip = make_zip("histories.zip", [
                "$folder/Test Voting History.pdf" => data("voting_history.pdf"),
                "$folder/Pena Voting History.pdf" => data("voting_history_pena.pdf"),
                "$folder/Empty Voting History.pdf" => data("voting_history_empty.pdf"),
                "__MACOSX/$folder/._Test Voting History.pdf" => b"macOS metadata, not a PDF",
            ])
            duplicate_zip = make_zip("duplicate.zip", [
                "a/Test Voting History.pdf" => data("voting_history.pdf"),
                "b/Test Voting History.pdf" => data("voting_history.pdf"),
            ])

            responses = Dict(
                "/histories.zip" => (200, read(histories_zip)),
                "/duplicate.zip" => (200, read(duplicate_zip)),
                "/report.pdf" => (200, read(data("votes_ruled.pdf"))),
            )
            port, socket = listenany(ip"127.0.0.1", 49152)
            close(socket)
            server = HTTP.serve!("127.0.0.1", port) do request
                status, body = get(responses, request.target, (404, "Not Found"))
                HTTP.Response(status, body)
            end
            base = "http://127.0.0.1:$port"

            # A private temp directory, so other processes' temp files don't count.
            scratch = mktempdir()
            try
                histories = withenv("TMPDIR" => scratch, "TMP" => scratch, "TEMP" => scratch) do
                    @test tempdir() == scratch
                    download_voting_histories("$base/histories.zip")
                end

                @test histories isa Dict{String,<:Any}
                @test sort(collect(keys(histories))) == ["NOVOTES", "PEÑA", "TESTMEMBER"]
                @test histories["TESTMEMBER"] == extract_voting_history(data("voting_history.pdf"))
                @test histories["PEÑA"] == extract_voting_history(data("voting_history_pena.pdf"))
                @test size(histories["PEÑA"], 1) == 9
                @test size(histories["NOVOTES"], 1) == 0
                @test names(histories["NOVOTES"]) == names(histories["TESTMEMBER"])

                withenv("TMPDIR" => scratch, "TMP" => scratch, "TEMP" => scratch) do
                    @test download_voting_histories(file_url(histories_zip)) == histories

                    @test occursin("404", error_message(() -> download_voting_histories("$base/missing.zip")))
                    @test occursin("Not a zip file", error_message(() -> download_voting_histories("$base/report.pdf")))
                    @test occursin("Two PDFs in the zip are for TESTMEMBER",
                                   error_message(() -> download_voting_histories("$base/duplicate.zip")))
                end

                # The downloaded zip and extracted PDFs are gone, errors included.
                @test isempty(readdir(scratch))
            finally
                close(server)
                rm(scratch; recursive=true, force=true)
            end
        end
    end
end
