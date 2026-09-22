"""
    AZLegInfo

AZLegInfo is a package to get data conerning the Arizona State Legislature, and to some extent, the
"""

module AZLegInfo
using DataFrames, Dates, HTTP, JSON3, JavaCall,  Downloads, p7zip_jll

export getSessions, getBillId, getBillInfo, getBillPositions_JSON, extract_tables_from_pdf, extract_voting_history, download_voting_histories

# Module-level so the JVM is initialized at most once per Julia session.
# JNI does not support tearing down and recreating a JVM in the same
# process, so this state must not be reset on every call to
# extract_tables_from_pdf.
const _tabula_tmpdir = Ref{Union{Nothing,String}}(nothing)
const _tabula_jar = Ref{Union{Nothing,String}}(nothing)
const _tabula_initialized = Ref(false)

function getSessions()::DataFrame
    """
    Returns a DataFrame with information for every Arizona State Legislative Session (avaliable through the API)

    Returns:
    A DataFrame with information for every Arizona State Legislative Session (avaliable through the API)

    """
    SessionIDs = DataFrame()


    ID = 0
    emptySessionIDs = 0

    while true
        ID += 1
        url = "https://apps.azleg.gov/api/Session/?sessionId=$ID"
        resp = HTTP.get(url)
        data = JSON3.read(String(resp.body))

        # Context: Some SessionID's are empty.
        # Allows for up to 100 empty SessionIDs
        if length(Array(data)) == 0
            if emptySessionIDs > 100
                break
            end
            emptySessionIDs += 1
        end
        # Append the current SessionID to the df
        append!(SessionIDs, DataFrame(data))
        end

    return SessionIDs
    end

function getBillInfo(billNumber::String, sessionID::Int)
    """
    Returns basic information aout a bill as a parsed JSON.

    Expects:
        billNumber is the Bill Number as a string (for example: SB1010)
        sessionID is the Session ID (see the function getSessions())
    """
    url="https://apps.azleg.gov/api/Bill/?billNumber=$billNumber&sessionId=$sessionID"
    resp = HTTP.get(url)
    return JSON3.parse(String(resp.body))
    end

function getBillId(billNumber::String, sessionID::Int)::Int
    """
    Returns a bill's identification number from its bill number (example: SB1010) and its session (see the getSessions() function)
    """
    billInfo = getBillInfo(billNumber, sessionID)
    return Int(billInfo["BillId"])
    end

function getBillPositions_JSON(billNumber::String, sessionID::Int)
    """
    Returns the RTS system positions for a particular bill as a JSON.

    Expects:
        billNumber is the Bill Number as a string (for example: SB1010)
        sessionID is the Session ID (see the function getSesions())

    Returns
        A JSON of the positions
    """
    billId = getBillId(billNumber, sessionID)
    url = "https://apps.azleg.gov/api/BillPosition/?id=$sessionID&billStatusId=$billId"
    resp = HTTP.get(url)
    return JSON3.parse(String(resp.body))
    end

const _TABULA_JAR_URL =
    "https://github.com/tabulapdf/tabula-java/releases/download/v1.0.5/tabula-1.0.5-jar-with-dependencies.jar"

function _cleanup_tabula()
    tmpdir = _tabula_tmpdir[]

    if tmpdir !== nothing && isdir(tmpdir)
        try
            rm(tmpdir; recursive=true, force=true)
        catch err
            @warn "Unable to remove temporary Tabula directory" exception=err
        end
    end

    _tabula_tmpdir[] = nothing
    _tabula_jar[] = nothing

    nothing
end

function _initialize_tabula()
    _tabula_initialized[] && return

    # JavaCall.init() throws if another package already started the
    # JVM, and the classpath can no longer be extended at that point.
    if JavaCall.isloaded()
        @warn "JVM was already started elsewhere; Tabula must already be on its classpath"
        _tabula_initialized[] = true
        return
    end

    tmpdir = mktempdir()
    jar_path = joinpath(
        tmpdir,
        "tabula-1.0.5-jar-with-dependencies.jar",
    )

    try
        Downloads.download(_TABULA_JAR_URL, jar_path)

        # The classpath must be configured before JVM initialization.
        JavaCall.addClassPath(jar_path)
        JavaCall.init()

        _tabula_tmpdir[] = tmpdir
        _tabula_jar[] = jar_path
        _tabula_initialized[] = true

        # Register cleanup once the JVM has been initialized.
        atexit(_cleanup_tabula)

    catch
        rm(tmpdir; recursive=true, force=true)
        rethrow()
    end

    nothing
