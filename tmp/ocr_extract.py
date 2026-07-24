#!/usr/bin/env python3
"""
Efficient OCR extraction using subprocess-based parallelism.
Processes pages in batches and writes progress.
"""

import fitz
import pytesseract
from PIL import Image, ImageEnhance
import io
import json
import re
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
PDF_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/source_pdfs')
OUTPUT_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/content')
CACHE_DIR = os.path.join(BASE_DIR, 'tmp/ocr_cache')

LANG_CONFIG = {
    'te': {'tess': 'tel', 'start': 16, 'heading': 'అధ్యాయం', 'marker': r'అధ్యాయము'},
    'bn': {'tess': 'ben', 'start': 10, 'heading': 'অধ্যায়', 'marker': r'অধ্যায়'},
    'gu': {'tess': 'guj', 'start': 8,  'heading': 'અધ્યાય', 'marker': r'અધ્યાય'},
    'pa': {'tess': 'pan', 'start': 8,  'heading': 'ਅਧਿਆਇ', 'marker': r'ਅਧਿਆਇ'},
    'kn': {'tess': 'kan', 'start': 8,  'heading': 'ಅಧ್ಯಾಯ', 'marker': r'ಅಧ್ಯಾಯ'},
    'ta': {'tess': 'tam', 'start': 8,  'heading': 'அத்தியாயம்', 'marker': r'அத்தியாயம்'},
    'ml': {'tess': 'mal', 'start': 8,  'heading': 'അധ്യായം', 'marker': r'അധ്യായം'},
    'or': {'tess': 'ori', 'start': 8,  'heading': 'ଅଧ୍ୟାୟ', 'marker': r'ଅଧ୍ୟାୟ'},
    'ne': {'tess': 'nep', 'start': 8,  'heading': 'अध्याय', 'marker': r'अध्याय'},
    'sd': {'tess': 'snd', 'start': 10, 'heading': 'باب', 'marker': r'باب'},
    'ur': {'tess': 'urd', 'start': 10, 'heading': 'باب', 'marker': r'باب'},
}

DPI = 200  # Good balance of speed and quality


def ocr_page(pdf_path, page_idx, lang):
    """OCR a single page."""
    doc = fitz.open(pdf_path)
    page = doc[page_idx]
    pix = page.get_pixmap(dpi=DPI)
    img = Image.open(io.BytesIO(pix.tobytes("png")))
    img = img.convert('L')
    img = ImageEnhance.Contrast(img).enhance(1.3)
    text = pytesseract.image_to_string(img, lang=lang, config='--psm 6')
    doc.close()
    return text.strip()


def ocr_page_wrapper(args):
    """Wrapper for multiprocessing."""
    pdf_path, page_idx, lang = args
    try:
        return (page_idx, ocr_page(pdf_path, page_idx, lang))
    except Exception as e:
        return (page_idx, f"[ERROR: {e}]")


def extract_with_progress(lang_code):
    """Extract all pages with progress reporting."""
    cfg = LANG_CONFIG[lang_code]
    pdf_path = os.path.join(PDF_DIR, f'satcharita_{lang_code}.pdf')
    cache_file = os.path.join(CACHE_DIR, f'{lang_code}_pages.json')
    
    os.makedirs(CACHE_DIR, exist_ok=True)
    
    # Use cache
    if os.path.exists(cache_file):
        print(f"  Loading from cache: {cache_file}")
        with open(cache_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    doc = fitz.open(pdf_path)
    total = len(doc)
    doc.close()
    
    page_range = list(range(cfg['start'], total))
    n_pages = len(page_range)
    args = [(pdf_path, i, cfg['tess']) for i in page_range]
    
    workers = 4  # Use 4 workers for better stability
    print(f"  OCR: {n_pages} pages, {workers} workers, {DPI} DPI")
    
    results = {}
    start_time = time.time()
    
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(ocr_page_wrapper, a): a[1] for a in args}
        done_count = 0
        for future in as_completed(futures):
            page_idx, text = future.result()
            results[page_idx] = text
            done_count += 1
            if done_count % 50 == 0 or done_count == n_pages:
                elapsed = time.time() - start_time
                rate = done_count / elapsed
                remaining = (n_pages - done_count) / rate if rate > 0 else 0
                print(f"  Progress: {done_count}/{n_pages} ({done_count*100//n_pages}%) "
                      f"- {rate:.1f} pages/sec - ETA: {remaining:.0f}s")
    
    # Sort by page index
    pages = [results[i] for i in sorted(results.keys())]
    
    # Cache
    with open(cache_file, 'w', encoding='utf-8') as f:
        json.dump(pages, f, ensure_ascii=False)
    
    print(f"  Done: {len(pages)} pages in {time.time()-start_time:.1f}s")
    return pages


