# Regenerates the test PDFs: pip install reportlab && python make_fixtures.py test/data
import csv
import sys

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

out = sys.argv[1]

# Generic tables: 80 rows over 3 pages, with and without ruling lines.
header = ["Bill", "Short Title", "Date", "Motion", "Vote"]
rows = [header] + [
    [f"SB{1000 + i}", f"appropriation; item {i}", f"02/{(i % 28) + 1:02d}/2026",
     "3rd Read" if i % 2 else "Final Read", ["Y", "N", "NV", "EXC"][i % 4]]
    for i in range(80)
]


def build_table(path, ruled):
    doc = SimpleDocTemplate(path, pagesize=letter)
    t = Table(rows, repeatRows=1)
    style = [("FONTSIZE", (0, 0), (-1, -1), 9)]
    if ruled:
        style.append(("GRID", (0, 0), (-1, -1), 0.5, colors.black))
    t.setStyle(TableStyle(style))
    title = Paragraph("Member Voting History - Test Member", getSampleStyleSheet()["Title"])
    doc.build([title, Spacer(1, 12), t])


build_table(f"{out}/votes_ruled.pdf", ruled=True)
build_table(f"{out}/votes_unruled.pdf", ruled=False)

# Member Voting History: same layout, fonts and x positions as the House
# PDFs (57th Legislature, 2nd Regular Session), with made-up bills.
CODES = ["Y", "N", "NV", "EXC", "AB", "P"]
TYPES = ["THIRD", "FINAL", "ED", "THIRD (R)", "COW MOTION", "RULES"]
CHAPTERS = ["V", "", "191", "1 E"]
bills = []
for i in range(40):
    n_votes = 1 + i % 3
    bills.append({
        "bill": f"{'HB' if i < 30 else 'SCR'}{2003 + i if i < 30 else 1001 + i}",
        "chapter": CHAPTERS[i % 4],
        "short_title": f"test subject {i}; requirements; study (Member{i % 5})",
        "now_title": f"new subject {i}; revisions" if i % 7 == 3 else "",
        "votes": [(CODES[(i + k) % 6], TYPES[(i + 2 * k) % 6],
                   f"0{1 + (i + k) % 6}/{10 + k:02d}/26", (30 + k, 20 - k, 5, k % 2, 0))
                  for k in range(n_votes)],
    })

LEGEND = [
    ("Y= Aye", "LIVS = Line Item Veto Signed", "E = Emergency"),
    ("N = Nay", "V/O = Veto Override", "W/O = Without Emergency"),
    ("NV = Not Voting", "W/S = Without Signature", "R = Reconsideration"),
    ("EXC = Excused", "V = Vetoed", "RFE = Requirements for Enactment"),
    ("VAC = Vacant", "SS = Secretary of State", "RFEIR = Requirements for Enactment, Initiative and Referendum"),
]
H = letter[1]


def page_header(c, page_no):
    c.setFont("Helvetica-Bold", 13); c.drawString(181.4, H - 48.2, "Member Voting History")
    c.setFont("Helvetica", 8); c.drawString(544.9, H - 48.2, "07/06/26")
    c.setFont("Times-Roman", 10); c.drawString(149.2, H - 60.3, "Fifty-seventh Legislature - Second Regular Session")
    c.setFont("Helvetica", 7)
    for j, (left, mid, right) in enumerate(LEGEND):
        y = H - (77.0 + 8.07 * j)
        c.drawString(36, y, left); c.drawCentredString(250, y, mid); c.drawRightString(576, y, right)
    c.setFont("Helvetica-Bold", 10); c.drawString(36, H - 128.2, "Member: TESTMEMBER")
    c.setFont("Helvetica", 9)
    for x, label in [(36, "Bill Number"), (99.4, "Chapter"), (167.8, "Short Title"),
                     (275.8, "Date"), (344.9, "A-N-NV-EXC-VAC")]:
        c.drawString(x, H - 138.7, label)
    c.drawString(167.8, H - 149.0, "Vote/Vote Type")
    c.setFont("Helvetica", 11); c.drawCentredString(306, H - 752.9, str(page_no))
    c.setFont("Helvetica", 10)


c = canvas.Canvas(f"{out}/voting_history.pdf", pagesize=letter)
page_no, y = 1, 160.4
page_header(c, page_no)


def line(draw):
    global y, page_no
    if y > 730:
        c.showPage(); page_no += 1; y = 160.4
        page_header(c, page_no)
    draw(H - y)
    y += 20.2


for b in bills:
    line(lambda yy: (c.drawString(36, yy, b["bill"]), c.drawString(99.4, yy, b["chapter"]),
                     c.drawString(167.8, yy, b["short_title"])))
    if b["now_title"]:
        line(lambda yy: c.drawString(167.8, yy, "    NOW: " + b["now_title"]))
    for code, vtype, date, tally in b["votes"]:
        line(lambda yy: (c.drawString(167.8, yy, f"{code}    {vtype}"), c.drawString(275.8, yy, date),
                         c.drawString(344.9, yy, "-".join(map(str, tally)))))

counts = {code: sum(v[0] == code for b in bills for v in b["votes"]) for code in ("Y", "N", "NV", "EXC")}
y += 40
c.setFont("Helvetica-Bold", 10)
for x, text in [(108, f"AYES = {counts['Y']}"), (180, f"NAYS = {counts['N']}"), (252, f"NV = {counts['NV']}"),
                (324, f"EXC = {counts['EXC']}"), (396, f"TOTAL VOTES = {sum(counts.values())}")]:
    c.drawString(x, H - y, text)
c.save()

with open(f"{out}/voting_history_expected.tsv", "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["bill", "chapter", "short_title", "now_title", "vote", "vote_type", "date",
                "ayes", "nays", "not_voting", "excused", "vacant"])
    for b in bills:
        for code, vtype, date, tally in b["votes"]:
            mm, dd, yy = date.split("/")
            w.writerow([b["bill"], b["chapter"], b["short_title"], b["now_title"], code, vtype,
                        f"20{yy}-{mm}-{dd}", *tally])