end

function extract_tables_from_pdf(pdf_path::AbstractString; columns=nothing)
    """
    Extracts Tables from a PDF

    The function downloads the .jar file for Tabula to a temporary location
    so that it is automatically deleted when no longer in use.

    Then it uses JavaCall to run Tabula and utilizes it to extract
    the tables from a PDF.

    It expects the PDFs to follow the provided format for legislative
    votes. Each page is first read in lattice mode (tables drawn with
    ruling lines); pages without ruled tables fall back to stream mode
    (whitespace-aligned columns) over the whole page, so every line of
    text on the page ends up in some row. For Member Voting History
    PDFs, extract_voting_history turns these rows into one row per vote.

    On Linux and macOS, Julia must be started with the environment
    variable JULIA_COPY_STACKS=1 (e.g. `JULIA_COPY_STACKS=1 julia`),
    otherwise JavaCall refuses to run outside the root task, which
    includes Jupyter and Pluto. Do not set it on Windows.

    Expects:
        pdf_path is the path to the pdf
        columns (optional) is a list of x positions, in points from the
          left edge of the page, where one column ends and the next
          begins. When given, every page is read in stream mode with
          these boundaries instead of guessed ones (tabula's --columns).

    Returns
       Tables as DataFrame, one row per table row, with columns named
       column_1, column_2, ... Header rows repeated on each page are kept.

    Citations:
      Text generated by ChatGPT, OpenAI, September 22, 2026, https://chatgpt.com/s/t_6ab2ce120dc88191becfac3228d8f310.
      Code revised by Claude Code, Anthropic, September 22, 2026, https://claude.ai/code/session_01SQ79sYVPmqwp7yFkriCVsL.
    """
    isfile(pdf_path) || throw(ArgumentError("No such file: $pdf_path"))

    _initialize_tabula()

    # JNI resolves methods by exact signature, so every jcall needs the
    # concrete Java class; a bare JavaObject has no signature.
    JFile = @jimport java.io.File
    JObject = @jimport java.lang.Object
    JList = @jimport java.util.List
    PDDocument = @jimport org.apache.pdfbox.pdmodel.PDDocument
    ObjectExtractor = @jimport technology.tabula.ObjectExtractor
    PageIterator = @jimport technology.tabula.PageIterator
    Page = @jimport technology.tabula.Page
    Table = @jimport technology.tabula.Table
    RectangularTextContainer = @jimport technology.tabula.RectangularTextContainer
    TextElement = @jimport technology.tabula.TextElement
    TextChunk = @jimport technology.tabula.TextChunk
    SpreadsheetExtractionAlgorithm =
        @jimport technology.tabula.extractors.SpreadsheetExtractionAlgorithm
    BasicExtractionAlgorithm =
        @jimport technology.tabula.extractors.BasicExtractionAlgorithm

    # PDDocument.load has no String overload, only File/InputStream/byte[].
    pdf_file = JFile((JString,), abspath(pdf_path))
    document = jcall(PDDocument, "load", PDDocument, (JFile,), pdf_file)

    jlist(list, T) = [convert(T, jcall(list, "get", JObject, (jint,), i))
                      for i in 0:(jcall(list, "size", jint, ()) - 1)]

    try
        spreadsheet = SpreadsheetExtractionAlgorithm(())
        basic = BasicExtractionAlgorithm(())

        # Lattice mode for tables drawn with ruling lines; if it finds none,
        # stream mode (whitespace-aligned columns) over the whole page.
        # Stream mode is not restricted to a detected table area because
        # detection clips rows at the top and bottom of real vote PDFs.
        if columns !== nothing
            JFloat = @jimport java.lang.Float
            ArrayList = @jimport java.util.ArrayList
            boundaries = ArrayList(())
            for x in columns
                jcall(boundaries, "add", jboolean, (JObject,), convert(JFloat, x))
            end
        end

        function page_tables(page)
            if columns !== nothing
                return jlist(jcall(basic, "extract", JList, (Page, JList), page, boundaries), Table), true
            end
            tables = filter(
                t -> jcall(t, "getRowCount", jint, ()) > 0,
                jlist(jcall(spreadsheet, "extract", JList, (Page,), page), Table),
            )
            isempty(tables) || return tables, false
            jlist(jcall(basic, "extract", JList, (Page,), page), Table), true
        end

        # Stream mode joins the words of a cell without the gaps between
        # them ("Y   FINAL" becomes "YFINAL"); re-split them into words.
        function stream_cell_text(cell)
            elements = jcall(cell, "getTextElements", JList, ())
            words = jlist(jcall(TextElement, "mergeWords", JList, (JList,), elements), TextChunk)
            String(strip(replace(join([jcall(w, "getText", JString, ()) for w in words], " "), r"\s+" => " ")))
        end

        extractor = ObjectExtractor((PDDocument,), document)
        pages = jcall(extractor, "extract", PageIterator, ())

        all_rows = Vector{Vector{String}}()

        while Bool(jcall(pages, "hasNext", jboolean, ()))
            page = jcall(pages, "next", Page, ())

            tables, stream = page_tables(page)
            for table in tables
                for cells in jlist(jcall(table, "getRows", JList, ()), JList)
                    push!(all_rows, [
                        stream ? stream_cell_text(cell) :
                            replace(jcall(cell, "getText", JString, ()), '\r' => ' ')
                        for cell in jlist(cells, RectangularTextContainer)
                    ])
                end
            end
        end

        isempty(all_rows) && return DataFrame()

        # Normalize rows because different tables may have
        # different numbers of columns.
        ncols = maximum(length, all_rows)

        for row in all_rows
            append!(
                row,
                fill("", ncols - length(row)),
            )
        end

        DataFrame(
            [
                getindex.(all_rows, i)
                for i in 1:ncols
            ],
            Symbol.(
                "column_" .* string.(1:ncols)
            ),
        )

    finally
        jcall(
            document,
            "close",
            Nothing,
            (),
        )
    end
