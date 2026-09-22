# AZ Leg Info

Hello! This is where I am doing some scaffolding/early-stages work for my 2026 Honors Thesis at the University of Arizona.
For the first semester of my honors thesis I am hoping to build a Julia package (that is Python-compatible) to make it a bit easier to get certain pieces of information from the state legislature (and hopefully eventually also recorder's office).

## Extracting votes from PDFs

- `download_voting_histories()` downloads `57L2RMemberVotingHistory.zip` (57th Legislature, 2nd Regular Session) from the [AZLegInfo datasets repository](https://codeberg.org/AZLegInfo/datasets) and returns a `Dict` from each legislator's name (as printed after "Member:", e.g. `"ALLEN"`, `"CONTRERAS L"`) to their votes. The zip and its extracted PDFs are temporary and deleted when the function returns. Pass a URL to read another zip; a local zip works as a `file://` URL.
- `extract_voting_history(path)` reads a House Member Voting History PDF into a DataFrame with one row per vote: member, bill, chapter, short title, new ("NOW:") title, vote, vote type, date, and the ayes/nays/not voting/excused/vacant tally. It warns if its counts differ from the totals printed at the end of the PDF.
- `extract_tables_from_pdf(path; columns=nothing, pages=nothing)` is the general table extractor underneath it, and the only function that talks to Tabula. Pass `columns` (x positions in points where one column ends and the next begins) when the guessed columns are wrong, and `pages` (e.g. `[1]`) to read only some pages.

All three use [Tabula](https://github.com/tabulapdf/tabula-java) through JavaCall.jl, so they need:

- A Java runtime (JDK 8 or newer) on your machine, with `JAVA_HOME` set if JavaCall cannot find it.
- On Linux and macOS, Julia started with `JULIA_COPY_STACKS=1`. Otherwise JavaCall refuses to run outside Julia's root task, which includes Jupyter and Pluto. Do not set it on Windows.

```sh
JULIA_COPY_STACKS=1 julia --project
```

```julia
using AZLegInfo, DataFrames
histories = download_voting_histories()
histories["ALLEN"]                        # Allen's 277 votes
votes = reduce(vcat, values(histories))   # every legislator's votes in one DataFrame
```

The Tabula jar (about 13 MB) is downloaded to a temporary directory the first time any of them is called in a session. Reading all 62 member PDFs of the 57th Legislature, 2nd Regular Session (67,945 votes) takes about 1.5 minutes.
