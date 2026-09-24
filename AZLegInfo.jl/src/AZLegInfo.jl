"""
    AZLegInfo

AZLegInfo is a package to get data conerning the Arizona State Legislature, and to some extent, the
"""

module AZLegInfo
using DataFrames, HTTP, JSON3, Downloads, Dates, CSV, Gumbo, PDFIO, ZipFile

export getSessions, getBillID, getBillInfo, getBillPositions_JSON, session57HouseLegislativeMemberVotingHistory, equalityArizona2022SineDieReport, getBillIntroducedVersionText

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

function getBillInfo(billNumber::AbstractString, sessionID::Int)
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

function getBillID(billNumber::AbstractString, sessionID::Int)::Int
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
    billId = getBillID(billNumber, sessionID)
    url = "https://apps.azleg.gov/api/BillPosition/?id=$sessionID&billStatusId=$billId"
    resp = HTTP.get(url)
    return JSON3.parse(String(resp.body))
    end

function html2Text(html::String)
  """
  Converts HTML to cleaned text.
  
  Expects:
    HTML as a String
    
  Returns:
    HTML converted to cleaned text
    
  Citations:
    ATOzTOA. “Converting HTML to Text with Python.” Answer posted February 4, 2013; edited November 16, 2020. Stack Overflow. https://stackoverflow.com/a/14694615.
  """
  cleaned = replace(html, r"<[^>]*>" => "")
  return cleaned
  end

  function getBillIntroducedVersionText(billID::Int64)
    """
    Returns the text of the introduced version of a bill.
    
    Expects:
      billID: The billStatusId
    
    Returns:
      A cleaned string containing the bill's text
          
    ToDO:
      In the future, I plan to create a function to more easily see the different documents associated with a bill.
      This function should utilize that function once it is created.
    """
    response = HTTP.get("https://apps.azleg.gov/api/DocType/?billStatusId=$billID")
    responseJSON = JSON3.parse(String(response.body))
    @assert responseJSON[1]["Documents"][1]["DocumentName"] == "Introduced Version"
    billTextHTML = HTTP.get(responseJSON[1]["Documents"][1]["HtmlPath"])
    billText = String(billTextHTML.body)
    
    indx = findfirst("(TEXT OF BILL BEGINS ON NEXT PAGE)", String(billText))
    billStart = nextind(billText, last(indx))
    
    billText = billText[billStart:end]
    billText = html2Text(billText)
    
    return billText
    end

function getEqualityArizona2022SineDieReport()::DataFrame
  """
  Returns an edited version of the 2022 Sine Die Report by Equality Arizona.

  Expects:
    None

  Returns:
    A DataFrame of the 2022 Sine Die Report by Equality Arizona
  """
    SPREADSHEET_ID = "11xiBVZ-aWULnpDKxVpehrnzi8Krcz37l_xcZSF2bDiU"
    url = "https://docs.google.com/spreadsheets/d/$SPREADSHEET_ID/export?format=csv"
    response = HTTP.get(url)
        
    equalityArizona2022SineDieReport = CSV.read(IOBuffer(response.body), DataFrame; header=2)
    deleteat!(equalityArizona2022SineDieReport, nrow(equalityArizona2022SineDieReport)-10:nrow(equalityArizona2022SineDieReport))

    rename!(equalityArizona2022SineDieReport, names(equalityArizona2022SineDieReport) .=> replace.(names(equalityArizona2022SineDieReport), " " => "_"))

    sessionID2022Legislature = 125
    equalityArizona2022SineDieReport.Introduced_Version_Text = [getBillIntroducedVersionText(getBillID(bill, sessionID2022Legislature)) for bill in equalityArizona2022SineDieReport.Bill_Number]
    
    return equalityArizona2022SineDieReport
    end

equalityArizona2022SineDieReport = getEqualityArizona2022SineDieReport()

