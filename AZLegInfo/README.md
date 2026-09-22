# AZ Leg Info

Hello! This is where I am doing some scaffolding/early-stages work for my 2026 Honors Thesis at the University of Arizona.
For the first semester of my honors thesis I am hoping to build a Julia package (that is Python-compatible) to make it a bit easier to get certain pieces of information from the state legislature (and hopefully eventually also recorder's office).

## Extracting tables from vote PDFs

`extract_tables_from_pdf(path)` uses [Tabula](https://github.com/tabulapdf/tabula-java) through JavaCall.jl, so it needs:

- A Java runtime (JDK 8 or newer) on your machine, with `JAVA_HOME` set if JavaCall cannot find it.
- On Linux and macOS, Julia started with `JULIA_COPY_STACKS=1`. Otherwise JavaCall refuses to run outside Julia's root task, which includes Jupyter and Pluto. Do not set it on Windows.

```sh
JULIA_COPY_STACKS=1 julia --project
```

```julia
using AZLegInfo
votes = extract_tables_from_pdf("Member Voting History.pdf")
```

The Tabula jar (about 13 MB) is downloaded to a temporary directory the first time the function is called in a session.
