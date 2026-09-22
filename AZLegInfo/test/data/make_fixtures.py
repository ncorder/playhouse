# Regenerates the test PDFs: pip install reportlab && python make_fixtures.py test/data
import sys
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors

out = sys.argv[1]
header = ["Bill", "Short Title", "Date", "Motion", "Vote"]
rows = [header] + [
    [f"SB{1000 + i}", f"appropriation; item {i}", f"02/{(i % 28) + 1:02d}/2026",
     "3rd Read" if i % 2 else "Final Read", ["Y", "N", "NV", "EXC"][i % 4]]
    for i in range(80)
]

styles = getSampleStyleSheet()


def build(path, ruled):
    doc = SimpleDocTemplate(path, pagesize=letter)
    t = Table(rows, repeatRows=1)
    style = [("FONTSIZE", (0, 0), (-1, -1), 9)]
    if ruled:
        style.append(("GRID", (0, 0), (-1, -1), 0.5, colors.black))
    t.setStyle(TableStyle(style))
    doc.build([Paragraph("Member Voting History - Test Member", styles["Title"]), Spacer(1, 12), t])


build(f"{out}/votes_ruled.pdf", ruled=True)
build(f"{out}/votes_unruled.pdf", ruled=False)
