# AZLegInfo.jl: reading the Member Voting History PDFs with native Julia code

This folder holds a rewrite of `getSession57HouseLegislativeMemberVotingHistory`
from [AZLegInfo.jl](https://codeberg.org/AZLegInfo/AZLegInfo.jl), made on top of
its `main` branch as of commit `ffe2f0b` ("scoping issue"). It
now reads the 57th Legislature's House Member Voting History PDFs using **only
native Julia code**. All of the new code is inside that one function in
`src/AZLegInfo.jl`: no `.jl` files were added, and no packages either.

| | Before | After |
|---|---|---|
| PDF text | Tabula (Java) through JavaCall | `read_lines`, nested in the function |
| Zip file | the `7z` program from p7zip_jll | `read_zip`, nested in the function |
| Decompression | inside Java and 7z | `inflate_data`, nested in the function |
| Dependencies | JavaCall, p7zip_jll, Java | none new (Julia's standard library and DataFrames) |
| Needs `JULIA_COPY_STACKS=1` | yes | no |
| Time for the 62 PDFs (4,210 pages), first call in a Julia session | about 80 s | about 17 s, mostly compiling |
| Time for later calls | about 70 s | about 3.3 s, or 1.3 s with 4 threads |

After `using AZLegInfo`, calls are as fast as later calls: precompiling the
package runs the function once, and Julia keeps the compiled code.

The function's name, argument and return value are unchanged: a `Dict` from each
member's name to a `DataFrame` of their votes, with the same 13 columns. So
`session57HouseLegislativeMemberVotingHistory` and the one-hot-encoding code
that uses it work as before.

## Files

- `src/AZLegInfo.jl`: the package module. Only the voting-history function and
  the `using` line changed. The function now holds, as nested functions, a
  Deflate decompressor, a zip reader, a PDF text reader and the vote parser,
  in that order.
- `Project.toml`: removes `JavaCall` and `p7zip_jll`. The `[compat]` section
  stays empty, as before.
- `0001-Read-Member-Voting-History-PDFs-with-native-Julia-co.patch`: the same
  change as one commit on top of `ffe2f0b`.

## Applying it to the Codeberg repository

```sh
cd AZLegInfo.jl                     # a clone of codeberg.org/AZLegInfo/AZLegInfo.jl
git am /path/to/playhouse/AZLegInfo.jl/0001-*.patch
git push
```

Or copy `src/AZLegInfo.jl` and `Project.toml` from this folder over the
package's files. Usage stays the same, with no Java and no environment variable:

```julia
using Pkg
Pkg.add(url="https://codeberg.org/AZLegInfo/AZLegInfo.jl")
using AZLegInfo
session57HouseLegislativeMemberVotingHistory["ALLEN"]
```

To read the PDFs in parallel, start Julia with threads, for example
`julia --threads=auto`.

## How the code is laid out, and why it is fast

Julia cannot define a `struct` inside a function, so PDF objects, fonts, glyphs,
words and lines are NamedTuples, Pairs and Refs. Julia also slows down some
nested functions by "boxing" them, so each nested function is defined before
the ones that call it, none calls itself directly, and none has default or
keyword arguments. The function has no boxed variables.

Most of the speed comes from avoiding work that Julia hides well: the loops
that run for every byte, token or glyph allocate almost nothing, have no `try`
block or warning in them, and call other functions only with arguments of
known types. The content-stream reader keeps numbers and strings in reused
buffers, and the Deflate decompressor uses lookup tables. It decompresses the
dataset's 98 MB of PDF streams at about 220 MB/s, about 4 times as fast as the
Inflate package.

## How it was checked

- **Same output as before.** The old Tabula version and the new version, run on
  the dataset, give byte-identical output: all 67,945 votes, every column. Two
  independent extractions, built with pdfminer and with MuPDF without reading
  the Julia code, also agree on every row.
- **The PDFs' own totals.** In each of the 62 PDFs, the parsed Y/N/NV/EXC counts
  match the totals line printed at its end.
- **Same as the earlier, reviewed version.** Before being moved into the
  function and made faster, the readers were separate modules that had been
  reviewed and tested in depth. The new code gives the same text, positions
  and warnings as those modules on 529 PDFs: real ones, edge cases, 304
  corrupted ones and the dataset. The only differences are in the wording of
  some warnings about damaged files (for example "Damaged Deflate data"
  where the Inflate package's error said "BoundsError"). It also gives the
  same results as the version before the speed work on 50,000 random, and
  often damaged, content streams, and the modules' 71 unit tests pass.
- **The decompressor.** On all 38,274 Flate streams of the test PDFs (140 MB),
  697 streams made with zlib at every level and strategy, 155,000 damaged
  streams, and hand-made edge cases, it gives the same bytes as the Inflate
  package, and fails exactly where that package fails. Zip reading reads the
  108 test zips as before, and on 42,000 mutated ones it never returns wrong
  file contents and gives only clear errors.
- **Julia versions.** The dataset output is byte-identical, and the unit tests
  pass, on Julia 1.6.7, 1.10.12, 1.11.7, 1.12.7 and 1.13.0, including with
  `--depwarn=error`, and with 1 and 4 threads. Tested on Linux only.
- **The whole package.** `Pkg.develop` of the package followed by
  `using AZLegInfo` works (with the `equalityArizona2022SineDieReport` block
  disabled, see below), and gives 62 members and 67,945 votes, which
  `findAllBillActions` turns into 13,947 bill actions. After `using`, a call
  takes about 3.5 s, or 1.6 s with 4 threads.
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
- With several threads, the PDFs are read in parallel, so warnings from
  different PDFs can come in any order, and an error from one PDF is raised
  again once all PDFs before it are done (so its backtrace starts there).
- Warnings about damaged Flate streams quote the new decompressor's error
  ("Damaged Deflate data...") rather than the Inflate package's. And a zip
  entry damaged so that the Inflate package's streaming reader gave wrong
  bytes (which the CRC check then caught) may now fail with "cannot be
  decompressed" instead of "fails its CRC check".
- Ligatures such as "ﬁ" become "fi". Tabula did the same, so the output is
  unchanged.

## Notes on the package's other code

These are outside the rewritten function, and were left as they are:

- The new block that sets `equalityArizona2022SineDieReport` assigns the
  Parquet data to `session57HouseLegislativeMemberVotingHistory` instead.
  And reading that Parquet file fails (`UndefRefError`, with Parquet.jl
  0.8.6 on Julia 1.11), so the package falls back to scraping azleg.gov,
  which also failed when this was tested. Loading the package then fails.
  The tests of the whole package were run with that block disabled.
- `session57HouseLegislativeMemberVotingHistory.parquet` is not in the
  datasets repository yet, so the package runs the function instead. If it
  is added, the Parquet data would be a `DataFrame`, while
  `findAllBillActions` and the one-hot encoding expect the function's
  `Dict` of `DataFrame`s.
- `getSession57HouseLegislativeMemberVotingHistory_OneHotEncoding` compares
  "Aye", "Nay" and so on with the vote as printed ("Y", "N", ...), so no cell
  is ever set to 1. It also sets the same cell five times for each vote,
  and prints a line each time.

## Limits

The PDF reader does not decrypt encrypted PDFs, including ones that open without
a password (Tabula's PDFBox could). It does not read text that exists only as
images (scans), or CJK fonts without a ToUnicode table. The zip reader does not
read encrypted or split zips, or compression methods other than stored and
Deflate.

The package's `test/runtests.jl` is unchanged and still does not run: it lacks
`using Test`, and `@test SB1010_billID = 83585` is an assignment, which `@test`
does not accept.
