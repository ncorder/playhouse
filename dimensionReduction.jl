### A Pluto.jl notebook ###
# v1.0.4

using Markdown
using InteractiveUtils

# ╔═╡ 388a54f4-e21f-466c-8e85-78e492f99b0b
begin
	using Pkg
	Pkg.add(url="https://codeberg.org/AZLegInfo/AZLegInfo.jl")
	Pkg.add(["MultivariateStats", "DataFrames", "NamedArrays", "UMAP", "PlutoPlotly", "TSne", "Clustering", "Distances"])
	using AZLegInfo, MultivariateStats, Statistics, NamedArrays, LinearAlgebra, UMAP, PlutoPlotly, TSne, Clustering, Distances
end

# ╔═╡ c177a4fe-c38f-11f1-b899-0bbf875c6316
md"""
## Dimension Reduciton on the Arizona House Member Voting History (MVH)
"""

# ╔═╡ e03f9602-4cc3-4dd1-ab47-16364bbc9320
md"""
###  About the DataSet

For this tutorial, we will be using the Member Voting History (MVH) for the 57th House Legislature. This data was sent to me in a PDF and extracted using multiple techniques.

It is now an exported part of the AZLegInfo library.
"""

# ╔═╡ 9d5ceeb1-f87d-419d-9cac-955466f1cbe5
# Representative Gress's MVH
session57HouseLegislativeMemberVotingHistory["GRESS"]

# ╔═╡ c458eeaa-4310-4b07-97e5-7d5311bc58d1
# Member Voting History Using One-Hot Encoding
oneHotEncodedMVH = getSession57HouseLegislativeMemberVotingHistory_OneHotEncoding()

# ╔═╡ 22d75c76-5807-486c-8614-334a776ef8aa
md"""
# Replace Rare Bills
"""

# ╔═╡ 1d93fad2-f72a-4fb4-9a72-780a907960bd
function removeRareItems(A::NamedArray, n=80)::NamedArray
	"""
	Removes rows where above n% of values are missing

	Expects:
		A NamedArray

	Returns:
		A NamedArray
	"""
    keep = [
        i for i in axes(A, 1)
        if count(ismissing, view(A, i, :)) / size(A, 2) < n / 100
    ]

    return A[keep, :]
end

# ╔═╡ 4c1a3eeb-8e7b-45b5-820a-f25c7b8c302b
md"""
## Replacing Empty Values with the Mean for that Row
"""

# ╔═╡ b5bd976a-1278-49ac-907a-ea23e8a51ff6
function replaceMissingWithMean(A::NamedArray)::NamedArray
	"""
	Replaces missing values with the mean value for that row.

	Expects:
		One-Hot Encoded MVH NamedArray
	Returns:
		NamedArray
	"""

	# Temporary Fix
    data = Matrix{Union{Missing,Float64}}(A)
    A = NamedArray(
        data,
        (names(A, 1), names(A, 2)),
        ("row", "column")
    )
	
	for row in eachrow(A)
		meanVal = mean(skipmissing(row))
		for i in eachindex(row)
			if ismissing(row[i])
				row[i] = meanVal
			end
		end
	end
	return A
end

# ╔═╡ a89dd7b5-7ffb-46bb-b63e-6bd29a52a15a
oneHotEncodedMVH_Meanized = replaceMissingWithMean(removeRareItems(oneHotEncodedMVH))

# ╔═╡ 61eb9919-23c4-49c7-aa2d-1f3ecefcd35d
md"""
## Party Affiliation
"""