function getSession57HouseLegislativeMemberVotingHistory(
    url::AbstractString="https://codeberg.org/AZLegInfo/datasets/raw/branch/main/57L2RMemberVotingHistory.zip",
)
    """
    Downloads the House Member Voting History PDFs and reads every legislator's votes

    The zip is downloaded to a temporary file, which is deleted when the
    function returns, even on error, and read with ZipFile. Every .pdf in the
    zip, in any folder, is read with the nested extract_voting_history, which
    uses the nested extract_text_rows (PDFIO) to read the PDF. Only Julia
    packages are used: no Java, Tabula or 7-Zip.

    By default it downloads 57L2RMemberVotingHistory.zip (57th
    Legislature, 2nd Regular Session) from the AZLegInfo datasets repository,
    https://codeberg.org/AZLegInfo/datasets. A local zip can be read with a
    file:// URL.

    Expects:
        url (optional) is the address of the .zip file

    Returns
        A Dict mapping each legislator's name, as printed after "Member:"
        in their PDF (for example "ALLEN" or "CONTRERAS L"), to the
        DataFrame of their votes: member, bill, chapter ("V" = vetoed,
        "" = none, "1 E" = chapter 1 with an emergency clause),
        short_title, now_title ("" = none), vote (Y, N, NV, EXC, AB, P,
        ...), vote_type (FINAL, THIRD, a committee, ...), date, ayes, nays,
        not_voting, excused, and vacant.

    Citations:
      Text generated by ChatGPT, OpenAI, September 22, 2026, https://chatgpt.com/s/t_6ab2ce120dc88191becfac3228d8f310.
      Code generated by Claude Code, Anthropic, September 22, 2026, https://claude.ai/code/session_01SQ79sYVPmqwp7yFkriCVsL.
      Code revised by Claude Code, Anthropic, September 24, 2026, https://claude.ai/code/session_01542N3c5SpE51oTVJxy4bV1.
    """

    function extract_text_rows(pdf_path::AbstractString; columns=Float64[], pages=nothing)
        """
        Extracts the lines of text from a PDF, split into columns

        PDFIO opens the PDF and decodes its objects and streams. Each page's
        content stream is then run through a small interpreter for the PDF
        text operators (Tf, Td, TD, Tm, T*, Tj, TJ, ', ", Tc, Tw, Tz, TL,
        Ts, cm, q, Q) that records where every character is drawn. Character
        codes are turned into text with the font's ToUnicode map, or with
        WinAnsiEncoding for simple fonts without one, and the font's glyph
        widths give each character's width.

        Characters whose baselines are within 2 points of each other are one
        line; a space is put between characters that are more than a fifth of
        the font size apart.

        Expects:
            pdf_path is the path to the pdf
            columns (optional) is a list of x positions, in points from the
              left edge of the page, where one column ends and the next
              begins. A character goes in the column its left edge is in.
            pages (optional) is a list of page numbers to read, starting at 1;
              by default every page is read.

        Returns
           A DataFrame with one row per line of text, top to bottom and page
           by page, and columns named column_1, column_2, ... (one more than
           the number of boundaries in columns). Lines with no text are left
           out. Header rows repeated on each page are kept.

        Citations:
          Code generated by Claude Code, Anthropic, September 24, 2026, https://claude.ai/code/session_01542N3c5SpE51oTVJxy4bV1.
        """
        isfile(pdf_path) || throw(ArgumentError("No such file: $pdf_path"))

        # WinAnsiEncoding is Latin-1 except for 0x80-0x9F.
        winansi_80_9f = collect("€�‚ƒ„…†‡ˆ‰Š‹Œ�Ž��‘’“”•–—˜™š›œ�žŸ")

        doc = pdDocOpen(pdf_path)
        cosdoc = pdDocGetCosDoc(doc)
        resolve(x) = cosDocGetObject(cosdoc, x)
        lookup(dict, key) = dict === CosNull ? CosNull : resolve(get(resolve(dict), CosName(key)))
        number(x) = Float64(get(resolve(x)))
        stream_bytes(stm) = (io = get(resolve(stm)); bytes = read(io); close(io); bytes)

        # What the interpreter needs from a font: whether its character codes
        # are 1 or 2 bytes, each code's width (in 1/1000 of the font size),
        # and each code's text.
        function load_font(fontdict)
            fontdict === CosNull && return (twobyte=false, widths=Dict{Int,Float64}(),
                                            default_width=0.0, tounicode=Dict{Int,String}())
            twobyte = lookup(fontdict, "Subtype") == cn"Type0"
            widths = Dict{Int,Float64}()
            default_width = 0.0
            if twobyte
                # W is [first [w1 w2 ...] first last w ...].
                descendant = resolve(get(lookup(fontdict, "DescendantFonts"))[1])
                dw = lookup(descendant, "DW")
                default_width = dw === CosNull ? 1000.0 : number(dw)
                w = lookup(descendant, "W")
                items = w === CosNull ? [] : [resolve(x) for x in get(w)]
                i = 1
                while i <= length(items)
                    first = Int(get(items[i]))
                    if items[i+1] isa CosArray
                        for (k, x) in enumerate(get(items[i+1]))
                            widths[first+k-1] = number(x)
                        end
                        i += 2
                    else
                        foreach(c -> widths[c] = number(items[i+2]), first:Int(get(items[i+1])))
                        i += 3
                    end
                end
            else
                first = lookup(fontdict, "FirstChar")
                w = lookup(fontdict, "Widths")
                if first !== CosNull && w !== CosNull
                    for (k, x) in enumerate(get(w))
                        widths[Int(get(first))+k-1] = number(x)
                    end
                end
            end

            # The ToUnicode CMap's bfchar and bfrange entries, in UTF-16BE hex.
            tounicode = Dict{Int,String}()
            tu = lookup(fontdict, "ToUnicode")
            if tu !== CosNull
                cmap = String(stream_bytes(tu))
                hex(s) = parse(Int, s; base=16)
                utf16(s) = transcode(String, [UInt16(hex(s[i:i+3])) for i in 1:4:length(s)-3])
                for block in eachmatch(r"beginbfchar(.*?)endbfchar"s, cmap),
                    m in eachmatch(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>", block.captures[1])
                    tounicode[hex(m.captures[1])] = utf16(m.captures[2])
                end
                for block in eachmatch(r"beginbfrange(.*?)endbfrange"s, cmap),
                    m in eachmatch(r"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]*>|\[[^\]]*\])", block.captures[1])
                    lo, hi, dst = hex(m.captures[1]), hex(m.captures[2]), m.captures[3]
                    if startswith(dst, "[")
                        for (k, d) in enumerate(eachmatch(r"<([0-9A-Fa-f]*)>", dst))
                            tounicode[lo+k-1] = utf16(d.captures[1])
                        end
                    else
                        # Only the last UTF-16 unit counts up through the range.
                        start = utf16(dst[2:end-1])
                        for c in lo:hi
                            tounicode[c] = start[1:prevind(start, end)] * string(start[end] + (c - lo))
                        end
                    end
                end
            end
            (twobyte=twobyte, widths=widths, default_width=default_width, tounicode=tounicode)
        end

        # Splits a content stream into operands (Float64 numbers, Symbol names
        # such as Symbol("/TT0"), Vector{UInt8} strings, Vector{Any} arrays)
        # and operators (String), calling on_operator(op, operands) for each
        # operator. Dictionaries only appear as marked-content properties,
        # which are not needed, so their contents are passed along unparsed.
        is_space(b) = b in (0x00, 0x09, 0x0a, 0x0c, 0x0d, 0x20)
        is_delimiter(b) = b in b"()<>[]{}/%"
        escapes = Dict(UInt8('n') => 0x0a, UInt8('r') => 0x0d, UInt8('t') => 0x09,
                       UInt8('b') => 0x08, UInt8('f') => 0x0c)

        function each_operator(on_operator, data::Vector{UInt8})
            operands = Any[]
            arrays = Vector{Any}[]
            add(x) = push!(isempty(arrays) ? operands : arrays[end], x)
            i, n = 1, length(data)
            while i <= n
                b = data[i]
                if is_space(b)
                    i += 1
                elseif b == UInt8('%')
                    while i <= n && data[i] != 0x0a && data[i] != 0x0d
                        i += 1
                    end
                elseif b == UInt8('(')
                    # Literal string; parentheses nest, backslash escapes.
                    bytes = UInt8[]
                    depth = 1
                    i += 1
                    while i <= n
                        c = data[i]
                        if c == UInt8('\\') && i < n
                            i += 1
                            c = data[i]
                            if haskey(escapes, c)
                                push!(bytes, escapes[c])
                            elseif UInt8('0') <= c <= UInt8('7')
                                j = i
                                while j < i + 3 && j <= n && UInt8('0') <= data[j] <= UInt8('7')
                                    j += 1
                                end
                                push!(bytes, UInt8(parse(Int, String(data[i:j-1]); base=8) & 0xff))
                                i = j - 1
                            elseif c == 0x0d
                                i < n && data[i+1] == 0x0a && (i += 1)  # line continuation
                            elseif c != 0x0a
                                push!(bytes, c)
                            end
                        elseif c == UInt8('(')
                            depth += 1
                            push!(bytes, c)
                        elseif c == UInt8(')')
                            depth -= 1
                            depth == 0 && break
                            push!(bytes, c)
                        else
                            push!(bytes, c)
                        end
                        i += 1
                    end
                    add(bytes)
                    i += 1
                elseif b == UInt8('<') && i < n && data[i+1] == UInt8('<')
                    i += 2
                elseif b == UInt8('>') && i < n && data[i+1] == UInt8('>')
                    i += 2
                elseif b == UInt8('<')
                    # Hex string; a missing final digit is 0.
                    j = something(findnext(==(UInt8('>')), data, i), n + 1)
                    digits = filter(!is_space, data[i+1:j-1])
                    isodd(length(digits)) && push!(digits, UInt8('0'))
                    add(hex2bytes(digits))
                    i = j + 1
                elseif b == UInt8('[')
                    push!(arrays, Any[])
                    i += 1
                elseif b == UInt8(']')
                    isempty(arrays) || (a = pop!(arrays); add(a))
                    i += 1
                elseif b == UInt8('{') || b == UInt8('}') || b == UInt8(')') || b == UInt8('>')
                    i += 1
                else
                    j = i + (b == UInt8('/'))
                    while j <= n && !is_space(data[j]) && !is_delimiter(data[j])
                        j += 1
                    end
                    word = String(data[i:j-1])
                    i = j
                    if startswith(word, "/")
                        add(Symbol(word))
                    elseif (v = tryparse(Float64, word)) !== nothing
                        add(v)
                    elseif !isempty(arrays)
                        add(word)  # true, false or null inside an array
                    else
                        on_operator(word, operands)
                        empty!(operands)
                        if word == "ID"
                            # Inline image data runs to "EI".
                            k = findnext(b"EI", data, i)
                            i = k === nothing ? n + 1 : last(k) + 1
                        end
                    end
                end
            end
        end

        # Matrices are (a, b, c, d, e, f), as in the PDF specification.
        multiply(m, n) = (m[1]*n[1] + m[2]*n[3], m[1]*n[2] + m[2]*n[4],
                          m[3]*n[1] + m[4]*n[3], m[3]*n[2] + m[4]*n[4],
                          m[5]*n[1] + m[6]*n[3] + n[5], m[5]*n[2] + m[6]*n[4] + n[6])
        translate(x, y) = (1.0, 0.0, 0.0, 1.0, Float64(x), Float64(y))
        identity_matrix = translate(0, 0)

        # One entry per character drawn: the x of its left and right edges,
        # the y of its baseline, its font size, and its text.
        Character = @NamedTuple{page::Int, x0::Float64, x1::Float64, y::Float64,
                                size::Float64, text::String}

        function page_characters(page_number, page)
            node = pdPageGetCosObject(page)
            resources = CosNull
            while node !== CosNull && resources === CosNull  # inherited from parents
                resources = lookup(node, "Resources")
                resources === CosNull && (node = lookup(node, "Parent"))
            end
            font_dicts = lookup(resources, "Font")
            fonts = Dict{Symbol,Any}()
            get_font(name) = get!(() -> load_font(lookup(font_dicts, String(name)[2:end])), fonts, name)

            contents = pdPageGetContents(page)
            data = contents === CosNull ? UInt8[] :
                contents isa CosArray ?
                    reduce(vcat, [vcat(stream_bytes(s), UInt8('\n')) for s in get(contents)]; init=UInt8[]) :
                    stream_bytes(contents)

            characters = Character[]
            ctm = identity_matrix
            saved = Any[]
            tm = tlm = identity_matrix
            font = load_font(CosNull)
            font_size = char_spacing = word_spacing = leading = rise = 0.0
            scale = 1.0

            function show_text(bytes)
                step = font.twobyte ? 2 : 1
                for k in 1:step:(length(bytes) - step + 1)
                    code = step == 2 ? Int(bytes[k]) << 8 | bytes[k+1] : Int(bytes[k])
                    text = get(font.tounicode, code) do
                        font.twobyte ? "�" :
                            0x80 <= code <= 0x9f ? string(winansi_80_9f[code-0x7f]) :
                            string(Char(code))
                    end
                    width = get(font.widths, code, font.default_width) / 1000 * font_size
                    trm = multiply((font_size * scale, 0.0, 0.0, font_size, 0.0, rise), multiply(tm, ctm))
                    right = multiply((1.0, 0.0, 0.0, 1.0, width * scale, rise), multiply(tm, ctm))
                    push!(characters, (page=page_number, x0=trm[5], x1=right[5], y=trm[6],
                                       size=abs(trm[4]), text=text))
                    advance = (width + char_spacing + (step == 1 && code == 32 ? word_spacing : 0.0)) * scale
                    tm = multiply(translate(advance, 0), tm)
                end
            end

            each_operator(data) do op, o
                if op == "q"
                    push!(saved, ctm)
                elseif op == "Q"
                    isempty(saved) || (ctm = pop!(saved))
                elseif op == "cm" && length(o) >= 6
                    ctm = multiply(Tuple(Float64.(o[1:6])), ctm)
                elseif op == "BT"
                    tm = tlm = identity_matrix
                elseif op == "Tf" && length(o) >= 2
                    font, font_size = get_font(o[1]), o[2]
                elseif op == "Tc"
                    char_spacing = o[1]
                elseif op == "Tw"
                    word_spacing = o[1]
                elseif op == "Tz"
                    scale = o[1] / 100
                elseif op == "TL"
                    leading = o[1]
                elseif op == "Ts"
                    rise = o[1]
                elseif op == "Td" || op == "TD"
                    op == "TD" && (leading = -o[2])
                    tm = tlm = multiply(translate(o[1], o[2]), tlm)
                elseif op == "Tm" && length(o) >= 6
                    tm = tlm = Tuple(Float64.(o[1:6]))
                elseif op == "T*"
                    tm = tlm = multiply(translate(0, -leading), tlm)
                elseif op == "Tj"
                    show_text(o[1])
                elseif op == "'" || op == "\""
                    op == "\"" && ((word_spacing, char_spacing) = (o[1], o[2]))
                    tm = tlm = multiply(translate(0, -leading), tlm)
                    show_text(o[end])
                elseif op == "TJ"
                    for x in o[1]
                        # Numbers move the next character left, in 1/1000 of the font size.
                        x isa Vector{UInt8} ? show_text(x) :
                            x isa Float64 && (tm = multiply(translate(-x / 1000 * font_size * scale, 0), tm))
                    end
                end
            end
            characters
        end

        boundaries = sort(Float64.(collect(columns)))
        rows = Vector{Vector{String}}()

        try
            for page_number in something(pages, 1:pdDocGetPageCount(doc))
                characters = sort(page_characters(page_number, pdDocGetPage(doc, page_number)),
                                  by=c -> (-c.y, c.x0))
                # Split into lines, top to bottom, at vertical gaps over 2 points.
                lines = Vector{Vector{Character}}()
                for c in characters
                    if isempty(lines) || lines[end][1].y - c.y > 2
                        push!(lines, [c])
                    else
                        push!(lines[end], c)
                    end
                end
                for line in lines
                    sort!(line, by=c -> c.x0)
                    cells = [IOBuffer() for _ in 1:(length(boundaries) + 1)]
                    last_right = fill(-Inf, length(cells))
                    for c in line
                        cell = searchsortedlast(boundaries, c.x0) + 1
                        c.x0 - last_right[cell] > c.size / 5 && print(cells[cell], ' ')
                        print(cells[cell], c.text)
                        last_right[cell] = max(last_right[cell], c.x1)
                    end
                    texts = [String(strip(replace(Base.Unicode.normalize(String(take!(io)), :NFKC),
                                                  r"\s+" => " "))) for io in cells]
                    all(isempty, texts) || push!(rows, texts)
                end
            end
        finally
            pdDocClose(doc)
        end

        DataFrame([getindex.(rows, i) for i in 1:(length(boundaries) + 1)],
                  Symbol.("column_" .* string.(1:(length(boundaries) + 1))))
    end

    bill_cell = r"^((?:HB|SB|HCR|SCR|HCM|SCM|HJR|SJR|HR|SR|HM|SM)\d{4})(?:\s+(.+))?$"
    vote_line = r"^(\S+)\s+(.+?)\s+(\d\d/\d\d/\d\d)\s+(\d+)-(\d+)-(\d+)-(\d+)-(\d+)$"
    totals_pattern = r"AYES\s*=\s*(\d+)\s*NAYS\s*=\s*(\d+)\s*NV\s*=\s*(\d+)\s*EXC\s*=\s*(\d+)\s*TOTAL\s*VOTES\s*=\s*(\d+)"

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
          Code revised by Claude Code, Anthropic, September 24, 2026, https://claude.ai/code/session_01542N3c5SpE51oTVJxy4bV1.
        """
        # The "Member:" line can run past x = 160 (below), where the columns
        # would split it, so it is read from page 1 without columns.
        member = nothing
        for line in extract_text_rows(pdf_path; pages=[1]).column_1
            m = match(r"^Member:\s*(.+)$", line)
            m === nothing || (member = String(m.captures[1]); break)
        end
        member === nothing && throw(ArgumentError("Not a Member Voting History PDF: $pdf_path"))

        # Bill number (x = 36) and chapter (x = 99) sit left of x = 160; the
        # short title, NOW: line and vote lines start at x = 168.
        rows = extract_text_rows(pdf_path; columns=[160])

        votes = DataFrame(
            member=String[], bill=String[], chapter=String[], short_title=String[],
            now_title=String[], vote=String[], vote_type=String[], date=Date[],
            ayes=Int[], nays=Int[], not_voting=Int[], excused=Int[], vacant=Int[],
        )

        bill = chapter = short_title = now_title = ""
        totals_line = ""
        in_header = false

        for (left, right) in zip(rows.column_1, rows.column_2)
            # Every page repeats the title, legend and column headings.
            if startswith(right, "Member Voting History")
                in_header = true
            elseif in_header
                in_header = right != "Vote/Vote Type"
            elseif isempty(left) && occursin(r"^\d+$", right)
                continue  # page number
            elseif startswith(left, "AYES")
                # Split at x = 160, possibly mid-word; totals_pattern ignores spacing.
                totals_line = left * right
                break
            elseif (b = match(bill_cell, left)) !== nothing
                bill, chapter = b.captures[1], something(b.captures[2], "")
                short_title, now_title = right, ""
            elseif startswith(right, "NOW:")
                now_title = strip(right[5:end])
            elseif (v = match(vote_line, right)) !== nothing
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
        t = match(totals_pattern, totals_line)
        if t === nothing
            @warn "No vote totals found to check against" pdf_path
        else
            expected = parse.(Int, t.captures[1:4])
            parsed = [count(==(code), votes.vote) for code in ("Y", "N", "NV", "EXC")]
            parsed == expected || @warn "Parsed vote counts differ from the PDF's totals" pdf_path expected parsed
        end

        votes, member
    end

    histories = Dict{String,DataFrame}()

    mktemp() do zip_path, io
        close(io)
        Downloads.download(url, zip_path)
        read(zip_path, 2) == b"PK" || error("Not a zip file: $url")

        mktempdir() do dir
            # Each PDF is written out under a numbered name, since the same
            # file name can appear in more than one folder of the zip.
            pdfs = Pair{String,String}[]
            reader = ZipFile.Reader(zip_path)
            try
                for (k, entry) in enumerate(reader.files)
                    file = basename(entry.name)
                    # Skip folders and the "._name.pdf" metadata files macOS adds to zips.
                    (endswith(lowercase(file), ".pdf") && !startswith(file, "._")) || continue
                    pdf = joinpath(dir, "$k.pdf")
                    write(pdf, read(entry))
                    push!(pdfs, file => pdf)
                end
            finally
                close(reader)
            end

            for (_, pdf) in sort(pdfs; by=first)
                votes, member = extract_voting_history(pdf)
                haskey(histories, member) && error("Two PDFs in the zip are for $member")
                histories[member] = votes
            end
        end
    end

    histories
end

session57HouseLegislativeMemberVotingHistory = getSession57HouseLegislativeMemberVotingHistory()



end # module
