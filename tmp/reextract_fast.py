#!/usr/bin/env python3
"""
Fast OCR re-extraction for badly corrupted language files.
Uses multiprocessing and optimized settings for speed.
"""

import fitz
import pytesseract
from PIL import Image, ImageEnhance
import io
import json
import re
import os
import sys
from multiprocessing import Pool, cpu_count

BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
PDF_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/source_pdfs')
OUTPUT_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/content')
CACHE_DIR = os.path.join(BASE_DIR, 'tmp/ocr_cache')
DPI = 250  # Balance of quality vs speed

LANG_CONFIG = {
    'te': {'tess': 'tel', 'start': 16, 'heading': 'అధ్యాయం', 'marker': r'అధ్యాయము|అధ్యాయం'},
    'bn': {'tess': 'ben', 'start': 10, 'heading': 'অধ্যায়', 'marker': r'অধ্যায়\s*[-–]?\s*[০-৯\d]+'},
    'gu': {'tess': 'guj', 'start': 8,  'heading': 'અધ્યાય', 'marker': r'અધ્યાય\s*[-–:]?\s*[૦-૯\d]+'},
    'pa': {'tess': 'pan', 'start': 8,  'heading': 'ਅਧਿਆਇ', 'marker': r'ਅਧਿਆਇ\s*[-–]?\s*[੦-੯\d]+'},
    'kn': {'tess': 'kan', 'start': 8,  'heading': 'ಅಧ್ಯಾಯ', 'marker': r'ಅಧ್ಯಾಯ\s*[-–:]?\s*[೦-೯\d]+'},
    'ta': {'tess': 'tam', 'start': 8,  'heading': 'அத்தியாயம்', 'marker': r'அத்தியாயம்\s*[-–:]?\s*[௦-௯\d]+'},
    'ml': {'tess': 'mal', 'start': 8,  'heading': 'അധ്യായം', 'marker': r'അധ്യായം\s*[-–:]?\s*[൦-൯\d]+'},
    'or': {'tess': 'ori', 'start': 8,  'heading': 'ଅଧ୍ୟାୟ', 'marker': r'ଅଧ୍ୟାୟ\s*[-–:]?\s*[୦-୯\d]+'},
    'ne': {'tess': 'nep', 'start': 8,  'heading': 'अध्याय', 'marker': r'अध्याय\s*[-–:]?\s*[०-९\d]+'},
    'sd': {'tess': 'snd', 'start': 10, 'heading': 'باب', 'marker': r'باب\s*[-–:]?\s*[\d٠-٩۰-۹]+'},
    'ur': {'tess': 'urd', 'start': 10, 'heading': 'باب', 'marker': r'باب\s*[-–:]?\s*[\d٠-٩۰-۹]+'},
}


def ocr_page(args):
    """OCR a single page."""
    pdf_path, page_idx, lang = args
    try:
        doc = fitz.open(pdf_path)
        page = doc[page_idx]
        pix = page.get_pixmap(dpi=DPI)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        # Convert to grayscale and enhance
        img = img.convert('L')
        img = ImageEnhance.Contrast(img).enhance(1.3)
        text = pytesseract.image_to_string(img, lang=lang)
        doc.close()
        return (page_idx, text.strip())
    except Exception as e:
        return (page_idx, "")