def split_into_chapters(pages, lang_code, expected=47):
    """Split pages into chapters based on markers."""
    cfg = LANG_CONFIG[lang_code]
    full_text = '\n\n'.join(pages)
    marker = cfg['marker']
    
    # Find markers
    matches = list(re.finditer(marker, full_text))
    print(f"  Chapter markers found: {len(matches)}")
    
    if len(matches) >= expected - 5:
        # Good - split at markers
        # Take only first 'expected' markers to avoid duplicates
        if len(matches) > expected + 10:
            # Too many matches - might be catching non-chapter mentions
            # Filter to only markers at start of lines
            line_start_matches = [m for m in matches 
                                  if m.start() == 0 or full_text[m.start()-1] == '\n']
            if len(line_start_matches) >= expected - 5:
                matches = line_start_matches
                print(f"  Filtered to line-start markers: {len(matches)}")
        
        chapters = []
        for i in range(min(len(matches), expected)):
            start = matches[i].start()
            end = matches[i+1].start() if i+1 < len(matches) else len(full_text)
            chapters.append(full_text[start:end].strip())
        return chapters
    
    elif len(matches) >= 20:
        # Partial - use what we have
        chapters = []
        for i in range(len(matches)):
            start = matches[i].start()
            end = matches[i+1].start() if i+1 < len(matches) else len(full_text)
            chapters.append(full_text[start:end].strip())
        return chapters
    
    else:
        # Too few markers - use page-based splitting
        print(f"  Using page-based splitting ({n_per_ch} pages/chapter)")
        n_per_ch = max(1, len(pages) // expected)
        chapters = []
        for i in range(0, len(pages), n_per_ch):
            chunk = '\n\n'.join(pages[i:i+n_per_ch])
            if chunk.strip():
                chapters.append(chunk.strip())
        return chapters[:expected]


def clean_content(text, lang_code):
    """Clean OCR artifacts."""
    # Remove standalone page numbers
    text = re.sub(r'^\s*\d{1,3}\s*$', '', text, flags=re.MULTILINE)
    # Remove excessive whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    
    if lang_code == 'pa':
        # Fix Punjabi forward-slash OCR artifacts
        text = re.sub(r'\s*/\s*', ' ', text)
    
    return text.strip()


def get_title(content, max_len=150):
    """Get title from first meaningful lines."""
    lines = content.split('\n')
    parts = []
    for line in lines:
        line = line.strip()
        if not line or len(line) < 3 or line.isdigit():
            continue
        # Skip lines that are just the chapter marker
        if re.match(r'^\d+\s*(వ|st|nd|rd|th)?\s*అధ్యాయము$', line):
            continue
        parts.append(line)
        if len(' '.join(parts)) > 60:
            break
    title = ' '.join(parts)
    return title[:max_len] if title else "Chapter"


def process_language(lang_code):
    """Process one language end-to-end."""
    cfg = LANG_CONFIG[lang_code]
    print(f"\n{'='*50}")
    print(f"  Language: {lang_code} ({cfg['tess']})")
    print(f"{'='*50}")
    
    pdf_path = os.path.join(PDF_DIR, f'satcharita_{lang_code}.pdf')
    if not os.path.exists(pdf_path):
        print(f"  ERROR: PDF not found")
        return False
    
    # OCR
    pages = extract_with_progress(lang_code)
    
    # Split chapters
    chapters = split_into_chapters(pages, lang_code)
    print(f"  Chapters: {len(chapters)}")
    
    # Build JSON
    output = []
    for i, content in enumerate(chapters):
        content = clean_content(content, lang_code)
        num = i + 1
        output.append({
            "id": num,
            "number": num,
            "chapterLabel": str(num),
            "heading": f"{cfg['heading']} {num}",
            "title": get_title(content),
            "content": content,
            "language": lang_code,
            "version": 1
        })
    
    # Write
    out_path = os.path.join(OUTPUT_DIR, f'satcharita_{lang_code}.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    print(f"  Output: {out_path} ({len(output)} chapters)")
    
    # Show first chapter title
    if output:
        print(f"  Ch.1 title: {output[0]['title'][:80]}")
    
    return True


def main():
    langs = sys.argv[1:] if len(sys.argv) > 1 else ['te', 'bn', 'gu']
    print(f"Processing: {langs}")
    
    for lang in langs:
        if lang not in LANG_CONFIG:
            print(f"Unknown language: {lang}")
            continue
        try:
            process_language(lang)
        except Exception as e:
            print(f"ERROR [{lang}]: {e}")
            import traceback
            traceback.print_exc()


if __name__ == '__main__':
    main()