end

const _BILL_CELL = r"^((?:HB|SB|HCR|SCR|HCM|SCM|HJR|SJR|HR|SR|HM|SM)\d{4})(?:\s+(.+))?$"
const _VOTE_LINE = r"^(\S+)\s+(.+?)\s+(\d\d/\d\d/\d\d)\s+(\d+)-(\d+)-(\d+)-(\d+)-(\d+)$"
const _TOTALS = r"AYES\s*=\s*(\d+)\s*NAYS\s*=\s*(\d+)\s*NV\s*=\s*(\d+)\s*EXC\s*=\s*(\d+)\s*TOTAL VOTES\s*=\s*(\d+)"

function extract_voting_history(pdf_path::AbstractString)
    """
    Extracts every vote from a House Member Voting History PDF

    Each bill in the PDF is a bill line (bill number, chapter, short title
    and sponsor), an optional "NOW:" line with the bill's new title, and
    one line per vote (vote, vote type, date, and the
    A-N-NV-EXC-VAC tally). This turns those lines into one row per vote,
    and warns if the Y/N/NV/EXC counts differ from the totals printed at
    the end of the PDF.

    Expects:
        pdf_path is the path to a Member Voting History pdf

    Returns
        A DataFrame with one row per vote and the columns member, bill,
        chapter ("V" = vetoed, "" = none, "1 E" = chapter 1 with an
        emergency clause), short_title, now_title ("" = none), vote
        (Y, N, NV, EXC, AB, P, ...), vote_type (FINAL, THIRD, a
        committee, ...), date, ayes, nays, not_voting, excused, and vacant.

    Citations:
      Code generated by Claude Code, Anthropic, September 22, 2026, https://claude.ai/code/session_01SQ79sYVPmqwp7yFkriCVsL.
    """
    # Bill number (x = 36) and chapter (x = 99) sit left of x = 160; the
    # short title, NOW: line and vote lines start at x = 168. Guessed
    # columns would shift with the width of the member's name.
    rows = extract_tables_from_pdf(pdf_path; columns=[160])

    # The member line and the totals line straddle x = 160, so they are
    # read from PDFBox's plain text of the whole document instead.
    JFile = @jimport java.io.File
    PDDocument = @jimport org.apache.pdfbox.pdmodel.PDDocument
    PDFTextStripper = @jimport org.apache.pdfbox.text.PDFTextStripper
    document = jcall(PDDocument, "load", PDDocument, (JFile,), JFile((JString,), abspath(pdf_path)))
    text = try
        jcall(PDFTextStripper(()), "getText", JString, (PDDocument,), document)
    finally
        jcall(document, "close", Nothing, ())
    end

    m = match(r"Member:[ \t]*([^\r\n]+)", text)
    m === nothing && throw(ArgumentError("Not a Member Voting History PDF: $pdf_path"))
    member = String(strip(m.captures[1]))

    votes = DataFrame(
        member=String[], bill=String[], chapter=String[], short_title=String[],
        now_title=String[], vote=String[], vote_type=String[], date=Date[],
        ayes=Int[], nays=Int[], not_voting=Int[], excused=Int[], vacant=Int[],
    )

    bill = chapter = short_title = now_title = ""
    in_header = false

    for (left, right) in zip(rows.column_1, rows.column_2)
        # Every page repeats the title, legend and column headings.
        if startswith(right, "Member Voting History")
            in_header = true
        elseif in_header
            in_header = right != "Vote/Vote Type"
        elseif isempty(left) && (isempty(right) || occursin(r"^\d+$", right))
            continue  # blank line or page number
        elseif startswith(left, "AYES")
            break  # totals line, checked below
        elseif (b = match(_BILL_CELL, left)) !== nothing
            bill, chapter = b.captures[1], something(b.captures[2], "")
            short_title, now_title = right, ""
        elseif startswith(right, "NOW:")
            now_title = strip(right[5:end])
        elseif (v = match(_VOTE_LINE, right)) !== nothing
            isempty(bill) && error("Vote before any bill in $pdf_path: $right")
            push!(votes, (
                member, bill, chapter, short_title, now_title,
                v.captures[1], v.captures[2],
                Date(v.captures[3], dateformat"mm/dd/yy") + Year(2000),
                parse.(Int, v.captures[4:8])...,
            ))
        elseif isempty(now_title)
            short_title = join(filter(!isempty, [short_title, left, right]), " ")
        else
            now_title = join(filter(!isempty, [now_title, left, right]), " ")
        end
    end

    # The PDF's own totals, which leave out committee codes (AB, P).
    t = match(_TOTALS, text)
    if t === nothing
        @warn "No vote totals found to check against" pdf_path
    else
        expected = parse.(Int, t.captures[1:4])
        parsed = [count(==(code), votes.vote) for code in ("Y", "N", "NV", "EXC")]
        parsed == expected || @warn "Parsed vote counts differ from the PDF's totals" pdf_path expected parsed
    end

    votes
