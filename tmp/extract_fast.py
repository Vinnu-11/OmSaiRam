#!/usr/bin/env python3
"""Fast OCR extraction of Bengali and Gujarati Sai Satcharita using multiprocessing."""

import fitz
import pytesseract
from PIL import Image
import io
import json
import re
import os
from multiprocessing import Pool, cpu_count
from functools import partial

DPI = 200  # Lower DPI for speed

def ocr_single_page(args):
    """OCR a single page. Args: (pdf_path, page_idx, lang)"""
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
        return (page_idx, f"ERROR: {e}")


def extract_pdf(pdf_path, lang, content_start, label):
    """Extract all text from a PDF using multiprocessing."""
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    doc.close()

    pages_to_process = list(range(content_start, total_pages))
    args_list = [(pdf_path, i, lang) for i in pages_to_process]

    num_workers = min(cpu_count(), 8)
    print(f"  {label}: Processing {len(pages_to_process)} pages with {num_workers} workers...")

    with Pool(num_workers) as pool:
        results = pool.map(ocr_single_page, args_list)

    # Sort by page index and extract text
    results.sort(key=lambda x: x[0])
    texts = [text for _, text in results]

    print(f"  {label}: OCR complete")
    return texts


def find_chapters_bengali(pages_text):
    """Find chapter boundaries in Bengali text."""
    full_text = '\n\n'.join(pages_text)

    # Bengali chapter pattern: অধ্যায় - ১ (or variations)
    # Bengali digits: ০১২৩৪৫৬৭৮৯
    patterns = [
        r'অধ্যায়\s*[-–—:]\s*[০-৯\d]+',
        r'অধ্যায়\s+[০-৯\d]+',
        r'অধ্যা\w*\s*[-–—]\s*[০-৯\d]+',
    ]

    for pattern in patterns:
        splits = list(re.finditer(pattern, full_text))
        if len(splits) >= 40:
            print(f"  Bengali: found {len(splits)} chapters with pattern: {pattern}")
            break
    else:
        # If regex fails, try page-by-page detection
        print(f"  Bengali: regex found only {len(splits)} markers, trying page-by-page...")
        splits = list(re.finditer(patterns[0], full_text))
        if len(splits) < 10:
            splits = list(re.finditer(r'অধ্যায়', full_text))
            print(f"  Bengali: basic 'অধ্যায়' found {len(splits)} times")

    # Extract chapters
    chapters = []
    for idx in range(len(splits)):
        start = splits[idx].start()
        end = splits[idx + 1].start() if idx + 1 < len(splits) else len(full_text)
        chapter_text = full_text[start:end].strip()
        chapters.append(chapter_text)

    return chapters, full_text


def find_chapters_gujarati(pages_text):
    """Find chapter boundaries in Gujarati text."""
    full_text = '\n\n'.join(pages_text)

    # Gujarati chapter pattern: અધ્યાય ૧ (or variations)
    # Gujarati digits: ૦૧૨૩૪૫૬૭૮૯
    patterns = [
        r'અધ્યાય\s*[૦-૯\d]+',
        r'અધ્યાય\s*[-–—]?\s*[૦-૯\d]+',
    ]

    for pattern in patterns:
        splits = list(re.finditer(pattern, full_text))
        if len(splits) >= 40:
            print(f"  Gujarati: found {len(splits)} chapters with pattern: {pattern}")
            break
    else:
        print(f"  Gujarati: regex found {len(splits)} markers")
        if len(splits) < 10:
            splits = list(re.finditer(r'અધ્યાય', full_text))
            print(f"  Gujarati: basic 'અધ્યાય' found {len(splits)} times")

    # Extract chapters
    chapters = []
    for idx in range(len(splits)):
        start = splits[idx].start()
        end = splits[idx + 1].start() if idx + 1 < len(splits) else len(full_text)
        chapter_text = full_text[start:end].strip()
        chapters.append(chapter_text)

    return chapters, full_text


def clean_text(text):
    """Clean OCR artifacts."""
    lines = text.split('\n')
    cleaned = []
    for line in lines:
        line = line.strip()
        if line:
            cleaned.append(line)
        elif cleaned and cleaned[-1] != '':
            cleaned.append('')
    result = '\n'.join(cleaned)
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result.strip()


