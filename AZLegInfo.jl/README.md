# AZLegInfo.jl: native-Julia House voting history

A rewrite of `getSession57HouseLegislativeMemberVotingHistory` from
[AZLegInfo.jl](https://codeberg.org/AZLegInfo/AZLegInfo.jl) that uses only Julia packages.

| Before | After |
| --- | --- |
| JavaCall + Tabula (downloaded `.jar`, needs Java and `JULIA_COPY_STACKS=1`) | [PDFIO.jl](https://github.com/sambitdash/PDFIO.jl) plus a small text-operator interpreter (`extract_text_rows`) |
| `p7zip_jll` (runs the `7z` binary) | [ZipFile.jl](https://github.com/fhs/ZipFile.jl) |

Files:

- `src/AZLegInfo.jl` and `Project.toml` are the full updated upstream files.
- `native-julia-voting-history.patch` is the same change as a diff. To apply it
  in a clone of the Codeberg repo, run `git apply native-julia-voting-history.patch`.

The function's signature and return value are unchanged: a `Dict` from member
name to a `DataFrame` of votes.

## Verification

I ran both versions on `57L2RMemberVotingHistory.zip` (62 member PDFs):

- The two versions give the same 62 members, and all 883,285 cells in the
  67,945 vote rows are identical.
- For every PDF, the Y/N/NV/EXC counts match the totals printed in that PDF.
- The new version needs no Java and no `JULIA_COPY_STACKS`, so it also runs in
  Jupyter and Pluto.
