# AZ Leg Info

Hello! This is where I am doing some scaffolding/early-stages work for my 2026 Honors Thesis at the University of Arizona.
For the first semester of my honors thesis I am hoping to build a Julia package (that is Python-compatible) to make it a bit easier to get certain pieces of information from the state legislature (and hopefully eventually also recorder's office).

## Extracting votes from PDFs

- `extract_voting_history(path)` reads a House Member Voting History PDF into a DataFrame with one row per vote: member, bill, chapter, short title, new ("NOW:") title, vote, vote type, date, and the ayes/nays/not voting/excused/vacant tally. It warns if its counts differ from the totals printed at the end of the PDF.
- `extract_tables_from_pdf(path; columns=nothing)` is the general table extractor underneath it. Pass `columns` (x positions in points where one column ends and the next begins) when the guessed columns are wrong.

Both use [Tabula](https://github.com/tabulapdf/tabula-java) through JavaCall.jl, so they need:

- A Java runtime (JDK 8 or newer) on your machine, with `JAVA_HOME` set if JavaCall cannot find it.
- On Linux and macOS, Julia started with `JULIA_COPY_STACKS=1`. Otherwise JavaCall refuses to run outside Julia's root task, which includes Jupyter and Pluto. Do not set it on Windows.

```sh
JULIA_COPY_STACKS=1 julia --project
```

```julia
using AZLegInfo, DataFrames
dir = "57L 2R Member Voting History"
votes = reduce(vcat, [extract_voting_history(joinpath(dir, f)) for f in readdir(dir) if endswith(f, ".pdf")])
```

The Tabula jar (about 13 MB) is downloaded to a temporary directory the first time either function is called in a session. Reading all 62 member PDFs of the 57th Legislature, 2nd Regular Session (67,945 votes) takes about 1.5 minutes.
