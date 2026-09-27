# AZLegInfo.jl: reading the Member Voting History PDFs with native Julia code

This folder holds a rewrite of `getSession57HouseLegislativeMemberVotingHistory`
from [AZLegInfo.jl](https://codeberg.org/AZLegInfo/AZLegInfo.jl), made on top of
its `main` branch as of commit `b2638da` ("change from Parquet to Parquet2"). It
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
| Time for the 62 PDFs (4,210 pages), first call in a Julia session | 115 s | 23 s, mostly compiling |
| Time for later calls | 100 s | 4.2 s, or 1.6 s with 4 threads |

The times were measured on the same 4-core Linux machine, reading the zip from
a local file; another machine was about 25% faster for both versions. After
`using AZLegInfo`, the first call takes about 1 s longer than later calls, not
about 19 s: precompiling the package runs the function once, and Julia keeps
the compiled code.

The function's name, argument and return value are unchanged: a `Dict` from each
member's name to a `DataFrame` of their votes, with the same 13 columns. So
`session57HouseLegislativeMemberVotingHistory` and the one-hot-encoding code
that uses it work as before.

## Files

- `src/AZLegInfo.jl`: the package module. Only the voting-history function and
  the `using` line changed. The function now holds, as nested functions, a
  Deflate decompressor, a zip reader, a PDF text reader and the vote parser,
  in that order.
- `Project.toml`: removes `JavaCall` and `p7zip_jll`, and gives `Parquet2`
  its own UUID (see the notes at the end). The `[compat]` section stays
  empty, as before.
- `0001-Read-Member-Voting-History-PDFs-with-native-Julia-co.patch`: the same
  change as one commit on top of `b2638da`.

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
buffers, and the Deflate decompressor uses lookup tables: it decompresses the
dataset's 98 MB of PDF streams about 4 times as fast as the Inflate package.

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
  where the Inflate package's error said "BoundsError"). The modules' 71 unit
  tests pass.
- **Same as before the speed work.** Random, often damaged, inputs give the
  same results as the version from before the speed work: 54,000 content
  streams (with many kinds of fonts, forms, and /Contents arrays; the glyphs
  are compared bit for bit), 40,000 sets of glyphs to group into lines
  (with ties, NaN, -0.0 and infinities), and 3,000 voting-history PDFs. An
  independent review of the speed work found three inputs that behaved
  differently (a name with a #00 escape, a 0 in a TJ array on mirrored
  text, and a zip with a duplicate member followed by a damaged PDF); all
  three are fixed.
- **The decompressor.** On all 38,274 Flate streams of the test PDFs (140 MB),
  697 streams made with zlib at every level and strategy, 155,000 damaged
  streams, 260,000 generated ones (with incomplete and
  over-subscribed codes, every truncation, and bit flips), and hand-made
  edge cases, it gives the same bytes as the Inflate package, and fails
  exactly where that package fails. Zip reading reads the
  108 test zips as before, and on 42,000 mutated ones it never returns wrong
  file contents and gives only clear errors.
- **Julia versions.** The dataset output is byte-identical, and the unit tests
  pass, on Julia 1.6.7, 1.10.12, 1.11.7, 1.12.7 and 1.13.0, including with
  `--depwarn=error`, and with 1 and 4 threads. Tested on Linux only.
- **The whole package.** With `Parquet2.dataset` replaced by
  `Parquet2.Dataset` (see the notes at the end), `Pkg.develop` of the package
  followed by `using AZLegInfo` works, with 1 and 4 threads. It gives 62
  members and 67,945 votes, which `findAllBillActions` turns into 13,947 bill
  actions, and JavaCall and p7zip_jll are not loaded.
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

Apart from the Parquet2 UUID in `Project.toml`, these are outside the
rewritten function, and were left as they are:

- `Project.toml` on `main` gives `Parquet2` the UUID of the older Parquet
  package, so `Pkg.add` and `Pkg.develop` of the package fail ("depends on
  `Parquet2`, but entry ... has name `Parquet`"). This change fixes that,
  as it changes `Project.toml` anyway.
- `using AZLegInfo` still fails, before it gets to the voting histories.
  Parquet2 (version 0.2.37) has no `Parquet2.dataset`, so reading
  `equalityArizona2022SineDieReport.parquet` fails with an `UndefVarError`;
  the package then falls back to scraping azleg.gov, which failed when this
  was tested (`no method matching lastindex(::Nothing)`). With
  `Parquet2.Dataset` instead, reading the file works. The block for the
  voting histories calls `Parquet2.dataset` too.
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
