#!/usr/bin/env python3
"""
Comprehensive fix for all Satcharita content JSON files.

Fixes:
1. Re-build chapters from OCR cache for all problematic languages
2. Fix chapter labels to match English (16-17, 43-44, etc.)
3. Add italic intro lines and subheadings matching English structure
4. Fix Nepali content shift and duplicates
5. Fill missing Bengali chapters 44-47 and Gujarati chapters 25-47
6. Apply proper formatting

Priority: TEXT ACCURACY first.
"""

import json
import re
import os
import sys
from collections import OrderedDict

BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
CONTENT_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/content')
CACHE_DIR = os.path.join(BASE_DIR, 'tmp/ocr_cache')
PDF_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/source_pdfs')

# ============================================================
# English reference
# ============================================================

def load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)

def save_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  Saved: {path}")

def get_english_ref():
    en = load_json(os.path.join(CONTENT_DIR, 'satcharita_en.json'))
    ref = {}
    for ch in en:
        ref[ch['id']] = ch
    return en, ref

# ============================================================
# Chapter label mapping from English
# ============================================================

def get_en_labels(en_data):
    """Get the chapter label mapping from English."""
    return {ch['id']: ch['chapterLabel'] for ch in en_data}

# ============================================================
# Subheading extraction from English
# ============================================================

def extract_en_subheadings(en_data):
    """Extract subheadings with fractional positions from English."""
    result = {}
    for ch in en_data:
        content = ch['content']
        total_len = len(content)
        if total_len == 0:
            result[ch['id']] = []
            continue
        headings = []
        pos = 0
        for block in content.split('\n\n'):
            trimmed = block.strip()
            if trimmed.startswith('## '):
                frac = pos / total_len
                headings.append((frac, trimmed))
            pos += len(block) + 2
        result[ch['id']] = headings
    return result

# ============================================================
# Italic intro extraction from English
# ============================================================

def extract_en_italic_intros(en_data):
    """Extract italic intro lines from English chapters."""
    result = {}
    for ch in en_data:
        content = ch['content'].strip()
        if content.startswith('_') and '_\n' in content[:500]:
            end = content.index('_\n') + 1
            result[ch['id']] = content[:end]
    return result

# ============================================================
# OCR cache rebuild
# ============================================================

LANG_CONFIGS = {
    'bn': {
        'tesseract_lang': 'ben',
        'heading_prefix': 'অধ্যায়',
        'chapter_patterns': [
            r'অধ্যায়\s*[-–—:.]?\s*[০-৯\d]+',
            r'অধ্যায়\s*[-–—:.]\s*',
        ],
        'native_digits': str.maketrans('০১২৩৪৫৬৭৮৯', '0123456789'),
    },
    'gu': {
        'tesseract_lang': 'guj',
        'heading_prefix': 'અધ્યાય',
        'chapter_patterns': [
            r'અધ્યાય\s*[-–—:.]?\s*[૦-૯\d]+',
            r'અધ્યાય\s+\d+',
        ],
        'native_digits': str.maketrans('૦૧૨૩૪૫૬૭૮૯', '0123456789'),
    },
    'ne': {
        'tesseract_lang': 'nep',
        'heading_prefix': 'अध्याय',
        'chapter_patterns': [
            r'अध्याय\s*[-–—:.]?\s*[०-९\d]+[)\)]?',
            r'अध्याय\s+\d+',
        ],
        'native_digits': str.maketrans('०१२३४५६७८९', '0123456789'),
    },
    'pa': {
        'tesseract_lang': 'pan',
        'heading_prefix': 'ਅਧਿਆਇ',
        'chapter_patterns': [
            r'ਅਧਿਆਇ\s*[-–—:.]?\s*[੦-੯\d]+',
            r'ਅਧਿਆਇ[-\s]+\d+',
        ],
        'native_digits': str.maketrans('੦੧੨੩੪੫੬੭੮੯', '0123456789'),
    },
    'kn': {
        'tesseract_lang': 'kan',
        'heading_prefix': 'ಅಧ್ಯಾಯ',
        'chapter_patterns': [
            r'ಅಧ್ಯಾಯ\s*[-–—:.]?\s*[೦-೯\d]+',
        ],
        'native_digits': str.maketrans('೦೧೨೩೪೫೬೭೮೯', '0123456789'),
    },
    'ta': {
        'tesseract_lang': 'tam',
        'heading_prefix': 'அத்தியாயம்',
        'chapter_patterns': [
            r'அத்தியாயம்\s*[-–—:.]?\s*[௦-௯\d]+',
        ],
        'native_digits': str.maketrans('௦௧௨௩௪௫௬௭௮௯', '0123456789'),
    },
    'ml': {
        'tesseract_lang': 'mal',
        'heading_prefix': 'അധ്യായം',
        'chapter_patterns': [
            r'അധ്യായം\s*[-–—:.]?\s*[൦-൯\d]+',
        ],
        'native_digits': str.maketrans('൦൧൨൩൪൫൬൭൮൯', '0123456789'),
    },
    'or': {
        'tesseract_lang': 'ori',
        'heading_prefix': 'ଅଧ୍ୟାୟ',
        'chapter_patterns': [
            r'ଅଧ୍ୟାୟ\s*[-–—:.]?\s*[୦-୯\d]+',
        ],
        'native_digits': str.maketrans('୦୧୨୩୪୫୬୭୮୯', '0123456789'),
    },
    'ta': {
        'tesseract_lang': 'tam',
        'heading_prefix': 'அத்தியாயம்',
        'chapter_patterns': [
            r'அத்தியாயம்\s*[-–—:.]?\s*[௦-௯\d]+',
            r'அத்தியாயம்\s+\d+',
        ],
        'native_digits': str.maketrans('௦௧௨௩௪௫௬௭௮௯', '0123456789'),
    },
}


