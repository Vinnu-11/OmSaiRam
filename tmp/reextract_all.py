#!/usr/bin/env python3
"""
Re-extract Sai Satcharita from source PDFs using OCR for all languages
with corrupted/garbled text in the current JSON files.

Languages to re-extract:
- Telugu (tel) - excellent OCR quality
- Bengali (ben) - good OCR quality
- Gujarati (guj) - excellent OCR quality
- Punjabi (pan) - decent OCR quality
- Kannada (kan) - improve existing
- Tamil (tam) - improve existing
- Malayalam (mal) - improve existing
- Odia (ori) - improve existing
- Nepali (nep) - improve existing
- Sindhi (snd) - attempt
- Urdu (urd) - attempt
"""

import fitz
import pytesseract
from PIL import Image, ImageFilter, ImageEnhance
import io
import json
import re
import os
import sys
from multiprocessing import Pool, cpu_count
from functools import partial

# Configuration
BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
PDF_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/source_pdfs')
OUTPUT_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/content')
CACHE_DIR = os.path.join(BASE_DIR, 'tmp/ocr_cache')
DPI = 300

# Language configurations
LANGUAGES = {
    'te': {
        'tesseract_lang': 'tel',
        'pdf': 'satcharita_te.pdf',
        'output': 'satcharita_te.json',
        'content_start': 16,  # 0-indexed page where content begins
        'chapter_pattern': r'(?:మొదటి|రెండవ|మూడవ|నాలుగవ|ఐదవ|ఆరవ|ఏడవ|ఎనిమిదవ|తొమ్మిదవ|పదవ|పదకొండవ|పన్నెండవ|పదమూడవ|పదునాలుగవ|పదిహేనవ|పదహారవ|పదిహేడవ|పదునెనిమిదవ|పందొమ్మిదవ|ఇరవయ్యవ|ఇరవై\s*ఒకటవ|ఇరవై\s*రెండవ|ఇరవై\s*మూడవ|ఇరవై\s*నాలుగవ|ఇరవై\s*ఐదవ|ఇరవై\s*ఆరవ|ఇరవై\s*ఏడవ|ఇరవై\s*ఎనిమిదవ|ఇరవై\s*తొమ్మిదవ|ముప్పయ్యవ|ముప్పై\s*ఒకటవ|ముప్పై\s*రెండవ|ముప్పై\s*మూడవ|ముప్పై\s*నాలుగవ|ముప్పై\s*ఐదవ|ముప్పై\s*ఆరవ|ముప్పై\s*ఏడవ|ముప్పై\s*ఎనిమిదవ|ముప్పై\s*తొమ్మిదవ|నలభయ్యవ|నలభై\s*ఒకటవ|నలభై\s*రెండవ|నలభై\s*మూడవ|నలభై\s*నాలుగవ|నలభై\s*ఐదవ|నలభై\s*ఆరవ|నలభై\s*ఏడవ|\d+\s*వ)\s*అధ్యాయము',
        'heading_prefix': 'అధ్యాయం',
        'alt_chapter_pattern': r'అధ్యాయము',
    },
    'bn': {
        'tesseract_lang': 'ben',
        'pdf': 'satcharita_bn.pdf',
        'output': 'satcharita_bn.json',
        'content_start': 10,
        'chapter_pattern': r'অধ্যায়\s*[-–—:.]?\s*[০-৯\d]+',
        'heading_prefix': 'অধ্যায়',
        'alt_chapter_pattern': r'অধ্যায়',
    },
    'gu': {
        'tesseract_lang': 'guj',
        'pdf': 'satcharita_gu.pdf',
        'output': 'satcharita_gu.json',
        'content_start': 8,
        'chapter_pattern': r'અધ્યાય\s*[-–—:.]?\s*[૦-૯\d]+',
        'heading_prefix': 'અધ્યાય',
        'alt_chapter_pattern': r'અધ્યાય',
    },
    'pa': {
        'tesseract_lang': 'pan',
        'pdf': 'satcharita_pa.pdf',
        'output': 'satcharita_pa.json',
        'content_start': 8,
        'chapter_pattern': r'ਅਧਿਆਇ\s*[-–—:.]?\s*[੦-੯\d]+',
        'heading_prefix': 'ਅਧਿਆਇ',
        'alt_chapter_pattern': r'ਅਧਿਆਇ',
    },
    'kn': {
        'tesseract_lang': 'kan',
        'pdf': 'satcharita_kn.pdf',
        'output': 'satcharita_kn.json',
        'content_start': 8,
        'chapter_pattern': r'ಅಧ್ಯಾಯ\s*[-–—:.]?\s*[೦-೯\d]+',
        'heading_prefix': 'ಅಧ್ಯಾಯ',
        'alt_chapter_pattern': r'ಅಧ್ಯಾಯ',
    },
    'ta': {
        'tesseract_lang': 'tam',
        'pdf': 'satcharita_ta.pdf',
        'output': 'satcharita_ta.json',
        'content_start': 8,
        'chapter_pattern': r'அத்தியாயம்\s*[-–—:.]?\s*[௦-௯\d]+',
        'heading_prefix': 'அத்தியாயம்',
        'alt_chapter_pattern': r'அத்தியாயம்',
    },
    'ml': {
        'tesseract_lang': 'mal',
        'pdf': 'satcharita_ml.pdf',
        'output': 'satcharita_ml.json',
        'content_start': 8,
        'chapter_pattern': r'അധ്യായം\s*[-–—:.]?\s*[൦-൯\d]+',
        'heading_prefix': 'അധ്യായം',
        'alt_chapter_pattern': r'അധ്യായം',
    },
    'or': {
        'tesseract_lang': 'ori',
        'pdf': 'satcharita_or.pdf',
        'output': 'satcharita_or.json',
        'content_start': 8,
        'chapter_pattern': r'ଅଧ୍ୟାୟ\s*[-–—:.]?\s*[୦-୯\d]+',
        'heading_prefix': 'ଅଧ୍ୟାୟ',
        'alt_chapter_pattern': r'ଅଧ୍ୟାୟ',
    },
    'ne': {
        'tesseract_lang': 'nep',
        'pdf': 'satcharita_ne.pdf',
        'output': 'satcharita_ne.json',
        'content_start': 8,
        'chapter_pattern': r'अध्याय\s*[-–—:.]?\s*[०-९\d]+',
        'heading_prefix': 'अध्याय',
        'alt_chapter_pattern': r'अध्याय',
    },
    'sd': {
        'tesseract_lang': 'snd',
        'pdf': 'satcharita_sd.pdf',
        'output': 'satcharita_sd.json',
        'content_start': 10,
        'chapter_pattern': r'باب\s*[-–—:.]?\s*[\d٠-٩۰-۹]+',
        'heading_prefix': 'باب',
        'alt_chapter_pattern': r'باب',
    },
    'ur': {
        'tesseract_lang': 'urd',
        'pdf': 'satcharita_ur.pdf',
        'output': 'satcharita_ur.json',
        'content_start': 10,
        'chapter_pattern': r'باب\s*[-–—:.]?\s*[\d٠-٩۰-۹]+',
        'heading_prefix': 'باب',
        'alt_chapter_pattern': r'باب',
    },
}


