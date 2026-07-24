#!/usr/bin/env python3
"""Extract Bengali and Gujarati Sai Satcharita from scanned PDFs via OCR."""

import fitz
import pytesseract
from PIL import Image
import io
import json
import re
import sys
import os

def ocr_page(doc, page_idx, lang, dpi=250):
    """OCR a single page and return text."""
    page = doc[page_idx]
    pix = page.get_pixmap(dpi=dpi)
    img = Image.open(io.BytesIO(pix.tobytes("png")))
    text = pytesseract.image_to_string(img, lang=lang)
    return text.strip()


def extract_bengali():
    """Extract Bengali Sai Satcharita chapters."""
    print("=== Starting Bengali PDF extraction ===")
    pdf_path = '/home/vdamarl/pers/OmSaiRam/tmp/bengal.pdf'
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    print(f"Total pages: {total_pages}")

    # Bengali content starts around page 11 (0-indexed 10)
    # Chapter marker pattern: অধ্যায় - ১, অধ্যায় - ২, etc.
    # Also may appear as: অধ্যায়-১ or অধ্যায় ১

    all_text = []
    content_start = 10  # 0-indexed page where content begins

    for i in range(content_start, total_pages):
        text = ocr_page(doc, i, 'ben')
        all_text.append(text)
        if (i - content_start + 1) % 20 == 0:
            print(f"  Bengali: processed {i - content_start + 1}/{total_pages - content_start} pages")

    print(f"  Bengali: OCR complete, {len(all_text)} pages extracted")

    # Join all text
    full_text = '\n\n'.join(all_text)

    # Save raw text for debugging
    with open('/home/vdamarl/pers/OmSaiRam/tmp/bengali_raw.txt', 'w', encoding='utf-8') as f:
        f.write(full_text)

    # Split by chapter markers
    # Bengali chapter pattern: অধ্যায় - ১ or অধ্যায়-১ or অধ্যায় ১
    # Bengali numerals: ০১২৩৪৫৬৭৮৯
    chapter_pattern = r'অধ্যায়\s*[-–—]?\s*[০-৯১২৩৪৫৬৭৮৯\d]+'

    # Find all chapter markers
    splits = list(re.finditer(chapter_pattern, full_text))
    print(f"  Bengali: found {len(splits)} chapter markers")

    if len(splits) < 40:
        # Try alternate pattern
        alt_pattern = r'অধ্যা[য়য]\s*[-–—]?\s*[০-৯\d]+'
        splits = list(re.finditer(alt_pattern, full_text))
        print(f"  Bengali: alternate pattern found {len(splits)} markers")

    if len(splits) < 40:
        # Try even more flexible pattern
        alt_pattern2 = r'অধ্যা\w*\s*[-–—:]\s*[০-৯\d]+'
        splits = list(re.finditer(alt_pattern2, full_text))
        print(f"  Bengali: flexible pattern found {len(splits)} markers")

    # Extract chapter content
    chapters = []
    for idx in range(len(splits)):
        start = splits[idx].start()
        end = splits[idx + 1].start() if idx + 1 < len(splits) else len(full_text)
        chapter_text = full_text[start:end].strip()
        chapters.append(chapter_text)

    print(f"  Bengali: extracted {len(chapters)} chapters")
    return chapters


def extract_gujarati():
    """Extract Gujarati Sai Satcharita chapters."""
    print("=== Starting Gujarati PDF extraction ===")
    pdf_path = '/home/vdamarl/pers/OmSaiRam/tmp/gujarathi.pdf'
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    print(f"Total pages: {total_pages}")

    # Gujarati content starts around page 26 (0-indexed 25)
    # Chapter marker pattern: અધ્યાય ૧, અધ્યાય ૨, etc.
    # Gujarati numerals: ૦૧૨૩૪૫૬૭૮૯

    all_text = []
    content_start = 25  # 0-indexed page where chapter content begins

    for i in range(content_start, total_pages):
        text = ocr_page(doc, i, 'guj')
        all_text.append(text)
        if (i - content_start + 1) % 20 == 0:
            print(f"  Gujarati: processed {i - content_start + 1}/{total_pages - content_start} pages")

    print(f"  Gujarati: OCR complete, {len(all_text)} pages extracted")

    # Join all text
    full_text = '\n\n'.join(all_text)

    # Save raw text for debugging
    with open('/home/vdamarl/pers/OmSaiRam/tmp/gujarati_raw.txt', 'w', encoding='utf-8') as f:
        f.write(full_text)

    # Split by chapter markers
    chapter_pattern = r'અધ્યાય\s*[૦-૯\d]+'

    splits = list(re.finditer(chapter_pattern, full_text))
    print(f"  Gujarati: found {len(splits)} chapter markers")

    if len(splits) < 40:
        # Try alternate - the OCR might split the word
        alt_pattern = r'અધ્યાય\s*[-–—]?\s*[૦-૯\d]+'
        splits = list(re.finditer(alt_pattern, full_text))
        print(f"  Gujarati: alternate found {len(splits)} markers")

    # Extract chapter content
    chapters = []
    for idx in range(len(splits)):
        start = splits[idx].start()
        end = splits[idx + 1].start() if idx + 1 < len(splits) else len(full_text)
        chapter_text = full_text[start:end].strip()
        chapters.append(chapter_text)

    print(f"  Gujarati: extracted {len(chapters)} chapters")
    return chapters


