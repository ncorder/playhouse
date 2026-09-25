using Test
using AZLegInfo
#out = plusTwo(3)

# The PDF and zip readers, tested offline.
include("readers.jl")

SB1010_billID = getBillID("SB1010", 130)

@test SB1010_billID == 83585

#@test out == 5
