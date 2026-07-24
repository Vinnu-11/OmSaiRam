#!/usr/bin/env python3
"""Extract Urdu, Spanish, French, and Deutsch Sai Satcharita."""

import fitz
import pytesseract
from PIL import Image
import io
import json
import re
import os
from multiprocessing import Pool, cpu_count

DPI = 150


def ocr_single_page(args):
    """OCR a single page."""
    pdf_path, page_idx, lang = args
    try:
        doc = fitz.open(pdf_path)
        page = doc[page_idx]
        pix = page.get_pixmap(dpi=DPI)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        text = pytesseract.image_to_string(img, lang=lang)
        doc.close()
        return (page_idx, text.strip())
    except Exception as e:
        return (page_idx, "")


def extract_pdf_ocr(pdf_path, lang, content_start, label):
    """Extract text from scanned PDF using OCR."""
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    doc.close()

    pages_to_process = list(range(content_start, total_pages))
    args_list = [(pdf_path, i, lang) for i in pages_to_process]

    num_workers = min(cpu_count(), 8)
    print(f"  {label}: Processing {len(pages_to_process)} pages with {num_workers} workers at {DPI} DPI...")

    with Pool(num_workers) as pool:
        results = pool.map(ocr_single_page, args_list)

    results.sort(key=lambda x: x[0])
    pages = [text for _, text in results if text]

    print(f"  {label}: OCR complete, {len(pages)} non-empty pages")
    return pages


def extract_pdf_text(pdf_path, content_start, label, strip_header=None):
    """Extract embedded text from PDF (no OCR needed)."""
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    pages = []
    for i in range(content_start, total_pages):
        text = doc[i].get_text().strip()
        if strip_header and text.startswith(strip_header):
            # Remove header lines
            lines = text.split('\n')
            text = '\n'.join(l for l in lines if not l.startswith(strip_header[:30]))
            text = text.strip()
        if text:
            pages.append(text)
    doc.close()
    print(f"  {label}: Extracted {len(pages)} non-empty pages (text mode)")
    return pages


def clean_text(text):
    lines = text.split('\n')
    cleaned = []
    for line in lines:
        line = line.strip()
        if line:
            cleaned.append(line)
        elif cleaned and cleaned[-1] != '':
            cleaned.append('')
    result = '\n'.join(cleaned)
    return re.sub(r'\n{3,}', '\n\n', result).strip()


def build_proportional_json(pages, lang_code, heading_prefix, en_chapters):
    """Build JSON by proportionally distributing pages into 47 chapters."""
    en_sizes = [len(ch['content']) for ch in en_chapters]
    total_en = sum(en_sizes)
    total_pages = len(pages)

    chapter_page_map = []
    for size in en_sizes:
        proportion = size / total_en
        num_pages = max(1, round(proportion * total_pages))
        chapter_page_map.append(num_pages)

    while sum(chapter_page_map) > total_pages:
        max_idx = chapter_page_map.index(max(chapter_page_map))
        chapter_page_map[max_idx] -= 1
    while sum(chapter_page_map) < total_pages:
        min_idx = chapter_page_map.index(min(chapter_page_map))
        chapter_page_map[min_idx] += 1

    json_output = []
    page_idx = 0
    for i in range(47):
        num_pages = chapter_page_map[i]
        chapter_pages = pages[page_idx:page_idx + num_pages]
        page_idx += num_pages

        content = '\n\n'.join(chapter_pages)
        content = clean_text(content)

        title = ''
        for line in content.split('\n')[:8]:
            line = line.strip()
            if (line and len(line) > 10 and
                not re.match(r'^[\d\s\-–—()]+$', line) and
                'PAGE' not in line.upper()):
                title = line[:200]
                break

        if not title:
            title = en_chapters[i]['title']

        json_output.append({
            "id": i + 1,
            "number": i + 1,
            "chapterLabel": str(i + 1),
            "heading": f"{heading_prefix} {i + 1}",
            "title": title,
            "content": content,
            "language": lang_code,
            "version": 1
        })

    return json_output


def main():
    en_path = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'
    with open(en_path, 'r') as f:
        en_chapters = json.load(f)

    # Urdu: scanned PDF, needs OCR, content starts page 3
    print("=== Urdu Extraction (OCR) ===")
    ur_pages = extract_pdf_ocr(
        '/home/vdamarl/pers/OmSaiRam/tmp/urdu.pdf',
        'urd', 3, 'Urdu'
    )

    # Spanish: has embedded text, chapter 1 at page 5
    print("\n=== Spanish Extraction (text) ===")
    es_pages = extract_pdf_text(
        '/home/vdamarl/pers/OmSaiRam/tmp/spanish.pdf',
        5, 'Spanish'
    )

    # French: has embedded text, chapter 1 at page 4
    print("\n=== French Extraction (text) ===")
    fr_pages = extract_pdf_text(
        '/home/vdamarl/pers/OmSaiRam/tmp/french.pdf',
        4, 'French'
    )

    # Deutsch: has embedded text with header on each page, content from page 2
    print("\n=== Deutsch Extraction (text) ===")
    de_pages = extract_pdf_text(
        '/home/vdamarl/pers/OmSaiRam/tmp/Deutsch.pdf',
        2, 'Deutsch',
        strip_header='Aus: Shri Sai Satcharita'
    )

    print("\n=== Building JSON files ===")

    ur_json = build_proportional_json(ur_pages, 'ur', 'باب', en_chapters)
    es_json = build_proportional_json(es_pages, 'es', 'Capítulo', en_chapters)
    fr_json = build_proportional_json(fr_pages, 'fr', 'Chapitre', en_chapters)
    de_json = build_proportional_json(de_pages, 'de', 'Kapitel', en_chapters)

    outputs = [
        ('Urdu', ur_json, '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_ur.json'),
        ('Spanish', es_json, '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_es.json'),
        ('French', fr_json, '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_fr.json'),
        ('Deutsch', de_json, '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_de.json'),
    ]

    for name, data, path in outputs:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    print("\n=== Summary ===")
    for name, data, path in outputs:
        filled = sum(1 for ch in data if ch['content'])
        sizes = [len(ch['content']) for ch in data]
        print(f"  {name}: {filled}/47 chapters")
        print(f"    Total chars: {sum(sizes):,}")
        print(f"    Sizes: min={min(sizes):,}, max={max(sizes):,}, avg={sum(sizes)//len(sizes):,}")
        print(f"    File: {path} ({os.path.getsize(path):,} bytes)")

    print("\nDONE!")


if __name__ == '__main__':
    main()
