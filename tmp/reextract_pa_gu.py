#!/usr/bin/env python3
"""Re-extract Punjabi and Gujarati Sai Satcharita with better OCR settings."""

import fitz
import pytesseract
from PIL import Image
import io
import json
import re
import os
from multiprocessing import Pool, cpu_count

DPI = 300
EN_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'


def ocr_page(args):
    """OCR a single page at high DPI."""
    pdf_path, page_idx, lang = args
    try:
        doc = fitz.open(pdf_path)
        page = doc[page_idx]
        pix = page.get_pixmap(dpi=DPI)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        text = pytesseract.image_to_string(img, lang=lang, config='--psm 6 --oem 1')
        doc.close()
        return (page_idx, text.strip())
    except Exception as e:
        return (page_idx, "")


def extract_all_pages(pdf_path, lang, content_start, label):
    """Extract all pages using OCR with multiprocessing."""
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    doc.close()

    pages_to_process = list(range(content_start, total_pages))
    args_list = [(pdf_path, i, lang) for i in pages_to_process]

    num_workers = min(cpu_count(), 8)
    print(f"  {label}: OCR {len(pages_to_process)} pages with {num_workers} workers at {DPI} DPI...")

    with Pool(num_workers) as pool:
        results = pool.map(ocr_page, args_list)

    results.sort(key=lambda x: x[0])
    pages = [(idx, text) for idx, text in results if text]
    print(f"  {label}: {len(pages)} non-empty pages extracted")
    return pages


def find_chapters_punjabi(pages):
    """Find Punjabi chapter boundaries."""
    full_text = '\n\n'.join(text for _, text in pages)
    
    # Punjabi chapter pattern: ਅਧਿਆਇ-N or || ਅਧਿਆਇ-N ||
    patterns = [
        r'[|॥]\s*ਅਧਿਆਇ\s*[-–]\s*(\d+)\s*[|॥]',
        r'ਅਧਿਆਇ\s*[-–]\s*(\d+)',
        r'ਅਧਿਆ\w*\s*[-–:]\s*(\d+)',
    ]
    
    for pattern in patterns:
        matches = list(re.finditer(pattern, full_text))
        if len(matches) >= 30:
            print(f"  Punjabi: Found {len(matches)} chapters with pattern: {pattern}")
            break
    else:
        # Fallback - try even more flexible pattern
        pattern = r'ਅਧਿ\w+\s*[-–]?\s*(\d+)'
        matches = list(re.finditer(pattern, full_text))
        print(f"  Punjabi: Fallback found {len(matches)} chapters")
    
    if not matches:
        return None, full_text
    
    chapters = []
    for idx in range(len(matches)):
        start = matches[idx].start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(full_text)
        chapter_text = full_text[start:end].strip()
        chapters.append(chapter_text)
    
    return chapters, full_text


def find_chapters_gujarati(pages):
    """Find Gujarati chapter boundaries."""
    full_text = '\n\n'.join(text for _, text in pages)
    
    # Gujarati chapter pattern: અધ્યાય N or variations
    patterns = [
        r'અધ્યાય\s*[-–]?\s*[૦-૯\d]+',
        r'અધ્ય\w*\s*[-–]?\s*[૦-૯\d]+',
    ]
    
    for pattern in patterns:
        matches = list(re.finditer(pattern, full_text))
        if len(matches) >= 30:
            print(f"  Gujarati: Found {len(matches)} chapters with pattern: {pattern}")
            break
    else:
        # More flexible
        pattern = r'અધ્ય\w*\s*\d+'
        matches = list(re.finditer(pattern, full_text))
        print(f"  Gujarati: Flexible found {len(matches)} chapters")
    
    if not matches:
        return None, full_text
    
    chapters = []
    for idx in range(len(matches)):
        start = matches[idx].start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(full_text)
        chapter_text = full_text[start:end].strip()
        chapters.append(chapter_text)
    
    return chapters, full_text


def clean_text(text):
    """Clean extracted text."""
    lines = text.split('\n')
    cleaned = []
    prev_empty = False
    for line in lines:
        line = line.strip()
        if not line:
            if not prev_empty:
                cleaned.append('')
            prev_empty = True
        else:
            # Remove page numbers on their own line
            if re.match(r'^\d{1,3}$', line):
                continue
            cleaned.append(line)
            prev_empty = False
    result = '\n'.join(cleaned).strip()
    return re.sub(r'\n{3,}', '\n\n', result)


