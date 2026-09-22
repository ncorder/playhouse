#using Test, MyAwesomePackage
using AZLegInfo
#out = plusTwo(3)

SB1010_billID = getBillID("SB1010", 130)

@test SB1010_billID = 83585

#@test out == 5