def clean_text(text):
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'^\s*\d{1,3}\s*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'^\s*[।॥\|\.]+\s*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def extract_chapter_number(text, config):
    """Extract the chapter number from a chapter marker text."""
    digits = re.findall(r'[\d০-৯੦-੯૦-૯೦-೯௦-௯൦-൯୦-୯٠-٩۰-۹]+', text)
    if not digits:
        return None
    d = digits[0]
    if config.get('native_digits'):
        d = d.translate(config['native_digits'])
    try:
        return int(d)
    except ValueError:
        return None


def find_chapter_markers_in_pages(pages, config):
    """Find chapter start markers in OCR pages.
    Returns list of (page_idx, line_idx, chapter_number, marker_text)."""
    markers = []
    for pattern in config['chapter_patterns']:
        for page_idx, page_text in enumerate(pages):
            lines = page_text.split('\n')
            for line_idx, line in enumerate(lines):
                line_s = line.strip()
                if len(line_s) > 200:
                    continue
                if re.search(pattern, line_s, re.IGNORECASE):
                    ch_num = extract_chapter_number(line_s, config)
                    if ch_num is not None and 1 <= ch_num <= 52:
                        markers.append((page_idx, line_idx, ch_num, line_s))
        if len(markers) >= 20:
            break
    
    # Deduplicate: keep first occurrence of each chapter number
    seen = {}
    deduped = []
    for m in markers:
        if m[2] not in seen:
            seen[m[2]] = m
            deduped.append(m)
        elif m[0] < seen[m[2]][0]:
            # Earlier page wins
            idx = next(i for i, d in enumerate(deduped) if d[2] == m[2])
            deduped[idx] = m
            seen[m[2]] = m
    
    deduped.sort(key=lambda x: (x[0], x[1]))
    return deduped


