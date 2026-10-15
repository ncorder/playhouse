using Test, Pluto

notebook = joinpath(@__DIR__, "dimensionReduction.jl")

@testset "dimensionReduction.jl" begin
	m = Module()
	mktempdir() do dir
		cd(() -> Base.include(m, notebook), dir)
	end

	@testset "Party" begin
		@test Set(keys(m.party)) == Set(m.members)
		@test count(==("R"), m.memberParty) == 35
		@test count(==("D"), m.memberParty) == 27
		@test m.partyColor == [p == "R" ? "red" : "blue" for p in m.memberParty]
		@test m.memberLabels[findfirst(==("GRESS"), m.members)] == "GRESS (R)"
	end

	@testset "Data" begin
		@test size(m.X, 2) == 62
		@test all(isfinite, m.X)
	end

	@testset "Embeddings" begin
		for embedding in (m.transformation, m.embed, m.tsneModel', m.mdsEmbed)
			@test size(embedding) == (2, 62)
			@test all(isfinite, embedding)
		end
	end

	@testset "Clustering" begin
		for clusters in (m.kmeansClusters, m.hclustClusters)
			@test length(clusters) == 62
			@test sort(unique(clusters)) == 1:m.k
		end
	end

	@testset "LDA" begin
		@test size(m.ldaEmbed) == (1, 62)
		r = m.ldaEmbed[1, m.memberParty .== "R"]
		d = m.ldaEmbed[1, m.memberParty .== "D"]
		@test maximum(r) < minimum(d) || maximum(d) < minimum(r)
	end

	@testset "Plots" begin
		for p in (m.P, m.umapPlot, m.tsnePlot, m.mdsPlot, m.kmeansPlot, m.hclustPlot)
			@test length(p.Plot.data[1][:x]) == length(p.Plot.data[1][:y]) == 62
		end
		for p in (m.P, m.umapPlot, m.tsnePlot, m.mdsPlot)
			@test p.Plot.data[1][:marker_color] == m.partyColor
			@test p.Plot.data[1][:text] == m.memberLabels
		end
		for p in (m.kmeansPlot, m.hclustPlot)
			@test p.Plot.data[1][:marker_line_color] == m.partyColor
		end
		@test [t[:name] for t in m.ldaPlot.Plot.data] == ["R", "D"]
		@test [t[:marker_color] for t in m.ldaPlot.Plot.data] == ["red", "blue"]
		@test sum(length(t[:x]) for t in m.ldaPlot.Plot.data) == 62
	end
end

@testset "Pluto" begin
	mktempdir() do dir
		path = joinpath(dir, "dimensionReduction.jl")
		cp(notebook, path)
		session = Pluto.ServerSession()
		nb = Pluto.SessionActions.open(session, path; run_async=false)
		for cell in nb.cells
			cell.errored && println(cell.code, "\n", cell.output.body)
		end
		@test !any(cell.errored for cell in nb.cells)
		Pluto.SessionActions.shutdown(session, nb)
	end
end