def bengali_num_to_int(s):
    """Convert Bengali numeral string to integer."""
    bn_digits = '০১২৩৪৫৬৭৮৯'
    result = ''
    for ch in s:
        if ch in bn_digits:
            result += str(bn_digits.index(ch))
        elif ch.isdigit():
            result += ch
    return int(result) if result else 0


def gujarati_num_to_int(s):
    """Convert Gujarati numeral string to integer."""
    gu_digits = '૦૧૨૩૪૫૬૭૮૯'
    result = ''
    for ch in s:
        if ch in gu_digits:
            result += str(gu_digits.index(ch))
        elif ch.isdigit():
            result += ch
    return int(result) if result else 0


def clean_chapter_text(text):
    """Clean up OCR artifacts in chapter text."""
    # Remove excessive whitespace but keep paragraph breaks
    lines = text.split('\n')
    cleaned_lines = []
    for line in lines:
        line = line.strip()
        if line:
            cleaned_lines.append(line)
        elif cleaned_lines and cleaned_lines[-1] != '':
            cleaned_lines.append('')

    # Join with newlines, collapse multiple blank lines
    result = '\n'.join(cleaned_lines)
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result.strip()


def build_json(chapters, lang_code, lang_name, heading_prefix, chapter_marker_pattern, num_converter):
    """Build the JSON structure for a language."""
    # Reference English chapter titles for mapping
    en_path = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'
    with open(en_path, 'r', encoding='utf-8') as f:
        en_chapters = json.load(f)

    json_chapters = []

    # We need exactly 47 chapters to match the app structure
    # If we have more or fewer, we need to handle that

    for i in range(min(len(chapters), 47)):
        chapter_text = chapters[i]

        # Extract heading from the first line
        lines = chapter_text.split('\n')
        heading_line = lines[0] if lines else ''

        # Try to extract chapter number from heading
        num_match = re.search(r'[০-৯૦-૯\d]+', heading_line)
        chapter_num = i + 1  # Default sequential

        # Get title - use first few meaningful lines after heading
        title_lines = []
        for line in lines[1:4]:
            line = line.strip()
            if line and len(line) > 5:
                title_lines.append(line)
                break
        title = title_lines[0] if title_lines else en_chapters[i]['title'] if i < len(en_chapters) else f'{heading_prefix} {i+1}'

        # Clean the content (skip the heading line)
        content_text = '\n'.join(lines[1:]) if len(lines) > 1 else chapter_text
        content_text = clean_chapter_text(content_text)

        chapter_obj = {
            "id": i + 1,
            "number": i + 1,
            "chapterLabel": str(i + 1),
            "heading": f"{heading_prefix} {i + 1}",
            "title": title,
            "content": content_text,
            "language": lang_code,
            "version": 1
        }
        json_chapters.append(chapter_obj)

    # If we have fewer than 47 chapters, pad with empty ones (shouldn't happen ideally)
    while len(json_chapters) < 47:
        idx = len(json_chapters)
        json_chapters.append({
            "id": idx + 1,
            "number": idx + 1,
            "chapterLabel": str(idx + 1),
            "heading": f"{heading_prefix} {idx + 1}",
            "title": en_chapters[idx]['title'] if idx < len(en_chapters) else "",
            "content": "",
            "language": lang_code,
            "version": 1
        })

    return json_chapters[:47]  # Ensure exactly 47


def main():
    # Extract Bengali
    bn_chapters = extract_bengali()

    # Extract Gujarati
    gu_chapters = extract_gujarati()

    # Build JSON for Bengali
    print("\n=== Building Bengali JSON ===")
    bn_json = build_json(
        bn_chapters, 'bn', 'বাংলা', 'অধ্যায়',
        r'অধ্যায়\s*[-–—]?\s*([০-৯\d]+)',
        bengali_num_to_int
    )

    bn_output = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_bn.json'
    with open(bn_output, 'w', encoding='utf-8') as f:
        json.dump(bn_json, f, ensure_ascii=False, indent=2)
    print(f"  Written: {bn_output} ({len(bn_json)} chapters)")

    # Build JSON for Gujarati
    print("\n=== Building Gujarati JSON ===")
    gu_json = build_json(
        gu_chapters, 'gu', 'ગુજરાતી', 'અધ્યાય',
        r'અધ્યાય\s*[-–—]?\s*([૦-૯\d]+)',
        gujarati_num_to_int
    )

    gu_output = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_gu.json'
    with open(gu_output, 'w', encoding='utf-8') as f:
        json.dump(gu_json, f, ensure_ascii=False, indent=2)
    print(f"  Written: {gu_output} ({len(gu_json)} chapters)")

    print("\n=== DONE ===")


if __name__ == '__main__':
    main()