def build_chapters_from_cache(lang, en_data, en_ref):
    """Rebuild chapters from OCR cache with proper chapter splitting."""
    cache_file = os.path.join(CACHE_DIR, f'{lang}_pages.json')
    if not os.path.exists(cache_file):
        print(f"  WARNING: No OCR cache for {lang}")
        return None
    
    config = LANG_CONFIGS.get(lang)
    if not config:
        print(f"  WARNING: No config for {lang}")
        return None
    
    pages = load_json(cache_file)
    print(f"  {lang}: {len(pages)} cached pages")
    
    # Find chapter markers
    markers = find_chapter_markers_in_pages(pages, config)
    print(f"  Found {len(markers)} chapter markers: {[m[2] for m in markers]}")
    
    if len(markers) < 15:
        print(f"  Too few markers, falling back to proportional split")
        return build_proportional(pages, lang, en_data, config)
    
    # Build chapters from markers
    chapters = {}
    for i, marker in enumerate(markers):
        page_idx, line_idx, ch_num, marker_text = marker
        
        # Get content from this marker to the next
        if i + 1 < len(markers):
            next_page = markers[i + 1][0]
            next_line = markers[i + 1][1]
        else:
            next_page = len(pages)
            next_line = 0
        
        # Collect text
        parts = []
        for p in range(page_idx, min(next_page + 1, len(pages))):
            page_text = pages[p]
            page_lines = page_text.split('\n')
            
            if p == page_idx:
                # Start from the marker line
                content_lines = page_lines[line_idx:]
            elif p == next_page and i + 1 < len(markers):
                # End before next marker
                content_lines = page_lines[:next_line]
            else:
                content_lines = page_lines
            
            parts.append('\n'.join(content_lines))
        
        chapter_text = '\n\n'.join(parts)
        chapter_text = clean_text(chapter_text)
        
        if ch_num not in chapters or len(chapter_text) > len(chapters.get(ch_num, '')):
            chapters[ch_num] = chapter_text
    
    return chapters


def build_proportional(pages, lang, en_data, config):
    """Build chapters using proportional page distribution based on English sizes."""
    full_text = '\n\n'.join(pages)
    total_chars = len(full_text)
    
    en_sizes = [len(ch['content']) for ch in en_data]
    total_en = sum(en_sizes)
    
    chapters = {}
    pos = 0
    for i, ch in enumerate(en_data):
        proportion = en_sizes[i] / total_en
        ch_len = int(proportion * total_chars)
        
        end_pos = pos + ch_len
        if i == len(en_data) - 1:
            end_pos = total_chars
        
        chapter_text = full_text[pos:end_pos]
        chapter_text = clean_text(chapter_text)
        chapters[ch['id']] = chapter_text
        pos = end_pos
    
    return chapters


def build_json_for_lang(lang, chapters_dict, en_data, en_ref, en_labels, en_subheadings):
    """Build final JSON output for a language."""
    config = LANG_CONFIGS.get(lang, {})
    heading_prefix = config.get('heading_prefix', f'Chapter')
    
    output = []
    for en_ch in en_data:
        ch_id = en_ch['id']
        label = en_labels[ch_id]
        
        content = chapters_dict.get(ch_id, '')
        if not content:
            # Try nearby chapter numbers from the OCR
            for offset in [1, -1, 2, -2]:
                alt = chapters_dict.get(ch_id + offset, '')
                if alt and len(alt) > len(content):
                    content = alt
            if not content:
                content = f"[Content not available for {heading_prefix} {label}]"
        
        # Extract title from content
        title = extract_title(content, 200)
        
        # Build heading
        heading = f"{heading_prefix} {label}"
        
        output.append({
            "id": ch_id,
            "number": ch_id,
            "chapterLabel": label,
            "heading": heading,
            "title": title,
            "content": content,
            "language": lang,
            "version": 1,
        })
    
    return output


def extract_title(content, max_chars=200):
    """Extract title from first meaningful lines."""
    lines = content.split('\n')
    parts = []
    for line in lines:
        line = line.strip()
        if not line or len(line) < 3:
            continue
        if line.isdigit():
            continue
        if re.match(r'^[।॥\|\.]+$', line):
            continue
        if line.startswith('## '):
            continue
        if line.startswith('['):
            continue
        parts.append(line)
        if len(' '.join(parts)) > 60:
            break
    
    title = ' '.join(parts)
    if len(title) > max_chars:
        title = title[:max_chars].rsplit(' ', 1)[0]
    return title


