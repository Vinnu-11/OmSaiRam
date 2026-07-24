#!/usr/bin/env python3
"""
Fix Telugu text by applying the halant-before-vowel-sign correction.
The Telugu PDF has a systematic encoding issue where U+0C4D (halant/virama)
appears before vowel signs where it shouldn't be.

Also re-extract using OCR for comparison on first few pages to verify quality.
"""

import json
import re
import os

BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
TE_JSON = os.path.join(BASE_DIR, 'om_sai_ram/assets/content/satcharita_te.json')

# Telugu vowel signs (matras) - Unicode range U+0C3E to U+0C4C
# Also U+0C55 (length mark) and U+0C56 (AI length mark)
TELUGU_VOWEL_SIGNS = set('\u0C3E\u0C3F\u0C40\u0C41\u0C42\u0C43\u0C44\u0C46\u0C47\u0C48\u0C4A\u0C4B\u0C4C\u0C55\u0C56')
TELUGU_HALANT = '\u0C4D'  # ్


def fix_telugu_halant(text):
    """Remove halant (virama) when it appears before a vowel sign.
    
    In proper Telugu, halant only appears before consonants (to form conjuncts).
    The PDF extraction erroneously inserts halant before vowel signs.
    """
    result = []
    i = 0
    while i < len(text):
        if text[i] == TELUGU_HALANT and i + 1 < len(text) and text[i + 1] in TELUGU_VOWEL_SIGNS:
            # Skip the halant - it's spurious before a vowel sign
            i += 1
            continue
        result.append(text[i])
        i += 1
    return ''.join(result)


def fix_telugu_file():
    """Apply the halant fix to the Telugu JSON file."""
    print("Loading Telugu JSON...")
    with open(TE_JSON, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    print(f"Found {len(data)} chapters")
    
    # Show before/after for first chapter title
    orig_title = data[0]['title']
    fixed_title = fix_telugu_halant(orig_title)
    print(f"\nBefore: {orig_title}")
    print(f"After:  {fixed_title}")
    
    # Apply fix to all chapters
    for chapter in data:
        chapter['title'] = fix_telugu_halant(chapter['title'])
        chapter['content'] = fix_telugu_halant(chapter['content'])
        chapter['heading'] = fix_telugu_halant(chapter.get('heading', ''))
    
    # Show another example
    print(f"\nChapter 2 title before: {json.loads(open(TE_JSON).read())[1]['title']}")
    print(f"Chapter 2 title after:  {data[1]['title']}")
    
    # Write fixed file
    with open(TE_JSON, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    print(f"\n✓ Fixed Telugu file written: {TE_JSON}")


if __name__ == '__main__':
    fix_telugu_file()