def preprocess_image(img):
    """Preprocess image for better OCR accuracy."""
    # Convert to grayscale
    img = img.convert('L')
    # Enhance contrast
    enhancer = ImageEnhance.Contrast(img)
    img = enhancer.enhance(1.5)
    # Sharpen
    img = img.filter(ImageFilter.SHARPEN)
    return img


def ocr_single_page(args):
    """OCR a single page. Args: (pdf_path, page_idx, lang, dpi)"""
    pdf_path, page_idx, lang, dpi = args
    try:
        doc = fitz.open(pdf_path)
        page = doc[page_idx]
        pix = page.get_pixmap(dpi=dpi)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        img = preprocess_image(img)
        text = pytesseract.image_to_string(img, lang=lang)
        doc.close()
        return (page_idx, text.strip())
    except Exception as e:
        return (page_idx, f"ERROR on page {page_idx}: {e}")


def extract_all_pages(pdf_path, lang, content_start, label):
    """Extract all text from a PDF using multiprocessing OCR."""
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    doc.close()

    # Check cache
    cache_file = os.path.join(CACHE_DIR, f'{label}_pages.json')
    if os.path.exists(cache_file):
        print(f"  {label}: Loading from cache...")
        with open(cache_file, 'r', encoding='utf-8') as f:
            return json.load(f)

    pages_to_process = list(range(content_start, total_pages))
    args_list = [(pdf_path, i, lang, DPI) for i in pages_to_process]

    num_workers = min(cpu_count(), 8)
    print(f"  {label}: Processing {len(pages_to_process)} pages with {num_workers} workers at {DPI} DPI...")

    with Pool(num_workers) as pool:
        results = pool.map(ocr_single_page, args_list)

    # Sort by page index and extract text
    results.sort(key=lambda x: x[0])
    pages = [text for _, text in results]

    # Cache results
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(cache_file, 'w', encoding='utf-8') as f:
        json.dump(pages, f, ensure_ascii=False)

    print(f"  {label}: OCR complete, {len(pages)} pages extracted")
    return pages


