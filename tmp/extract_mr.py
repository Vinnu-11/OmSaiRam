#!/usr/bin/env python3
"""Extract Marathi Sai Satcharita from scanned PDF via OCR."""

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


def extract_pdf(pdf_path, lang, content_start, label):
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

    print("=== Marathi Extraction ===")
    mr_pages = extract_pdf(
        '/home/vdamarl/pers/OmSaiRam/tmp/marathi',
        'mar', 4, 'Marathi'
    )

    print("\n=== Building JSON ===")
    mr_json = build_proportional_json(mr_pages, 'mr', 'अध्याय', en_chapters)

    mr_out = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_mr.json'
    with open(mr_out, 'w', encoding='utf-8') as f:
        json.dump(mr_json, f, ensure_ascii=False, indent=2)

    print("\n=== Summary ===")
    filled = sum(1 for ch in mr_json if ch['content'])
    sizes = [len(ch['content']) for ch in mr_json]
    print(f"  Marathi: {filled}/47 chapters")
    print(f"    Total chars: {sum(sizes):,}")
    print(f"    Sizes: min={min(sizes):,}, max={max(sizes):,}, avg={sum(sizes)//len(sizes):,}")
    print(f"    File: {mr_out} ({os.path.getsize(mr_out):,} bytes)")
    print("\nDONE!")


if __name__ == '__main__':
    main()
