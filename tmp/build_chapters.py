#!/usr/bin/env python3
"""
Rebuild chapter JSON from OCR cache with proper splitting.
Handles combined chapters, missing headings, and OCR noise.
"""

import json
import re
import os
import sys

BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
CACHE_DIR = os.path.join(BASE_DIR, 'tmp/ocr_cache')
OUTPUT_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/content')

# Bengali digits
BN_DIGITS = '০১২৩৪৫৬৭৮৯'

def bn_to_int(s):
    """Convert Bengali number string to integer."""
    result = ''
    for c in s:
        if c in BN_DIGITS:
            result += str(BN_DIGITS.index(c))
        elif c.isdigit():
            result += c
    return int(result) if result else 0

# Gujarati digits
GU_DIGITS = '૦૧૨૩૪૫૬૭૮૯'

def gu_to_int(s):
    result = ''
    for c in s:
        if c in GU_DIGITS:
            result += str(GU_DIGITS.index(c))
        elif c.isdigit():
            result += c
    return int(result) if result else 0


def clean_content(text):
    """Clean OCR artifacts from content."""
    # Remove standalone page numbers
    text = re.sub(r'^\s*\d{1,3}\s*$', '', text, flags=re.MULTILINE)
    # Remove leading/trailing decorative chars
    text = re.sub(r'^[|\s্‌.]+', '', text)
    text = re.sub(r'[|\s্‌.]+$', '', text)
    # Remove excessive whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    return text.strip()


def get_title(content, lang, max_len=150):
    """Get meaningful title from content."""
    lines = content.split('\n')
    parts = []
    for line in lines:
        line = line.strip()
        if not line or len(line) < 5 or line.isdigit():
            continue
        # Skip lines that are just numbers/decorations
        if re.match(r'^[\d\s|্‌.]+$', line):
            continue
        parts.append(line)
        if len(' | '.join(parts)) > 60:
            break
    title = ' | '.join(parts[:2])
    return title[:max_len] if title else "Chapter"


def build_bengali():
    """Build Bengali chapters from OCR cache."""
    cache_file = os.path.join(CACHE_DIR, 'bn_pages.json')
    with open(cache_file, 'r', encoding='utf-8') as f:
        pages = json.load(f)
    
    full_text = '\n\n'.join(pages)
    
    # Find chapter headings: অধ্যায় - N (with possible noise)
    pattern = r'^[|\s্‌0-9.]*অধ্যায়\s*[-–]\s*[০-৯0-9]+'
    matches = list(re.finditer(pattern, full_text, re.MULTILINE))
    
    print(f"  Found {len(matches)} chapter markers")
    
    # Build chapter sections
    sections = []
    
    # Chapter 1: from beginning to first marker
    if matches and matches[0].start() > 500:
        sections.append({
            'start': 0,
            'end': matches[0].start(),
            'label': '1'
        })
    
    # Remaining chapters from markers
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i+1].start() if i+1 < len(matches) else len(full_text)
        # Extract chapter number from heading
        num_match = re.search(r'[০-৯0-9]+', m.group())
        if num_match:
            label = str(bn_to_int(num_match.group()))
        else:
            label = str(i + 2)
        sections.append({
            'start': start,
            'end': end,
            'label': label
        })
    
    print(f"  Total sections: {len(sections)}")
    
    # Build JSON output
    output = []
    for i, sec in enumerate(sections):
        content = full_text[sec['start']:sec['end']]
        content = clean_content(content)
        if len(content) < 100:
            continue
        num = i + 1
        output.append({
            "id": num,
            "number": num,
            "chapterLabel": str(num),
            "heading": f"অধ্যায় {num}",
            "title": get_title(content, 'bn'),
            "content": content,
            "language": "bn",
            "version": 1
        })
    
    return output


def build_gujarati():
    """Build Gujarati chapters from OCR cache."""
    cache_file = os.path.join(CACHE_DIR, 'gu_pages.json')
    with open(cache_file, 'r', encoding='utf-8') as f:
        pages = json.load(f)
    
    full_text = '\n\n'.join(pages)
    
    # Gujarati chapter headings: અધ્યાય N or અધ્યાય - N at line start
    # The word અધ્યાય appears 205 times but only 47 at line start
    pattern = r'^[|\s૦-૯0-9.]*અધ્યાય\s*[-–]?\s*[૦-૯0-9]+'
    matches = list(re.finditer(pattern, full_text, re.MULTILINE))
    
    print(f"  Found {len(matches)} chapter markers at line start")
    
    # If too many, filter more strictly
    if len(matches) > 55:
        # Require the heading to be on a short line (actual headers are short)
        strict = []
        for m in matches:
            line_end = full_text.find('\n', m.start())
            if line_end == -1:
                line_end = len(full_text)
            line = full_text[m.start():line_end]
            if len(line.strip()) < 40:  # Chapter headers are short
                strict.append(m)
        if len(strict) >= 40:
            matches = strict
            print(f"  Filtered to short-line markers: {len(matches)}")
    
    sections = []
    
    # Chapter 1: from beginning to first marker
    if matches and matches[0].start() > 500:
        sections.append({
            'start': 0,
            'end': matches[0].start(),
            'label': '1'
        })
    
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i+1].start() if i+1 < len(matches) else len(full_text)
        num_match = re.search(r'[૦-૯0-9]+', m.group())
        if num_match:
            label = str(gu_to_int(num_match.group()))
        else:
            label = str(i + 2)
        sections.append({
            'start': start,
            'end': end,
            'label': label
        })
    
    print(f"  Total sections: {len(sections)}")
    
    output = []
    for i, sec in enumerate(sections):
        content = full_text[sec['start']:sec['end']]
        content = clean_content(content)
        if len(content) < 100:
            continue
        num = i + 1
        output.append({
            "id": num,
            "number": num,
            "chapterLabel": str(num),
            "heading": f"અધ્યાય {num}",
            "title": get_title(content, 'gu'),
            "content": content,
            "language": "gu",
            "version": 1
        })
    
    return output