# ╔═╡ e257d5e4-3afa-4912-8b28-e78f33e4ff38
# Party from https://www.azleg.gov/MemberRoster/?body=H
party = Dict(
	"ABEYTIA" => "D",
	"AGUILAR" => "D",
	"ALLEN" => "R",
	"AUSTIN" => "D",
	"BIASIUCCI" => "R",
	"BLACKMAN" => "R",
	"BLATTMAN" => "D",
	"BLISS" => "R",
	"CARBONE" => "R",
	"CARTER N" => "R",
	"CARTER P" => "R",
	"CAVERO" => "D",
	"CHAPLIK" => "R",
	"CONNOLLY" => "D",
	"CONTRERAS L" => "D",
	"CONTRERAS P" => "D",
	"CREWS" => "D",
	"DE LOS SANTOS" => "D",
	"DIAZ" => "R",
	"FINK" => "R",
	"GARCIA" => "D",
	"GILLETTE" => "R",
	"GRESS" => "R",
	"GRIFFIN" => "R",
	"GUTIERREZ" => "D",
	"HEAP" => "R",
	"HENDRIX" => "R",
	"HERNANDEZ A" => "D",
	"HERNANDEZ C" => "D",
	"HERNANDEZ L" => "D",
	"KESHEL" => "R",
	"KOLODIN" => "R",
	"KUPPER" => "R",
	"LIGUORI" => "D",
	"LIVINGSTON" => "R",
	"LOPEZ" => "R",
	"LUNA-NÁJERA" => "D",
	"MÁRQUEZ" => "D",
	"MARSHALL" => "R",
	"MARTINEZ" => "R",
	"MATHIS" => "D",
	"NGUYEN" => "R",
	"OLSON" => "R",
	"PEÑA" => "R",
	"PESHLAKAI" => "D",
	"PINGERELLI" => "R",
	"POWELL" => "R",
	"REIM" => "R",
	"RIVERO" => "R",
	"SANDOVAL" => "D",
	"SIMACEK" => "D",
	"MONTENEGRO" => "R",
	"STAHL HAMILTON" => "D",
	"TAYLOR" => "R",
	"TRAVERS" => "D",
	"TSOSIE" => "D",
	"VILLEGAS" => "D",
	"VOLK" => "D",
	"WAY" => "R",
	"WENINGER" => "R",
	"WILLOUGHBY" => "R",
	"WILMETH" => "R"
)

# ╔═╡ 8c2d86b1-cb6e-441a-9c36-73ba4559591e
begin
	members = names(oneHotEncodedMVH_Meanized, 2)
	memberParty = [party[member] for member in members]
	memberLabels = members .* " (" .* memberParty .* ")"
	partyColor = [p == "R" ? "red" : "blue" for p in memberParty]
end

# ╔═╡ 2e4ceee2-52ec-4633-a1dd-2a75ed23f72a
md"""
# PCA Anaysis
"""

# ╔═╡ 3f55631c-61a1-43ff-aaeb-d5862344d6d6
begin
	X = Matrix{Float64}(oneHotEncodedMVH_Meanized)

	model = fit(PCA, X, maxoutdim=2)
	transformation = transform(model, X)
end

# ╔═╡ 70a1a572-4a64-4567-b67c-1ad62b75ef53
begin	
    P = plot(
            scatter(
                x = transformation[1,:],
                y = transformation[2,:],
                mode = "markers",
                text = memberLabels,
                hovertemplate = "%{text}<extra></extra>",
                marker = attr(size=16, color=partyColor)
            )
        )
    P
    
end

# ╔═╡ 4ee91e6b-1af7-40c9-9d50-6df3142a93bc
md"""
## UMAP
"""

# ╔═╡ e6feb5ac-062a-4442-aef0-dcdce3df8c56
begin
	model_umap = UMAP.fit(X,2)
	embed = model_umap.embedding

	umapPlot = plot(
            scatter(
                x = embed[1,:],
                y = embed[2,:],
                mode = "markers",
                text = memberLabels,
                hovertemplate = "%{text}<extra></extra>",
                marker = attr(size=16, color=partyColor)
            )
        )
    umapPlot

    
# 2. Save it to an HTML file
open("./my_plot.html", "w") do io
    # If using PlutoPlotly, extract the underlying Plot object with p.Plot
    PlotlyBase.to_html(io, umapPlot.Plot) 
end
end

# ╔═╡ c4ad8b78-370b-4eab-b7c8-b7f9184af8c3
md"""
## TSNE
"""