def clean_text(text):
    """Clean OCR artifacts from text."""
    # Remove isolated single characters that are likely noise
    # Remove excessive whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    # Remove lines that are just page numbers
    text = re.sub(r'^\s*\d{1,3}\s*$', '', text, flags=re.MULTILINE)
    # Remove lines that are just punctuation
    text = re.sub(r'^\s*[।॥\|\.]+\s*$', '', text, flags=re.MULTILINE)
    # Clean up extra spaces
    text = re.sub(r'[ \t]+', ' ', text)
    # Clean up line breaks
    text = re.sub(r' *\n *', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def clean_punjabi_text(text):
    """Remove forward slashes that are OCR artifacts in Punjabi."""
    # Remove / that appear at word boundaries (OCR artifact)
    text = re.sub(r'(?<=\s)/(?=\S)', '', text)
    text = re.sub(r'(?<=\S)/(?=\s)', '', text)
    text = re.sub(r'(?<=\s)/(?=\s)', '', text)
    # Also remove isolated /
    text = re.sub(r'\s+/\s+', ' ', text)
    return text


def find_chapters(full_text, config, expected_chapters=47):
    """Find chapter boundaries using language-specific patterns."""
    chapter_pattern = config['chapter_pattern']
    alt_pattern = config.get('alt_chapter_pattern', '')

    # Try primary pattern
    matches = list(re.finditer(chapter_pattern, full_text, re.IGNORECASE))

    if len(matches) < 30 and alt_pattern:
        # Try alternate pattern
        matches = list(re.finditer(alt_pattern, full_text, re.IGNORECASE))
        print(f"    Using alt pattern, found {len(matches)} markers")

    if len(matches) < 10:
        print(f"    WARNING: Only found {len(matches)} chapter markers!")
        return None

    print(f"    Found {len(matches)} chapter markers")

    # Extract chapters
    chapters = []
    for idx in range(len(matches)):
        match = matches[idx]
        content_start = match.start()

        if idx + 1 < len(matches):
            content_end = matches[idx + 1].start()
        else:
            content_end = len(full_text)

        content = full_text[content_start:content_end].strip()
        chapters.append(content)

    return chapters


def split_by_page_patterns(pages, config, expected_chapters=47):
    """Alternative: split pages into chapters by detecting chapter headers."""
    chapter_pattern = config.get('alt_chapter_pattern', config['chapter_pattern'])
    
    chapter_pages = []  # List of (start_page_idx, text_of_chapter_header)
    
    for i, page_text in enumerate(pages):
        if re.search(chapter_pattern, page_text, re.IGNORECASE):
            # Check if this is near the start of the page (likely a chapter start)
            lines = page_text.split('\n')
            for j, line in enumerate(lines[:10]):  # Check first 10 lines
                if re.search(chapter_pattern, line, re.IGNORECASE):
                    chapter_pages.append((i, j))
                    break
    
    return chapter_pages


def extract_title_from_content(content, max_chars=200):
    """Extract a title from the first meaningful lines of chapter content."""
    lines = content.split('\n')
    title_parts = []
    
    for line in lines:
        line = line.strip()
        # Skip empty lines, page numbers, and very short lines
        if not line or len(line) < 3:
            continue
        if line.isdigit():
            continue
        if re.match(r'^[।॥\|\.]+$', line):
            continue
        title_parts.append(line)
        if len(' '.join(title_parts)) > 60:
            break
    
    title = ' '.join(title_parts)
    if len(title) > max_chars:
        title = title[:max_chars].rsplit(' ', 1)[0]
    return title


def build_json_output(chapters, lang_code, config):
    """Build the final JSON output structure."""
    heading_prefix = config['heading_prefix']
    
    output = []
    for idx, content in enumerate(chapters):
        chapter_num = idx + 1
        
        # Clean the content
        content = clean_text(content)
        if lang_code == 'pa':
            content = clean_punjabi_text(content)
        
        # Extract title from first lines
        title = extract_title_from_content(content)
        
        output.append({
            "id": chapter_num,
            "number": chapter_num,
            "chapterLabel": str(chapter_num),
            "heading": f"{heading_prefix} {chapter_num}",
            "title": title,
            "content": content,
            "language": lang_code,
            "version": 1
        })
    
    return output


def process_language(lang_code):
    """Process a single language: OCR -> split chapters -> output JSON."""
    config = LANGUAGES[lang_code]
    pdf_path = os.path.join(PDF_DIR, config['pdf'])
    output_path = os.path.join(OUTPUT_DIR, config['output'])
    
    if not os.path.exists(pdf_path):
        print(f"  ERROR: PDF not found: {pdf_path}")
        return False
    
    print(f"\n{'='*60}")
    print(f"Processing: {lang_code} ({config['tesseract_lang']})")
    print(f"{'='*60}")
    
    # Step 1: OCR all pages
    pages = extract_all_pages(
        pdf_path, 
        config['tesseract_lang'],
        config['content_start'],
        lang_code
    )
    
    # Step 2: Join all pages
    full_text = '\n\n'.join(pages)
    
    # Step 3: Find chapters
    chapters = find_chapters(full_text, config)
    
    if chapters is None or len(chapters) < 10:
        # Try page-by-page approach
        print(f"  Trying page-by-page chapter detection...")
        chapter_starts = split_by_page_patterns(pages, config)
        print(f"  Found {len(chapter_starts)} chapter starts by page")
        
        if len(chapter_starts) >= 10:
            chapters = []
            for i in range(len(chapter_starts)):
                start_page, start_line = chapter_starts[i]
                if i + 1 < len(chapter_starts):
                    end_page = chapter_starts[i + 1][0]
                    chapter_text = '\n\n'.join(pages[start_page:end_page])
                else:
                    chapter_text = '\n\n'.join(pages[start_page:])
                chapters.append(chapter_text)
    
    if chapters is None or len(chapters) < 5:
        print(f"  ERROR: Could not split into chapters for {lang_code}")
        # Fall back: save all text as single chapter for manual review
        chapters = [full_text]
    
    print(f"  Split into {len(chapters)} chapters")
    
    # Step 4: Build JSON output
    output = build_json_output(chapters, lang_code, config)
    
    # Step 5: Write output
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    print(f"  Written to: {output_path}")
    print(f"  Chapters: {len(output)}")
    return True


def main():
    """Main entry point."""
    # Priority languages (best OCR quality)
    priority_langs = ['te', 'bn', 'gu']
    # Secondary languages
    secondary_langs = ['pa', 'kn', 'ta', 'ml', 'or', 'ne']
    # Difficult languages (poor OCR quality - attempt anyway)
    difficult_langs = ['sd', 'ur']
    
    # Parse command line
    if len(sys.argv) > 1:
        langs_to_process = sys.argv[1:]
    else:
        langs_to_process = priority_langs + secondary_langs + difficult_langs
    
    print(f"Languages to process: {langs_to_process}")
    print(f"DPI: {DPI}")
    print(f"Workers: {min(cpu_count(), 8)}")
    
    os.makedirs(CACHE_DIR, exist_ok=True)
    
    results = {}
    for lang in langs_to_process:
        if lang not in LANGUAGES:
            print(f"  Unknown language: {lang}")
            continue
        try:
            success = process_language(lang)
            results[lang] = success
        except Exception as e:
            print(f"  ERROR processing {lang}: {e}")
            import traceback
            traceback.print_exc()
            results[lang] = False
    
    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    for lang, success in results.items():
        status = "✓ SUCCESS" if success else "✗ FAILED"
        print(f"  {lang}: {status}")


if __name__ == '__main__':
    main()
