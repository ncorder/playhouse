# AZLegInfo.jl: reading the Member Voting History PDFs with native Julia code

This folder holds a rewrite of `getSession57HouseLegislativeMemberVotingHistory`
from [AZLegInfo.jl](https://codeberg.org/AZLegInfo/AZLegInfo.jl), made on top of
its `main` branch as of commit `0b46200` ("add NamedArrays as dependency"). It
now reads the 57th Legislature's House Member Voting History PDFs using **only
native Julia libraries**:

| | Before | After |
|---|---|---|
| PDF text | Tabula (Java) through JavaCall | `src/PDFText.jl`, pure Julia |
| Zip file | the `7z` program from p7zip_jll | `src/ZipReader.jl`, pure Julia |
| Decompression | inside Java and 7z | [Inflate.jl](https://github.com/GunnarFarneback/Inflate.jl): pure Julia, no dependencies |
| Needs Java and `JULIA_COPY_STACKS=1` | yes | no |
| Time for the 62 PDFs (4,210 pages), first call in a Julia session | about 90 s | about 30 s (then about 15 s) |

The function's name, argument and return value are unchanged: a `Dict` from each
member's name to a `DataFrame` of their votes, with the same 13 columns. So
`session57HouseLegislativeMemberVotingHistory` and the new one-hot-encoding
code that uses it work as before.

## Files

- `src/AZLegInfo.jl`: the package module. Only the voting-history function, the
  `using` line and two `include`s changed.
- `src/PDFText.jl` (new): reads a PDF's text as lines of words with their
  positions. `PDFText.read_lines(path_or_bytes)` also works on other PDFs.
- `src/ZipReader.jl` (new): reads the files in a zip: `ZipReader.read_zip(bytes)`.
- `Project.toml`: removes `JavaCall` and `p7zip_jll` and adds `Inflate`. The
  `[compat]` section stays empty, as before.
- `test/readers.jl` (new): 71 offline tests of the PDF and zip readers.
- `test/runtests.jl`, `test/Project.toml`: `Pkg.test()` now runs `readers.jl`.
  The file now loads `Test`, and the SB1010 check uses `==` instead of `=`,
  which `@test` does not accept.
- `0001-Read-Member-Voting-History-PDFs-with-native-Julia-co.patch`: the same
  change as one commit on top of `0b46200`.

## Applying it to the Codeberg repository

```sh
cd AZLegInfo.jl                     # a clone of codeberg.org/AZLegInfo/AZLegInfo.jl
git am /path/to/playhouse/AZLegInfo.jl/0001-*.patch
git push
```

Or copy `src/`, `test/` and `Project.toml` from this folder over the package's
files. Usage stays the same, with no Java and no environment variable:

```julia
using Pkg
Pkg.add(url="https://codeberg.org/AZLegInfo/AZLegInfo.jl")
using AZLegInfo
session57HouseLegislativeMemberVotingHistory["ALLEN"]
```

To run only the new tests: `julia --project=. test/readers.jl` in the package
folder, after `Pkg.instantiate()`.

## How it was checked

- **Same output as before.** The old Tabula version and the new version, run on
  the dataset, give byte-identical output: all 67,945 votes, every column. Two
  independent extractions, built with pdfminer and with MuPDF without reading
  the Julia code, also agree on every row.
- **The PDFs' own totals.** In each of the 62 PDFs, the parsed Y/N/NV/EXC counts
  match the totals line printed at its end.
- **Julia versions.** The dataset output is byte-identical, and all tests pass, on
  Julia 1.6.7, 1.10.12, 1.11.7, 1.12.7 and 1.13.0, including with
  `--depwarn=error`. Tested on Linux only.
- **The whole package.** `Pkg.develop` of the package followed by `using AZLegInfo`
  works, and gives 62 members and 67,945 votes.
- **Other PDFs.** On 43 real PDFs the reader had never seen (azleg.gov bills, fact
  sheets and JLBC reports, IRS forms, arXiv papers, LibreOffice, Word and
  Chrome output), the characters agree with pdfplumber's with an F1 score of at
  least 0.997. 34 more feature and edge-case files were also read. The only
  errors are for files that are not PDFs and for encrypted PDFs, and both errors
  say so.
- **Damaged files.** No damaged or hostile input hung or crashed Julia. That was
  304 corrupted PDFs, hostile PDFs (such as forms that draw themselves and
  10,000-deep nesting) and 42,000 mutated zips. Damaged parts of a PDF are
  skipped with a warning, and a mutated zip never returned wrong file contents.

## Changes in behaviour

- The zip is downloaded into memory; nothing is written to a temporary folder.
- Only the PDFs in the zip are decompressed, so other files in it do not matter.
- New warnings: when a line of a PDF is not recognized and is added to a title
  (this does not happen in this dataset), and when a PDF has damaged parts.
- New error: a zip that contains no PDFs.
- Ligatures such as "ﬁ" become "fi". Tabula did the same, so the output is
  unchanged.

## Limits

`PDFText` does not decrypt encrypted PDFs, including ones that open without a
password (Tabula's PDFBox could). It does not read text that exists only as
images (scans), or CJK fonts without a ToUnicode table. `ZipReader` does not read
encrypted or split zips, or compression methods other than stored and Deflate.