def build_generic(lang_code, tess_lang, heading_word, marker_pattern=None):
    """Generic chapter builder for languages with simple heading patterns."""
    cache_file = os.path.join(CACHE_DIR, f'{lang_code}_pages.json')
    if not os.path.exists(cache_file):
        print(f"  No cache file for {lang_code}")
        return None
    
    with open(cache_file, 'r', encoding='utf-8') as f:
        pages = json.load(f)
    
    full_text = '\n\n'.join(pages)
    
    if marker_pattern:
        pattern = marker_pattern
    else:
        pattern = rf'^.*{heading_word}\s*[-–]?\s*[0-9]+'
    
    matches = list(re.finditer(pattern, full_text, re.MULTILINE))
    print(f"  Found {len(matches)} chapter markers")
    
    # Filter to line-start if too many
    if len(matches) > 55:
        line_start = [m for m in matches if m.start() == 0 or full_text[m.start()-1] == '\n']
        if len(line_start) >= 35:
            matches = line_start
            print(f"  Filtered to line-start: {len(matches)}")
    
    if len(matches) > 55:
        short_line = []
        for m in matches:
            line_end = full_text.find('\n', m.start())
            if line_end == -1:
                line_end = len(full_text)
            line = full_text[m.start():line_end]
            if len(line.strip()) < 50:
                short_line.append(m)
        if len(short_line) >= 35:
            matches = short_line
            print(f"  Filtered to short lines: {len(matches)}")
    
    sections = []
    if matches and matches[0].start() > 500:
        sections.append({'start': 0, 'end': matches[0].start(), 'label': '1'})
    
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i+1].start() if i+1 < len(matches) else len(full_text)
        sections.append({'start': start, 'end': end, 'label': str(i + 2)})
    
    print(f"  Total sections: {len(sections)}")
    
    output = []
    for i, sec in enumerate(sections):
        content = full_text[sec['start']:sec['end']]
        content = clean_content(content)
        if len(content) < 100:
            continue
        num = i + 1
        output.append({
            "id": num,
            "number": num,
            "chapterLabel": str(num),
            "heading": f"{heading_word} {num}",
            "title": get_title(content, lang_code),
            "content": content,
            "language": lang_code,
            "version": 1
        })
    
    return output


def main():
    langs = sys.argv[1:] if len(sys.argv) > 1 else ['bn', 'gu']
    
    for lang in langs:
        print(f"\n{'='*50}")
        print(f"  Building: {lang}")
        print(f"{'='*50}")
        
        if lang == 'bn':
            output = build_bengali()
        elif lang == 'gu':
            output = build_gujarati()
        elif lang == 'pa':
            output = build_generic(lang, 'pan', 'ਅਧਿਆਇ')
        elif lang == 'kn':
            output = build_generic(lang, 'kan', 'ಅಧ್ಯಾಯ')
        elif lang == 'ta':
            output = build_generic(lang, 'tam', 'அத்தியாயம்')
        elif lang == 'ml':
            output = build_generic(lang, 'mal', 'അധ്യായം')
        elif lang == 'or':
            output = build_generic(lang, 'ori', 'ଅଧ୍ୟାୟ')
        elif lang == 'ne':
            output = build_generic(lang, 'nep', 'अध्याय')
        else:
            print(f"  Unknown language: {lang}")
            continue
        
        if output:
            out_path = os.path.join(OUTPUT_DIR, f'satcharita_{lang}.json')
            with open(out_path, 'w', encoding='utf-8') as f:
                json.dump(output, f, ensure_ascii=False, indent=2)
            print(f"  Output: {out_path} ({len(output)} chapters)")
            if output:
                print(f"  Ch.1: {output[0]['title'][:80]}")
                print(f"  Ch.2: {output[1]['title'][:80]}" if len(output) > 1 else "")
        else:
            print(f"  No output generated for {lang}")


if __name__ == '__main__':
    main()