def get_title(chapter_text):
    """Extract title from chapter text."""
    lines = chapter_text.split('\n')
    # Skip the chapter header line
    for line in lines[1:5]:
        line = line.strip()
        if line and len(line) > 10 and not re.match(r'^[\d\s\-–—()|॥]+$', line):
            return line[:200]
    return lines[0][:200] if lines else ""


def build_json(chapters, lang_code, heading_prefix, en_chapters):
    """Build 47-chapter JSON from extracted chapters."""
    num_target = 47
    json_output = []
    
    if chapters and len(chapters) >= num_target:
        # Use first 47 chapters, combine extras into last
        for i in range(num_target):
            ch_text = chapters[i] if i < len(chapters) else ""
            content = clean_text(ch_text)
            title = get_title(ch_text) if ch_text else en_chapters[i]['title']
            
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
        
        # Append extra chapters to last
        if len(chapters) > num_target:
            extra = '\n\n'.join(clean_text(ch) for ch in chapters[num_target:])
            json_output[-1]['content'] += '\n\n' + extra
    
    elif chapters:
        # Fewer than 47 - use what we have
        for i in range(num_target):
            if i < len(chapters):
                content = clean_text(chapters[i])
                title = get_title(chapters[i])
            else:
                content = ""
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
    else:
        # No chapters found - proportional split
        all_text = '\n\n'.join(text for _, text in pages)
        # Split proportionally based on English chapter sizes
        en_sizes = [len(ch['content']) for ch in en_chapters]
        total_en = sum(en_sizes)
        total_text = len(all_text)
        
        pos = 0
        for i in range(num_target):
            proportion = en_sizes[i] / total_en
            chunk_size = int(proportion * total_text)
            content = clean_text(all_text[pos:pos + chunk_size])
            pos += chunk_size
            
            json_output.append({
                "id": i + 1,
                "number": i + 1,
                "chapterLabel": str(i + 1),
                "heading": f"{heading_prefix} {i + 1}",
                "title": en_chapters[i]['title'],
                "content": content,
                "language": lang_code,
                "version": 1
            })
    
    return json_output


def main():
    with open(EN_PATH, 'r', encoding='utf-8') as f:
        en_chapters = json.load(f)
    
    pdf_base = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/source_pdfs'
    out_base = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content'
    
    # === PUNJABI ===
    print("=" * 60)
    print("=== Punjabi Re-extraction ===")
    pa_pages = extract_all_pages(
        f'{pdf_base}/satcharita_pa.pdf', 'pan', 8, 'Punjabi'
    )
    pa_chapters, pa_full = find_chapters_punjabi(pa_pages)
    if pa_chapters:
        print(f"  Punjabi: {len(pa_chapters)} chapters found")
    else:
        print(f"  Punjabi: No chapter markers found, using proportional split")
    
    pa_json = build_json(pa_chapters, 'pa', 'ਅਧਿਆਇ', en_chapters)
    pa_out = f'{out_base}/satcharita_pa.json'
    with open(pa_out, 'w', encoding='utf-8') as f:
        json.dump(pa_json, f, ensure_ascii=False, indent=2)
    
    filled = sum(1 for ch in pa_json if ch['content'])
    sizes = [len(ch['content']) for ch in pa_json]
    print(f"  Punjabi: {filled}/47 chapters, total {sum(sizes):,} chars")
    print(f"  Written: {pa_out}")
    
    # === GUJARATI ===
    print("\n" + "=" * 60)
    print("=== Gujarati Re-extraction ===")
    gu_pages = extract_all_pages(
        f'{pdf_base}/satcharita_gu.pdf', 'guj', 26, 'Gujarati'
    )
    gu_chapters, gu_full = find_chapters_gujarati(gu_pages)
    if gu_chapters:
        print(f"  Gujarati: {len(gu_chapters)} chapters found")
    else:
        print(f"  Gujarati: No chapter markers found, using proportional split")
    
    gu_json = build_json(gu_chapters, 'gu', 'અધ્યાય', en_chapters)
    gu_out = f'{out_base}/satcharita_gu.json'
    with open(gu_out, 'w', encoding='utf-8') as f:
        json.dump(gu_json, f, ensure_ascii=False, indent=2)
    
    filled = sum(1 for ch in gu_json if ch['content'])
    sizes = [len(ch['content']) for ch in gu_json]
    print(f"  Gujarati: {filled}/47 chapters, total {sum(sizes):,} chars")
    print(f"  Written: {gu_out}")


if __name__ == '__main__':
    main()