end

function download_voting_histories(
    url::AbstractString="https://codeberg.org/AZLegInfo/datasets/raw/branch/main/57L2RMemberVotingHistory.zip",
)
    """
    Downloads a .zip of Member Voting History PDFs and reads every legislator's votes

    The zip is downloaded to a temporary file and extracted to a temporary
    directory; both are deleted when the function returns, even on error.
    Every .pdf in the zip, in any folder, is read with extract_voting_history.

    By default it downloads 57L2RMemberVotingHistory.zip (57th
    Legislature, 2nd Regular Session) from the AZLegInfo datasets repository,
    https://codeberg.org/AZLegInfo/datasets. A local zip can be read with a
    file:// URL.

    Expects:
        url (optional) is the address of the .zip file

    Returns
        A Dict mapping each legislator's name, as printed after "Member:"
        in their PDF (for example "ALLEN" or "CONTRERAS L"), to the
        DataFrame of their votes returned by extract_voting_history.

    Citations:
      Code generated by Claude Code, Anthropic, September 22, 2026, https://claude.ai/code/session_01SQ79sYVPmqwp7yFkriCVsL.
    """
    # extract_voting_history keeps the member's name only in its rows,
    # so a legislator with no votes is named from the PDF's text.
    function member_name(pdf, votes)
        isempty(votes) || return votes.member[1]
        for row in eachrow(extract_tables_from_pdf(pdf))
            m = match(r"^Member:\s*(.+)$", join(filter(!isempty, collect(row)), " "))
            m === nothing || return String(m.captures[1])
        end
        error("No \"Member:\" line in $pdf")
    end

    histories = Dict{String,DataFrame}()

    mktemp() do zip_path, io
        close(io)
        Downloads.download(url, zip_path)
        read(zip_path, 2) == b"PK" || error("Not a zip file: $url")

        mktempdir() do dir
            run(pipeline(`$(p7zip_jll.p7zip()) x -y -o$dir $zip_path`, stdout=devnull))

            for (root, _, files) in walkdir(dir), file in sort(files)
                # Skip the "._name.pdf" metadata files macOS adds to zips.
                (endswith(lowercase(file), ".pdf") && !startswith(file, "._")) || continue
                pdf = joinpath(root, file)
                votes = extract_voting_history(pdf)
                member = member_name(pdf, votes)
                haskey(histories, member) && error("Two PDFs in the zip are for $member")
                histories[member] = votes
            end
        end
    end

    histories
end

end # module