def get_chapter_title(chapter_text, max_lines=3):
    """Extract a title from the beginning of chapter text."""
    lines = chapter_text.split('\n')
    # Skip the chapter header line
    title_candidates = []
    for line in lines[1:max_lines+1]:
        line = line.strip()
        if line and len(line) > 3 and not re.match(r'^[\d০-৯૦-૯\s\-–—]+$', line):
            title_candidates.append(line)
    if title_candidates:
        return title_candidates[0][:200]
    return ""


def build_json_output(chapters, lang_code, heading_prefix):
    """Build final JSON array."""
    # Load English for reference titles (fallback)
    en_path = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'
    with open(en_path, 'r', encoding='utf-8') as f:
        en_chapters = json.load(f)

    output = []
    num_chapters = min(len(chapters), 47)

    for i in range(num_chapters):
        chapter_text = chapters[i]
        lines = chapter_text.split('\n')

        # Get title from content
        title = get_chapter_title(chapter_text)
        if not title and i < len(en_chapters):
            title = en_chapters[i]['title']

        # Content is everything after the heading line
        content = '\n'.join(lines[1:]) if len(lines) > 1 else chapter_text
        content = clean_text(content)

        # Add end marker if the content has it (like English "Bow to Shri Sai")
        output.append({
            "id": i + 1,
            "number": i + 1,
            "chapterLabel": str(i + 1),
            "heading": f"{heading_prefix} {i + 1}",
            "title": title,
            "content": content,
            "language": lang_code,
            "version": 1
        })

    # Pad to 47 if needed
    while len(output) < 47:
        idx = len(output)
        en_title = en_chapters[idx]['title'] if idx < len(en_chapters) else ""
        output.append({
            "id": idx + 1,
            "number": idx + 1,
            "chapterLabel": str(idx + 1),
            "heading": f"{heading_prefix} {idx + 1}",
            "title": en_title,
            "content": "",
            "language": lang_code,
            "version": 1
        })

    return output[:47]


def main():
    bn_pdf = '/home/vdamarl/pers/OmSaiRam/tmp/bengal.pdf'
    gu_pdf = '/home/vdamarl/pers/OmSaiRam/tmp/gujarathi.pdf'

    # Extract Bengali (content starts at page 11, 0-indexed 10)
    print("=== Bengali Extraction ===")
    bn_pages = extract_pdf(bn_pdf, 'ben', 10, 'Bengali')

    # Save raw for debug
    with open('/home/vdamarl/pers/OmSaiRam/tmp/bengali_raw.txt', 'w', encoding='utf-8') as f:
        f.write('\n\n--- PAGE BREAK ---\n\n'.join(bn_pages))

    # Find chapters
    bn_chapters, _ = find_chapters_bengali(bn_pages)
    print(f"  Bengali: {len(bn_chapters)} chapters found")

    # Extract Gujarati (content starts at page 26, 0-indexed 25)
    print("\n=== Gujarati Extraction ===")
    gu_pages = extract_pdf(gu_pdf, 'guj', 25, 'Gujarati')

    with open('/home/vdamarl/pers/OmSaiRam/tmp/gujarati_raw.txt', 'w', encoding='utf-8') as f:
        f.write('\n\n--- PAGE BREAK ---\n\n'.join(gu_pages))

    gu_chapters, _ = find_chapters_gujarati(gu_pages)
    print(f"  Gujarati: {len(gu_chapters)} chapters found")

    # Build JSON
    print("\n=== Building JSON files ===")
    bn_json = build_json_output(bn_chapters, 'bn', 'অধ্যায়')
    gu_json = build_json_output(gu_chapters, 'gu', 'અધ્યાય')

    bn_out = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_bn.json'
    gu_out = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_gu.json'

    with open(bn_out, 'w', encoding='utf-8') as f:
        json.dump(bn_json, f, ensure_ascii=False, indent=2)
    print(f"  Written: {bn_out}")

    with open(gu_out, 'w', encoding='utf-8') as f:
        json.dump(gu_json, f, ensure_ascii=False, indent=2)
    print(f"  Written: {gu_out}")

    # Summary
    print("\n=== Summary ===")
    bn_sizes = [len(ch['content']) for ch in bn_json]
    gu_sizes = [len(ch['content']) for ch in gu_json]
    print(f"  Bengali: {sum(1 for s in bn_sizes if s > 0)}/47 chapters with content")
    print(f"  Bengali total chars: {sum(bn_sizes)}")
    print(f"  Gujarati: {sum(1 for s in gu_sizes if s > 0)}/47 chapters with content")
    print(f"  Gujarati total chars: {sum(gu_sizes)}")
    print("\nDONE!")


if __name__ == '__main__':
    main()
