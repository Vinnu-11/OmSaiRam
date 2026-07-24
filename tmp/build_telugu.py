#!/usr/bin/env python3
"""
Properly split and clean Telugu OCR output using chapter end markers.
"""

import json
import re

CACHE = '/home/vdamarl/pers/OmSaiRam/tmp/ocr_cache/te_pages.json'
OUTPUT = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_te.json'

with open(CACHE, 'r') as f:
    pages = json.load(f)

full_text = '\n\n'.join(pages)

# Split by chapter end markers "సంపూర్ణము"
end_markers = list(re.finditer(r'సంపూర్ణము', full_text))
print(f"End markers found: {len(end_markers)}")

# Create chapters (text between consecutive end markers)
raw_chapters = []
prev_end = 0
for marker in end_markers:
    chapter_text = full_text[prev_end:marker.start()]
    raw_chapters.append(chapter_text)
    prev_end = marker.end()

# We might have 49 splits but only need 47 - some might be duplicates or empty
# Filter out very short ones (noise)
chapters = [ch for ch in raw_chapters if len(ch.strip()) > 200]
print(f"Chapters after filtering: {len(chapters)}")

# If we have more than 47, take only first 47
if len(chapters) > 47:
    chapters = chapters[:47]
elif len(chapters) < 47:
    print(f"WARNING: Only {len(chapters)} chapters found, expected 47")


def clean_chapter(text):
    """Remove OCR border artifacts and noise from chapter text."""
    lines = text.split('\n')
    cleaned_lines = []
    
    # Track if we've found the real content start
    found_content = False
    
    for line in lines:
        orig = line
        # Remove leading/trailing pipe chars (borders)
        line = re.sub(r'^[|\s]*', '', line)
        line = re.sub(r'[|\s]*$', '', line)
        
        # Remove trailing single-char noise (border decorations)
        line = re.sub(r'\s+[వ్‌శన్‌యఇఎ,\./]+\s*$', '', line)
        line = re.sub(r'\s+[+\-]\s*$', '', line)
        
        # Remove leading single-char noise
        line = re.sub(r'^[జితి\.,/]\s+', '', line)
        
        # Skip pure noise lines
        stripped = line.strip()
        if not stripped:
            if cleaned_lines and cleaned_lines[-1] != '':
                cleaned_lines.append('')
            continue
        
        # Skip page numbers
        if re.match(r'^\d{1,3}$', stripped):
            continue
        
        # Skip very short noise (1-2 chars)
        if len(stripped) <= 2 and not re.match(r'[\u0C00-\u0C7F]{2}', stripped):
            continue
            
        # Skip the chapter preamble lines (ఓం, శ్రీ, సాయిబాబా, జీవిత చరిత్రము, chapter name)
        if not found_content:
            if re.match(r'^(ఓం|ఓెం|శ్రీ)$', stripped):
                continue
            if stripped in ['ఓం .', 'ఓం', '_ ఓం .', '_ ఓం']:
                continue
            if re.match(r'^సాయిబాబా', stripped):
                continue
            if re.match(r'^జీవిత\s+చరిత్రము', stripped):
                continue
            if re.match(r'^(మొదటి|రెండవ|మూడవ|నాల[ుగ]+వ|అయిదవ|ఐదవ|ఆరవ|ఏడవ|ఎనిమిదవ|తొమ్మిదవ|పద|ఇరవై|ముప్పై|నలభై|\d+\s*వ)\s*అధ్యాయ', stripped):
                continue
            if re.match(r'^[లనవశ్‌్ని\d\s\.\,\(\)టం]+$', stripped):
                continue
            # Once we find a line with substantial Telugu content, start keeping
            if len(stripped) > 10 and re.search(r'[\u0C05-\u0C6F]{3,}', stripped):
                found_content = True
        
        if found_content or len(stripped) > 15:
            found_content = True
            cleaned_lines.append(stripped)
    
    result = '\n'.join(cleaned_lines)
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result.strip()


def get_title(content, max_len=150):
    """Extract title from cleaned content."""
    lines = content.split('\n')
    title_parts = []
    for line in lines:
        line = line.strip()
        if not line or len(line) < 5:
            continue
        title_parts.append(line)
        if len(' '.join(title_parts)) > 60:
            break
    title = ' '.join(title_parts)
    # Clean any remaining artifacts
    title = re.sub(r'[|\[\]]', '', title)
    title = re.sub(r'\s+', ' ', title).strip()
    return title[:max_len] if title else "అధ్యాయం"


# Process chapters
output = []
for i, raw in enumerate(chapters):
    content = clean_chapter(raw)
    title = get_title(content)
    
    output.append({
        "id": i + 1,
        "number": i + 1,
        "chapterLabel": str(i + 1),
        "heading": f"అధ్యాయం {i + 1}",
        "title": title,
        "content": content,
        "language": "te",
        "version": 1
    })

# Write output
with open(OUTPUT, 'w') as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"\nOutput: {len(output)} chapters")
for i in range(min(5, len(output))):
    print(f"  Ch.{i+1}: {output[i]['title'][:80]}")
print(f"\nCh.1 content (first 200 chars):")
print(output[0]['content'][:200])
print(f"\nCh.2 content (first 200 chars):")
print(output[1]['content'][:200])