# ╔═╡ f8309839-4d51-4325-8863-626ba7ee5306
begin
	tsneModel = tsne(X',2,0,1000)

	tsnePlot = plot(
            scatter(
                x = tsneModel[:,1],
                y = tsneModel[:,2],
                mode = "markers",
                text = memberLabels,
                hovertemplate = "%{text}<extra></extra>",
                marker = attr(size=16, color=partyColor)
            )
        )
    tsnePlot

end

# ╔═╡ 56236407-ffa3-4c96-af65-6c2bfbaad6de
md"""
## MDS
"""

# ╔═╡ ef159cb9-18b2-4475-b6cc-e9d9a9616465
begin
	model_mds = fit(MDS, X, maxoutdim=2, distances=false)
	mdsEmbed = predict(model_mds)

	mdsPlot = plot(
            scatter(
                x = mdsEmbed[1,:],
                y = mdsEmbed[2,:],
                mode = "markers",
                text = memberLabels,
                hovertemplate = "%{text}<extra></extra>",
                marker = attr(size=16, color=partyColor)
            )
        )
    mdsPlot
end

# ╔═╡ a147a085-b970-46b8-815e-c42c42f07cca
md"""
# Clustering
"""

# ╔═╡ 952ed242-edb1-44db-bdc1-ab0c26f51255
begin
	k = 3

	kmeansClusters = assignments(kmeans(X, k))

	hc = hclust(pairwise(Euclidean(), X, dims=2), linkage=:ward)
	hclustClusters = cutree(hc, k=k)
end

# ╔═╡ 31cc81e6-9df0-429d-9b9a-3b270a1ce659
begin
	kmeansPlot = plot(
            scatter(
                x = transformation[1,:],
                y = transformation[2,:],
                mode = "markers",
                text = memberLabels,
                hovertemplate = "%{text}<extra></extra>",
                marker = attr(size=16, color=kmeansClusters, colorscale="Viridis", line=attr(width=3, color=partyColor))
            ),
            Layout(title="K-Means on PCA")
        )
    kmeansPlot
end

# ╔═╡ 44518354-1a2d-452c-94bb-43c36f00aeee
begin
	hclustPlot = plot(
            scatter(
                x = transformation[1,:],
                y = transformation[2,:],
                mode = "markers",
                text = memberLabels,
                hovertemplate = "%{text}<extra></extra>",
                marker = attr(size=16, color=hclustClusters, colorscale="Viridis", line=attr(width=3, color=partyColor))
            ),
            Layout(title="Hierarchical (Ward) on PCA")
        )
    hclustPlot
end

# ╔═╡ 6a154352-b6cb-4b6b-a170-9f7ec394526d
md"""
## LDA
Using party as class labels.
"""

# ╔═╡ 727f54dc-92bf-4f10-bce1-945f6a9d1289
begin
	model_lda = fit(SubspaceLDA, X, [p == "R" ? 1 : 2 for p in memberParty])
	ldaEmbed = predict(model_lda, X)

	ldaPlot = plot(
            [histogram(x = ldaEmbed[1, memberParty .== p], name = p, marker = attr(color = p == "R" ? "red" : "blue")) for p in ["R", "D"]],
            Layout(barmode="overlay")
        )
    ldaPlot
end

# ╔═╡ fb6af19b-61ca-4b7b-9a50-440b4bcbdf7e
# ╠═╡ disabled = true
#=╠═╡
# Note to self/author: you currently want to rewrite this notebook
  ╠═╡ =#

# ╔═╡ Cell order:
# ╟─c177a4fe-c38f-11f1-b899-0bbf875c6316
# ╠═388a54f4-e21f-466c-8e85-78e492f99b0b
# ╟─e03f9602-4cc3-4dd1-ab47-16364bbc9320
# ╠═9d5ceeb1-f87d-419d-9cac-955466f1cbe5
# ╠═c458eeaa-4310-4b07-97e5-7d5311bc58d1
# ╟─22d75c76-5807-486c-8614-334a776ef8aa
# ╠═1d93fad2-f72a-4fb4-9a72-780a907960bd
# ╟─4c1a3eeb-8e7b-45b5-820a-f25c7b8c302b
# ╠═b5bd976a-1278-49ac-907a-ea23e8a51ff6
# ╠═a89dd7b5-7ffb-46bb-b63e-6bd29a52a15a
# ╟─61eb9919-23c4-49c7-aa2d-1f3ecefcd35d
# ╠═e257d5e4-3afa-4912-8b28-e78f33e4ff38
# ╠═8c2d86b1-cb6e-441a-9c36-73ba4559591e
# ╟─2e4ceee2-52ec-4633-a1dd-2a75ed23f72a
# ╠═3f55631c-61a1-43ff-aaeb-d5862344d6d6
# ╠═70a1a572-4a64-4567-b67c-1ad62b75ef53
# ╟─4ee91e6b-1af7-40c9-9d50-6df3142a93bc
# ╠═e6feb5ac-062a-4442-aef0-dcdce3df8c56
# ╟─c4ad8b78-370b-4eab-b7c8-b7f9184af8c3
# ╠═f8309839-4d51-4325-8863-626ba7ee5306
# ╟─56236407-ffa3-4c96-af65-6c2bfbaad6de
# ╠═ef159cb9-18b2-4475-b6cc-e9d9a9616465
# ╟─a147a085-b970-46b8-815e-c42c42f07cca
# ╠═952ed242-edb1-44db-bdc1-ab0c26f51255
# ╠═31cc81e6-9df0-429d-9b9a-3b270a1ce659
# ╠═44518354-1a2d-452c-94bb-43c36f00aeee
# ╟─6a154352-b6cb-4b6b-a170-9f7ec394526d
# ╠═727f54dc-92bf-4f10-bce1-945f6a9d1289
# ╟─fb6af19b-61ca-4b7b-9a50-440b4bcbdf7e
