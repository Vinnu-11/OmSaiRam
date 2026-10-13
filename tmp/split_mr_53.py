#!/usr/bin/env python3
"""Split the OCR'd Marathi Satcharita (tmp/ocr_cache/mr_pages.json) into 53 adhyayas.

Every adhyaya starts on a new page with "।। अथ श्रीसाईसच्चरित ।। अध्याय N वा ।।"
(adhyaya 1: "अथ श्री साईसच्चरितप्रारंभः"). Pages 0-3 and 327+ are cover scans.
Run tmp/ocr_mr_pages.py first.
"""

import json
import re

PAGES = "/home/vdamarl/pers/OmSaiRam/tmp/ocr_cache/mr_pages.json"
OUT = "/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_mr.json"
FIRST, LAST = 4, 326  # inclusive content page range

START = re.compile(r"अथ\s*श्री\s*साईसच्चरित")
HEADER = re.compile(r"^श्री\s*साईसच्चरित$")  # running page header
PAGE_NO = re.compile(r"^[\d०-९]{1,3}$")
COLOPHON = re.compile(r"ध्याय\S*\s*[॥।|]*\s*संपूर्ण")


def clean_page(text):
    lines = [l.strip() for l in text.split("\n")]
    lines = [l for l in lines if not HEADER.match(l) and not PAGE_NO.match(l)]
    return "\n".join(lines)


def clean(text):
    out = []
    for line in text.split("\n"):
        if line:
            out.append(line)
        elif out and out[-1]:
            out.append("")
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


if __name__ == "__main__":
    pages = json.load(open(PAGES, encoding="utf-8"))
    starts = [i for i in range(FIRST, LAST + 1)
              if any(START.search(l) for l in pages[i].split("\n")[:4])]
    if len(starts) != 53 or starts[0] != FIRST:
        raise SystemExit(f"expected 53 starts from page {FIRST}, got {len(starts)}: {starts}")
    bounds = starts + [LAST + 1]
    out = []
    for n in range(1, 54):
        content = clean("\n".join(clean_page(pages[i]) for i in range(bounds[n - 1], bounds[n])))
        colophon = [l for l in content.split("\n") if COLOPHON.search(l)]
        # Title = the "<name> नाम <ordinal>ऽध्यायः" part of the colophon, if OCR caught it.
        m = re.search(r"([^।|॥]+?)\s*नाम\s", colophon[-1]) if colophon else None
        title = m.group(1).strip() if m else f"अध्याय {n}"
        print(f"{n:2d} pages {bounds[n-1]:3d}-{bounds[n]-1:3d} {len(content):6d} chars  "
              f"colophon={'Y' if colophon else '-'}  {title[:50]}")
        out.append({
            "id": n, "number": n, "chapterLabel": str(n),
            "heading": f"अध्याय {n}", "title": title, "content": content,
            "language": "mr", "version": 1,
        })
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("wrote", OUT)
