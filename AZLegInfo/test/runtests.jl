using Test, AZLegInfo, HTTP, Sockets, p7zip_jll

data(name) = joinpath(@__DIR__, "data", name)
error_message(f) = try f(); "" catch err; sprint(showerror, err) end
file_url(path) = "file://" * (Sys.iswindows() ? "/" * replace(path, '\\' => '/') : path)

@testset "AZLegInfo" begin
    @testset "Bill API" begin
        @test getBillId("SB1010", 130) == 83585
    end

    @testset "getSession57HouseLegislatureMemberVotingHistory" begin
        # voting_history.pdf has the same layout as the House Member Voting
        # History PDFs: bills split across page breaks, "NOW:" titles, and
        # chapters V, 191, "1 E" and none. voting_history_pena.pdf has its
        # first five bills; voting_history_empty.pdf has no votes.
        lines = split.(readlines(data("voting_history_expected.tsv")), '\t')
        header, expected = Symbol.(lines[1]), lines[2:end]
        matches_expected(votes, rows) =
            size(votes, 1) == length(rows) &&
            all(string.(votes[!, col]) == getindex.(rows, i) for (i, col) in enumerate(header))

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
            other_pdf_zip = make_zip("other.zip", ["c/Report.pdf" => data("votes_ruled.pdf")])

            responses = Dict(
                "/histories.zip" => (200, read(histories_zip)),
                "/duplicate.zip" => (200, read(duplicate_zip)),
                "/other.zip" => (200, read(other_pdf_zip)),
                "/report.pdf" => (200, read(data("votes_ruled.pdf"))),
            )
            port, socket = listenany(ip"127.0.0.1", 49152)
            close(socket)
            server = HTTP.serve!("127.0.0.1", port) do request
                status, body = get(responses, request.target, (404, "Not Found"))
                HTTP.Response(status, body)
            end
            base = "http://127.0.0.1:$port"

            scratch = mktempdir()
            try
                # No warnings: every PDF's counts match its printed totals. This
                # first call also starts the JVM, whose Tabula jar stays in a
                # temp directory until Julia exits.
                histories = @test_logs getSession57HouseLegislatureMemberVotingHistory("$base/histories.zip")

                @test histories isa Dict{String,<:Any}
                @test sort(collect(keys(histories))) == ["NOVOTES", "PEÑA", "TESTMEMBER"]
                @test matches_expected(histories["TESTMEMBER"], expected)
                @test all(==("TESTMEMBER"), histories["TESTMEMBER"].member)
                @test matches_expected(histories["PEÑA"], expected[1:9])
                @test all(==("PEÑA"), histories["PEÑA"].member)
                @test size(histories["NOVOTES"], 1) == 0
                @test names(histories["NOVOTES"]) == names(histories["TESTMEMBER"])

                # A private temp directory, so other processes' temp files don't count.
                withenv("TMPDIR" => scratch, "TMP" => scratch, "TEMP" => scratch) do
                    @test tempdir() == scratch

                    @test getSession57HouseLegislatureMemberVotingHistory("$base/histories.zip") == histories
                    @test getSession57HouseLegislatureMemberVotingHistory(file_url(histories_zip)) == histories

                    @test occursin("404", error_message(() -> getSession57HouseLegislatureMemberVotingHistory("$base/missing.zip")))
                    @test occursin("Not a zip file", error_message(() -> getSession57HouseLegislatureMemberVotingHistory("$base/report.pdf")))
                    @test occursin("Two PDFs in the zip are for TESTMEMBER",
                                   error_message(() -> getSession57HouseLegislatureMemberVotingHistory("$base/duplicate.zip")))
                    @test occursin("Not a Member Voting History PDF",
                                   error_message(() -> getSession57HouseLegislatureMemberVotingHistory("$base/other.zip")))
                end

                # The downloaded zip and extracted PDFs are gone, errors included.
                @test isempty(readdir(scratch))
            finally
                close(server)
                rm(scratch; recursive=true, force=true)
            end
        end

        @test var"57SessionHouseLegislatureMemberVotingHistory" === getSession57HouseLegislatureMemberVotingHistory
        @test Symbol("57SessionHouseLegislatureMemberVotingHistory") in names(AZLegInfo)
        @test :getSession57HouseLegislatureMemberVotingHistory in names(AZLegInfo)

        # The real dataset: https://codeberg.org/AZLegInfo/datasets
        histories = getSession57HouseLegislatureMemberVotingHistory()
        @test length(histories) == 62
        @test sum(v -> size(v, 1), values(histories)) == 67945
        @test size(histories["ALLEN"], 1) == 277
        @test all(member -> all(==(member), histories[member].member), keys(histories))
        @test haskey(histories, "PEÑA") && haskey(histories, "CONTRERAS L")
    end
end