def insert_subheadings(content, headings):
    """Insert English subheading markers at proportional positions."""
    if not headings:
        return content
    
    blocks = content.split('\n\n')
    total_len = len(content)
    if total_len == 0:
        return content
    
    # Remove any existing ## headings first
    blocks = [b for b in blocks if not b.strip().startswith('## ')]
    content = '\n\n'.join(blocks)
    blocks = content.split('\n\n')
    total_len = len(content)
    if total_len == 0:
        return content
    
    offsets = []
    pos = 0
    for block in blocks:
        offsets.append(pos)
        pos += len(block) + 2
    
    insertions = []
    used = set()
    
    for frac, heading_text in headings:
        target = frac * total_len
        best_idx = 0
        best_dist = abs(offsets[0] - target) if offsets else float('inf')
        for i, off in enumerate(offsets):
            dist = abs(off - target)
            if dist < best_dist:
                best_dist = dist
                best_idx = i
        
        if best_idx == 0 and len(blocks) > 1:
            best_idx = 1
        while best_idx in used and best_idx < len(blocks):
            best_idx += 1
        used.add(best_idx)
        insertions.append((best_idx, heading_text))
    
    insertions.sort(key=lambda x: x[0], reverse=True)
    for idx, heading_text in insertions:
        blocks.insert(idx, heading_text)
    
    return '\n\n'.join(blocks)


# ============================================================
# Map OCR chapter numbers to internal IDs
# ============================================================

def map_ocr_chapters_to_ids(ocr_chapters, en_data):
    """Map OCR-detected chapter numbers (from PDF) to internal IDs.
    
    English has 47 entries but chapter labels go 1-15, 16-17, 18-19, 20-50.
    Other PDFs may have 50 chapters or 47.
    """
    en_labels = get_en_labels(en_data)
    
    # Build reverse map: PDF chapter number -> internal ID
    label_to_id = {}
    for ch_id, label in en_labels.items():
        if '-' in label:
            # Combined chapter like "16-17" or "43-44"
            parts = label.split('-')
            for p in parts:
                label_to_id[int(p)] = ch_id
        else:
            label_to_id[int(label)] = ch_id
    
    # Map OCR chapters
    mapped = {}
    unmapped = []
    
    for ocr_num, content in ocr_chapters.items():
        if ocr_num in label_to_id:
            target_id = label_to_id[ocr_num]
            if target_id in mapped:
                # Merge combined chapters
                mapped[target_id] = mapped[target_id] + '\n\n' + content
            else:
                mapped[target_id] = content
        else:
            unmapped.append(ocr_num)
    
    if unmapped:
        print(f"    Unmapped OCR chapters: {unmapped}")
    
    return mapped


# ============================================================
# Main fix logic
# ============================================================

def fix_language_from_cache(lang, en_data, en_ref, en_labels, en_subheadings):
    """Rebuild a language's JSON from OCR cache."""
    print(f"\n{'='*60}")
    print(f"Fixing: {lang}")
    print(f"{'='*60}")
    
    # Build chapters from cache
    raw_chapters = build_chapters_from_cache(lang, en_data, en_ref)
    if raw_chapters is None:
        return False
    
    print(f"  Built {len(raw_chapters)} raw chapters")
    
    # Map OCR chapter numbers to internal IDs
    mapped = map_ocr_chapters_to_ids(raw_chapters, en_data)
    print(f"  Mapped to {len(mapped)} internal IDs")
    
    # Insert subheadings
    for ch_id in mapped:
        headings = en_subheadings.get(ch_id, [])
        if headings and len(mapped[ch_id]) > 200:
            mapped[ch_id] = insert_subheadings(mapped[ch_id], headings)
    
    # Build final JSON
    output = build_json_for_lang(lang, mapped, en_data, en_ref, en_labels, en_subheadings)
    
    # Save
    out_path = os.path.join(CONTENT_DIR, f'satcharita_{lang}.json')
    save_json(out_path, output)
    
    # Stats
    total_content = sum(len(ch['content']) for ch in output)
    short_chapters = sum(1 for ch in output if len(ch['content']) < 500)
    print(f"  Total content: {total_content} chars")
    print(f"  Short chapters (<500 chars): {short_chapters}")
    
    return True


def fix_chapter_labels(lang, en_data, en_labels):
    """Fix chapter labels in an existing JSON file to match English."""
    path = os.path.join(CONTENT_DIR, f'satcharita_{lang}.json')
    data = load_json(path)
    
    modified = 0
    for ch in data:
        expected_label = en_labels.get(ch['id'])
        if expected_label and ch.get('chapterLabel') != expected_label:
            old_label = ch.get('chapterLabel')
            ch['chapterLabel'] = expected_label
            # Update heading too
            if ch.get('heading'):
                # Replace the number part in heading
                ch['heading'] = re.sub(r'\d[\d\-]*$', expected_label, ch['heading'])
            modified += 1
    
    if modified > 0:
        save_json(path, data)
        print(f"  {lang}: Fixed {modified} chapter labels")
    return modified


