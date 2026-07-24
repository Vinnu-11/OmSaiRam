#!/usr/bin/env python3
"""Clean OCR artifacts from Telugu extraction."""

import json
import re

TE_JSON = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_te.json'
EN_JSON = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'

with open(TE_JSON, 'r') as f:
    te_data = json.load(f)

with open(EN_JSON, 'r') as f:
    en_data = json.load(f)


def clean_border_artifacts(text):
    """Remove OCR artifacts from page borders/margins."""
    # Remove lines that are mostly single chars with spaces (border decorations)
    # Pattern: isolated single Telugu chars at line boundaries
    lines = text.split('\n')
    cleaned = []
    for line in lines:
        stripped = line.strip()
        # Skip empty lines (keep one blank)
        if not stripped:
            if cleaned and cleaned[-1] != '':
                cleaned.append('')
            continue
        # Skip lines that are just page numbers
        if stripped.isdigit() and len(stripped) <= 3:
            continue
        # Skip lines that are just border chars: |, ], [, single Telugu chars
        if re.match(r'^[\|\]\[\s]+$', stripped):
            continue
        # Remove leading/trailing border artifacts from lines
        # Leading: ], |, single Telugu letter followed by space
        stripped = re.sub(r'^[\|\]\[\s]*', '', stripped)
        # Trailing: |, [, single char
        stripped = re.sub(r'[\|\]\[\s]*$', stripped, stripped)
        # Remove isolated single-char noise at line boundaries
        # Pattern: a single Telugu char (with optional virama) surrounded by spaces
        # that doesn't connect to adjacent words
        stripped = re.sub(r'^\s*[వ్‌శన్‌య]+\s+', '', stripped)
        stripped = re.sub(r'\s+[వ్‌శన్‌]+\s*$', '', stripped)
        
        if stripped and len(stripped) > 1:
            cleaned.append(stripped)
    
    result = '\n'.join(cleaned)
    # Final cleanup
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result.strip()


def extract_title(content, chapter_num):
    """Extract a clean title from chapter content."""
    lines = content.split('\n')
    # Skip the chapter header line
    title_lines = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        # Skip chapter number lines
        if re.match(r'^\d+\s*(వ|వ‌)?\s*అధ్యాయము', line):
            continue
        if 'సంపూర్ణము' in line:
            continue
        if len(line) < 5:
            continue
        title_lines.append(line)
        if len(' '.join(title_lines)) > 60:
            break
    
    title = ' '.join(title_lines)
    # Clean artifacts from title
    title = re.sub(r'[|\]\[]', '', title)
    title = re.sub(r'\s+', ' ', title).strip()
    return title[:150] if title else f"అధ్యాయము {chapter_num}"


# Process each chapter
for i, ch in enumerate(te_data):
    content = ch['content']
    
    # Remove chapter header from start
    content = re.sub(r'^అధ్యాయము[^\n]*\n*', '', content)
    # Remove "సంపూర్ణము" end markers that may have gotten included
    content = re.sub(r'\n*సంపూర్ణము\.?\s*$', '', content)
    content = re.sub(r'^సంపూర్ణము\.?\s*\n*', '', content)
    
    # Clean border artifacts
    content = clean_border_artifacts(content)
    
    # Extract clean title
    title = extract_title(content, i + 1)
    
    ch['content'] = content
    ch['title'] = title
    ch['heading'] = f"అధ్యాయం {i + 1}"

# Write
with open(TE_JSON, 'w') as f:
    json.dump(te_data, f, ensure_ascii=False, indent=2)

print("Telugu cleaned!")
for i in range(min(5, len(te_data))):
    print(f"  Ch.{i+1}: {te_data[i]['title'][:80]}")
print(f"\nCh.1 content preview:")
print(te_data[0]['content'][:300])
