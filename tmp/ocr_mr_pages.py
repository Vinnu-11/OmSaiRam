#!/usr/bin/env python3
"""OCR every page of the Marathi PDF into tmp/ocr_cache/mr_pages.json (one string per page)."""

import io
import json
import os
from multiprocessing import Pool

os.environ["OMP_THREAD_LIMIT"] = "1"  # else N workers x 16 OMP threads thrash

import fitz
import pytesseract
from PIL import Image

PDF = "/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/source_pdfs/satcharita_mr.pdf"
OUT = "/home/vdamarl/pers/OmSaiRam/tmp/ocr_cache/mr_pages.json"


def ocr(i):
    doc = fitz.open(PDF)
    pix = doc[i].get_pixmap(dpi=200)
    doc.close()
    return pytesseract.image_to_string(
        Image.open(io.BytesIO(pix.tobytes("png"))), lang="mar", config="--psm 6"
    )


if __name__ == "__main__":
    n = len(fitz.open(PDF))
    with Pool(15) as p:
        pages = p.map(ocr, range(n))
    json.dump(pages, open(OUT, "w", encoding="utf-8"), ensure_ascii=False)
    print(n, "pages ->", OUT)
