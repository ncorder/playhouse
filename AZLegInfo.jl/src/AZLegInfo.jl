"""
    AZLegInfo

AZLegInfo is a package to get data conerning the Arizona State Legislature, and to some extent, the
"""

module AZLegInfo
using DataFrames, HTTP, JSON3, Downloads, Dates, CSV, Gumbo, NamedArrays

# Readers for PDFs and zip files written in pure Julia
include("PDFText.jl")
include("ZipReader.jl")

export getSessions, getBillID, getBillInfo, getBillPositions_JSON, session57HouseLegislativeMemberVotingHistory, equalityArizona2022SineDieReport, getBillIntroducedVersionText, getSession57HouseLegislativeMemberVotingHistory_OneHotEncoding

votingTypes = Dict(
  "Y"   =>   :"Aye",
  "N"   =>   :"Nay",
  "NV"  =>   :"Not_Voting",
  "EXC" =>   :"Excused",
  "VAC" =>   :"Vacant",
  )

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

    The zip is downloaded into memory; nothing is written to disk. Every .pdf
    in the zip, in any folder, is read with the nested extract_voting_history.

    The zip and the PDFs are read with native Julia code only: by ZipReader and
    PDFText (both in this package's src folder), which decompress with the
    pure-Julia Inflate package. Neither Java nor any other program is needed.
    Encrypted PDFs (even ones that open without a password) are not supported.

    It warns if a PDF's vote counts differ from the totals printed in it, or if
    a line of a PDF is not recognized (it is then added to the bill's title),
    and raises an error if the zip has no PDFs or two PDFs for the same member.

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
      Code revised to use only native Julia libraries by Claude Code, Anthropic, September 24, 2026, https://claude.ai/code/session_019awDnsGJAcXbzPNQg6VhqU.
    """

    bill_cell = r"^((?:HB|SB|HCR|SCR|HCM|SCM|HJR|SJR|HR|SR|HM|SM)\d{4})(?:\s+(.+))?$"
    vote_line = r"^(\S+)\s+(.+?)\s+(\d\d/\d\d/\d\d)\s+(\d+)-(\d+)-(\d+)-(\d+)-(\d+)$"
    totals_pattern = r"AYES\s*=\s*(\d+)\s*NAYS\s*=\s*(\d+)\s*NV\s*=\s*(\d+)\s*EXC\s*=\s*(\d+)\s*TOTAL\s*VOTES\s*=\s*(\d+)"

    function extract_voting_history(pdf::Vector{UInt8}, file::AbstractString)
        """
        Extracts every vote from a House Member Voting History PDF

        Each bill in the PDF is a bill line (bill number, chapter, short title
        and sponsor), an optional "NOW:" line with the bill's new title, and
        one line per vote (vote, vote type, date, and the
        A-N-NV-EXC-VAC tally). This turns those lines into one row per vote,
        and warns if the Y/N/NV/EXC counts differ from the totals printed at
        the end of the PDF.

        PDFText.read_lines reads the PDF's text as lines of words, each with
        its position on the page, so the bill number and chapter are told
        apart from the short title by where they are, not by guessing.

        Expects:
            pdf is the contents of a Member Voting History pdf
            file is its name, for error messages

        Returns
            The member's name, as printed after "Member:", and a DataFrame
            with one row per vote and the columns member, bill, chapter
            ("V" = vetoed, "" = none, "1 E" = chapter 1 with an emergency
            clause), short_title, now_title ("" = none), vote (Y, N, NV,
            EXC, AB, P, ...), vote_type (FINAL, THIRD, a committee, ...),
            date, ayes, nays, not_voting, excused, and vacant.

        Citations:
          Code generated by Claude Code, Anthropic, September 22, 2026, https://claude.ai/code/session_01SQ79sYVPmqwp7yFkriCVsL.
          Code revised to use PDFText by Claude Code, Anthropic, September 24, 2026, https://claude.ai/code/session_019awDnsGJAcXbzPNQg6VhqU.
        """
        pages = PDFText.read_lines(pdf)

        # Every page repeats the heading, which names the member and has the
        # column headings. The bill number (x = 36) and chapter (x = 99) are
        # left of the "Short Title" heading (x = 168), where the short title,
        # NOW: line and vote lines start.
        member = nothing
        title_x = nothing
        for line in pages[1]
            text = PDFText.text(line)
            m = match(r"^Member:\s*(.+)$", text)
            m === nothing || (member = String(m.captures[1]))
            if startswith(text, "Bill Number")
                i = findfirst(w -> w.text == "Short", line.words)
                i === nothing || (title_x = line.words[i].x)
            end
        end
        (member === nothing || title_x === nothing) &&
            throw(ArgumentError("Not a Member Voting History PDF: $file"))
        # A few points of slack, as the text drifts slightly across a page.
        column = title_x - 5

        votes = DataFrame(
            member=String[], bill=String[], chapter=String[], short_title=String[],
            now_title=String[], vote=String[], vote_type=String[], date=Date[],
            ayes=Int[], nays=Int[], not_voting=Int[], excused=Int[], vacant=Int[],
        )

        bill = chapter = short_title = now_title = ""
        voted = false  # whether the current bill has had a vote line
        totals = nothing
        in_header = false

        for page in pages, line in page
            totals === nothing || break  # nothing but the page number follows the totals
            text = PDFText.text(line)
            left = join((w.text for w in line.words if w.x < column), " ")
            right = join((w.text for w in line.words if w.x >= column), " ")
            if startswith(text, "Member Voting History")
                in_header = true
            elseif in_header
                in_header = text != "Vote/Vote Type"
            elseif isempty(left) && occursin(r"^\d+$", right)
                continue  # page number
            elseif (t = match(totals_pattern, text)) !== nothing
                # The PDF's own totals, which leave out committee codes (AB, P).
                totals = parse.(Int, t.captures[1:4])
            elseif (b = match(bill_cell, left)) !== nothing
                bill, chapter = b.captures[1], something(b.captures[2], "")
                short_title, now_title = right, ""
                voted = false
            elseif startswith(right, "NOW:")
                now_title = strip(right[5:end])
            elseif (v = match(vote_line, right)) !== nothing
                isempty(bill) && error("Vote before any bill in $file: $right")
                push!(votes, (
                    member, bill, chapter, short_title, now_title,
                    v.captures[1], v.captures[2],
                    Date(v.captures[3], dateformat"mm/dd/yy") + Year(2000),
                    parse.(Int, v.captures[4:8])...,
                ))
                voted = true
            else
                # The rest of a title or NOW: line too long for one line. Text
                # in the bill or chapter column, or after a vote, is not that.
                (isempty(left) && !voted) || @warn "Unrecognized line added to the title of $bill" file text
                if isempty(now_title)
                    short_title = join(filter(!isempty, [short_title, left, right]), " ")
                else
                    now_title = join(filter(!isempty, [now_title, left, right]), " ")
                end
            end
        end

        if totals === nothing
            @warn "No vote totals found to check against" file
        else
            parsed = [count(==(code), votes.vote) for code in ("Y", "N", "NV", "EXC")]
            parsed == totals || @warn "Parsed vote counts differ from the PDF's totals" file expected=totals parsed
        end

        member, votes
    end

    histories = Dict{String,DataFrame}()

    archive = take!(Downloads.download(url, IOBuffer()))
    (length(archive) >= 2 && archive[1:2] == b"PK") || error("Not a zip file: $url")

    # Only the PDFs are decompressed, skipping the "._name.pdf" metadata files
    # macOS adds to zips.
    is_pdf(path) = (file = basename(path); endswith(lowercase(file), ".pdf") && !startswith(file, "._"))

    for (path, contents) in sort(ZipReader.read_zip(archive; keep=is_pdf), by=first)
        member, votes = extract_voting_history(contents, path)
        haskey(histories, member) && error("Two PDFs in the zip are for $member")
        histories[member] = votes
    end
    isempty(histories) && error("No PDFs in the zip: $url")

    histories
end

session57HouseLegislativeMemberVotingHistory = getSession57HouseLegislativeMemberVotingHistory()

function findAllBillActions(MVH::Dict{String, DataFrame})
           
           possibleBillActions = ["Aye", "Nay", "Not_Voting", "Excused", "Vacant"]
           
           billActions = Set()
           for (key, value) in MVH
               for row in eachrow(value)
                   for possibleAction in possibleBillActions
                       push!(billActions, row.bill * "_" * row.vote_type * "_" * possibleAction)
                       if !(row.vote in keys(votingTypes))
                           push!(billActions, row.bill * "_" * row.vote_type * "_" * row.vote)
                           end
                       end
               end
           return sort(collect(billActions))
           end
       end

function getSession57HouseLegislativeMemberVotingHistory_OneHotEncoding()
  emptyMatrix = Array{Union{Missing,Int8}}(
    missing,
    length(findAllBillActions(session57HouseLegislativeMemberVotingHistory)),
    length(collect(keys(session57HouseLegislativeMemberVotingHistory)))
    )

  session57HouseLegislativeMemberVotingHistory_OneHotEncoding = NamedArray(emptyMatrix, (collect(findAllBillActions(session57HouseLegislativeMemberVotingHistory)), collect(keys(session57HouseLegislativeMemberVotingHistory))), (:billAction, :member))

  for (key, memberDf) in session57HouseLegislativeMemberVotingHistory
               
               for row in eachrow(memberDf)
                      if (row.vote in keys(votingTypes))
                           billAction = row.bill * "_" * row.vote_type * "_" * votingTypes[row.vote]
                      else
                           billAction = row.bill * "_" * row.vote_type * "_" * row.vote
                           end
                      possibleBillActions = ["Aye", "Nay", "Not_Voting", "Excused", "Vacant"]
                 
                      for possibleBillAction in possibleBillActions
                          println(row.member)
                           if possibleBillAction == row.vote
                               session57HouseLegislativeMemberVotingHistory_OneHotEncoding[billAction, row.member] = Int8(1)
                           else
                               session57HouseLegislativeMemberVotingHistory_OneHotEncoding[billAction, row.member] = Int8(0)
                          end
                       end
                end
    return session57HouseLegislativeMemberVotingHistory_OneHotEncoding
    end
  
  end


end # module