def extract_pages(lang_code):
    """Extract all pages for a language."""
    cfg = LANG_CONFIG[lang_code]
    pdf_path = os.path.join(PDF_DIR, f'satcharita_{lang_code}.pdf')
    cache_file = os.path.join(CACHE_DIR, f'{lang_code}_pages.json')
    
    # Use cache if available
    if os.path.exists(cache_file):
        print(f"  [{lang_code}] Loading from cache")
        with open(cache_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    doc = fitz.open(pdf_path)
    total = len(doc)
    doc.close()
    
    pages_range = list(range(cfg['start'], total))
    args = [(pdf_path, i, cfg['tess']) for i in pages_range]
    
    workers = min(cpu_count(), 8)
    print(f"  [{lang_code}] OCR: {len(pages_range)} pages, {workers} workers, {DPI} DPI")
    
    with Pool(workers) as pool:
        results = pool.map(ocr_page, args)
    
    results.sort(key=lambda x: x[0])
    pages = [text for _, text in results if text]
    
    # Cache
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(cache_file, 'w', encoding='utf-8') as f:
        json.dump(pages, f, ensure_ascii=False)
    
    print(f"  [{lang_code}] Done: {len(pages)} pages extracted")
    return pages


def split_chapters(pages, lang_code):
    """Split extracted pages into chapters."""
    cfg = LANG_CONFIG[lang_code]
    full_text = '\n\n'.join(pages)
    marker = cfg['marker']
    
    # Find all chapter markers
    matches = list(re.finditer(marker, full_text))
    print(f"  [{lang_code}] Found {len(matches)} chapter markers")
    
    # If we can't find markers with numbers, try just the word
    if len(matches) < 20:
        # Try broader pattern
        heading_word = cfg['heading']
        alt_matches = list(re.finditer(heading_word, full_text))
        print(f"  [{lang_code}] Alt pattern found {len(alt_matches)} markers")
        if len(alt_matches) > len(matches):
            matches = alt_matches
    
    if len(matches) < 5:
        # Fall back to page-based splitting (roughly 7 pages per chapter)
        print(f"  [{lang_code}] Using page-based splitting")
        chapters = []
        pages_per_chapter = max(1, len(pages) // 47)
        for i in range(0, len(pages), pages_per_chapter):
            chunk = '\n\n'.join(pages[i:i + pages_per_chapter])
            if chunk.strip():
                chapters.append(chunk.strip())
        return chapters[:47]
    
    # Split at chapter markers
    chapters = []
    for i in range(len(matches)):
        start = matches[i].start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(full_text)
        chapter_text = full_text[start:end].strip()
        if chapter_text:
            chapters.append(chapter_text)
    
    return chapters


def clean_text(text, lang_code):
    """Clean OCR artifacts."""
    # Remove page numbers on their own lines
    text = re.sub(r'^\s*\d{1,3}\s*$', '', text, flags=re.MULTILINE)
    # Remove excessive blank lines
    text = re.sub(r'\n{3,}', '\n\n', text)
    # Clean spaces
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    
    # Language-specific cleanup
    if lang_code == 'pa':
        # Remove forward slashes that are OCR artifacts
        text = re.sub(r'(?<=[\u0A00-\u0A7F])\s*/\s*(?=[\u0A00-\u0A7F])', '', text)
        text = re.sub(r'^\s*/\s*', '', text, flags=re.MULTILINE)
    
    return text.strip()


def get_title(content, max_len=150):
    """Extract title from chapter content."""
    lines = content.split('\n')
    parts = []
    for line in lines:
        line = line.strip()
        if not line or line.isdigit() or len(line) < 3:
            continue
        parts.append(line)
        if len(' '.join(parts)) > 60:
            break
    title = ' '.join(parts)
    return title[:max_len] if title else f"Chapter"


def build_output(chapters, lang_code):
    """Build JSON output."""
    cfg = LANG_CONFIG[lang_code]
    result = []
    for i, content in enumerate(chapters):
        content = clean_text(content, lang_code)
        num = i + 1
        result.append({
            "id": num,
            "number": num,
            "chapterLabel": str(num),
            "heading": f"{cfg['heading']} {num}",
            "title": get_title(content),
            "content": content,
            "language": lang_code,
            "version": 1
        })
    return result


def process_language(lang_code):
    """Full pipeline for one language."""
    print(f"\n{'='*50}")
    print(f"Processing: {lang_code} ({LANG_CONFIG[lang_code]['tess']})")
    print(f"{'='*50}")
    
    pdf_path = os.path.join(PDF_DIR, f'satcharita_{lang_code}.pdf')
    if not os.path.exists(pdf_path):
        print(f"  ERROR: PDF not found: {pdf_path}")
        return False
    
    # Step 1: OCR
    pages = extract_pages(lang_code)
    
    # Step 2: Split chapters
    chapters = split_chapters(pages, lang_code)
    print(f"  [{lang_code}] Chapters: {len(chapters)}")
    
    # Step 3: Build output
    output = build_output(chapters, lang_code)
    
    # Step 4: Write
    out_path = os.path.join(OUTPUT_DIR, f'satcharita_{lang_code}.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    print(f"  [{lang_code}] Written: {out_path} ({len(output)} chapters)")
    return True


def main():
    langs = sys.argv[1:] if len(sys.argv) > 1 else ['te', 'bn', 'gu', 'pa']
    
    print(f"Languages: {langs}")
    print(f"DPI: {DPI}, Workers: {min(cpu_count(), 8)}")
    os.makedirs(CACHE_DIR, exist_ok=True)
    
    for lang in langs:
        if lang not in LANG_CONFIG:
            print(f"Unknown: {lang}")
            continue
        try:
            process_language(lang)
        except Exception as e:
            print(f"  ERROR [{lang}]: {e}")
            import traceback
            traceback.print_exc()


if __name__ == '__main__':
    main()