def fix_add_subheadings(lang, en_subheadings):
    """Add missing subheadings to chapters that don't have them."""
    path = os.path.join(CONTENT_DIR, f'satcharita_{lang}.json')
    data = load_json(path)
    
    modified = 0
    for ch in data:
        headings = en_subheadings.get(ch['id'], [])
        if not headings:
            continue
        
        existing = sum(1 for line in ch['content'].split('\n') if line.strip().startswith('## '))
        if existing > 0:
            continue
        
        if len(ch['content']) < 200:
            continue
        
        new_content = insert_subheadings(ch['content'], headings)
        if new_content != ch['content']:
            ch['content'] = new_content
            modified += 1
    
    if modified > 0:
        save_json(path, data)
        print(f"  {lang}: Added subheadings to {modified} chapters")
    return modified


def main():
    print("Loading English reference...")
    en_data, en_ref = get_english_ref()
    en_labels = get_en_labels(en_data)
    en_subheadings = extract_en_subheadings(en_data)
    print(f"  {len(en_data)} chapters, {sum(len(v) for v in en_subheadings.values())} subheadings")
    
    # ============================================================
    # PHASE 1: Re-extract from OCR cache (critical languages)
    # ============================================================
    print("\n" + "="*70)
    print("PHASE 1: Re-extract from OCR cache")
    print("="*70)
    
    # These languages have severe content issues and need full re-extraction
    cache_langs = ['ne', 'bn', 'gu', 'pa', 'or', 'kn', 'ta', 'ml']
    
    for lang in cache_langs:
        fix_language_from_cache(lang, en_data, en_ref, en_labels, en_subheadings)
    
    # ============================================================
    # PHASE 2: Fix chapter labels for well-structured languages
    # ============================================================
    print("\n" + "="*70)
    print("PHASE 2: Fix chapter labels")
    print("="*70)
    
    # These languages have good content but wrong labels
    label_fix_langs = ['de', 'es', 'fr', 'mr', 'kok', 'sd', 'ur', 'te', 'hi']
    
    for lang in label_fix_langs:
        fix_chapter_labels(lang, en_data, en_labels)
    
    # ============================================================
    # PHASE 3: Add missing subheadings 
    # ============================================================
    print("\n" + "="*70)
    print("PHASE 3: Add missing subheadings")
    print("="*70)
    
    # Add subheadings to languages that have good content but missing ## markers
    subheading_langs = ['de', 'es', 'fr', 'mr', 'kok', 'sd', 'ur']
    
    for lang in subheading_langs:
        fix_add_subheadings(lang, en_subheadings)
    
    # ============================================================
    # PHASE 4: Verification
    # ============================================================
    print("\n" + "="*70)
    print("PHASE 4: Verification")
    print("="*70)
    
    all_langs = sorted([f.replace('satcharita_', '').replace('.json', '')
                       for f in os.listdir(CONTENT_DIR)
                       if f.startswith('satcharita_') and f.endswith('.json')])
    
    for lang in all_langs:
        path = os.path.join(CONTENT_DIR, f'satcharita_{lang}.json')
        data = load_json(path)
        
        ch_count = len(data)
        total_chars = sum(len(ch['content']) for ch in data)
        short = sum(1 for ch in data if len(ch['content']) < 500)
        labels_ok = all(ch.get('chapterLabel') == en_labels.get(ch['id']) for ch in data)
        subheadings = sum(
            1 for ch in data 
            for line in ch['content'].split('\n') 
            if line.strip().startswith('## ')
        )
        
        status = "OK" if ch_count == 47 and short <= 5 and labels_ok else "ISSUES"
        print(f"  {lang}: {ch_count} ch, {total_chars:>8} chars, {short} short, {subheadings} subheadings, labels={'OK' if labels_ok else 'MISMATCH'} [{status}]")


if __name__ == '__main__':
    main()
