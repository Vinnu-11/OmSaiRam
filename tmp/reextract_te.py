#!/usr/bin/env python3
"""Re-extract Telugu Sai Satcharita from embedded PDF text (not OCR)."""

import fitz
import re
import json

PDF_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/source_pdfs/satcharita_te.pdf'
OUTPUT_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_te.json'
EN_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'


def extract_text_from_pdf():
    """Extract all embedded text from Telugu PDF."""
    doc = fitz.open(PDF_PATH)
    all_text = []
    
    # Content starts at page 16 (0-indexed)
    for i in range(16, len(doc)):
        text = doc[i].get_text().strip()
        if text:
            lines = text.split('\n')
            # Remove page number at start
            if lines and lines[0].strip().isdigit():
                lines = lines[1:]
            all_text.append('\n'.join(lines).strip())
    
    doc.close()
    return '\n\n'.join(all_text)


def find_chapters(full_text):
    """Find chapter boundaries using the chapter header pattern."""
    # Each chapter starts with:
    # ఓెం/ఓం
    # శ్రీ
    # సాయిబాబా
    # జీవిత చరితరము
    # XXXవ అధాాయము
    # 
    # [title/description]
    # [content]
    
    # Find all chapter start positions
    chapter_pattern = r'సాయిబాబా\s*\n\s*జీవిత చరితరము\s*\n\s*(.+?అధా+యము)'
    matches = list(re.finditer(chapter_pattern, full_text))
    
    print(f"Found {len(matches)} chapter markers")
    
    chapters = []
    for idx, match in enumerate(matches):
        # Chapter starts from the chapter name line
        chapter_name = match.group(1).strip()
        
        # Content starts after the chapter name line
        content_start = match.end()
        
        # Content ends at the next chapter's "ఓెం" or "ఓం" before the next "సాయిబాబా"
        if idx + 1 < len(matches):
            # Find the start of next chapter's preamble (ఓెం/ఓం before next match)
            next_match_start = matches[idx + 1].start()
            # Look backwards from next match for ఓెం or ఓం or "సంప్ూర్ణము"
            search_area = full_text[content_start:next_match_start]
            
            # Find the end marker "సంప్ూర్ణము" (chapter complete)
            end_marker = re.search(r'సంప్ూర్ణము', search_area)
            if end_marker:
                content_end = content_start + end_marker.start()
            else:
                # Look for "ఓెం" or "ఓం" that signals next chapter start
                preamble = re.search(r'\n\s*ఓ[ెం]+\s*\n', search_area)
                if preamble:
                    content_end = content_start + preamble.start()
                else:
                    content_end = next_match_start - 50  # leave some buffer
        else:
            # Last chapter
            content_end = len(full_text)
            # Try to find "సంప్ూర్ణము" in remaining text
            search_area = full_text[content_start:]
            end_marker = re.search(r'సంప్ూర్ణము', search_area)
            if end_marker:
                content_end = content_start + end_marker.start()
        
        content = full_text[content_start:content_end].strip()
        
        # Extract title from first meaningful line of content
        title_lines = []
        for line in content.split('\n'):
            line = line.strip()
            if line and len(line) > 5:
                title_lines.append(line)
                if len(' '.join(title_lines)) > 30:
                    break
        title = ' '.join(title_lines)[:200] if title_lines else chapter_name
        
        chapters.append({
            'chapter_name': chapter_name,
            'title': title,
            'content': content
        })
    
    return chapters


def clean_content(text):
    """Clean up content text."""
    # Remove excessive whitespace
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
            cleaned.append(line)
            prev_empty = False
    
    result = '\n'.join(cleaned).strip()
    # Remove any remaining triple+ newlines
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result


def build_json(chapters, en_chapters):
    """Build the final JSON output, mapping to 47 chapters like English."""
    num_target = 47  # Match English chapter count
    
    print(f"Source chapters: {len(chapters)}, Target: {num_target}")
    
    # If we have more chapters than 47, we need to combine some
    # If fewer, we might need to split or use what we have
    
    json_output = []
    
    if len(chapters) >= num_target:
        # Map chapters - some Telugu editions have 50-53 chapters
        # We'll use the first 47 or combine trailing ones
        for i in range(num_target):
            if i < len(chapters):
                ch = chapters[i]
                content = clean_content(ch['content'])
                title = ch['title']
            else:
                content = ""
                title = en_chapters[i]['title'] if i < len(en_chapters) else ""
            
            json_output.append({
                "id": i + 1,
                "number": i + 1,
                "chapterLabel": str(i + 1),
                "heading": f"అధ్యాయం {i + 1}",
                "title": title,
                "content": content,
                "language": "te",
                "version": 1
            })
        
        # If there are remaining chapters beyond 47, append to last
        if len(chapters) > num_target:
            extra_content = []
            for ch in chapters[num_target:]:
                extra_content.append(clean_content(ch['content']))
            if extra_content:
                json_output[-1]['content'] += '\n\n' + '\n\n'.join(extra_content)
    else:
        # Fewer chapters - use what we have, pad remaining with English titles
        for i in range(num_target):
            if i < len(chapters):
                ch = chapters[i]
                content = clean_content(ch['content'])
                title = ch['title']
            else:
                content = ""
                title = en_chapters[i]['title'] if i < len(en_chapters) else ""
            
            json_output.append({
                "id": i + 1,
                "number": i + 1,
                "chapterLabel": str(i + 1),
                "heading": f"అధ్యాయం {i + 1}",
                "title": title,
                "content": content,
                "language": "te",
                "version": 1
            })
    
    return json_output


def main():
    print("=== Telugu Re-extraction from PDF Embedded Text ===")
    
    # Load English for reference
    with open(EN_PATH, 'r', encoding='utf-8') as f:
        en_chapters = json.load(f)
    
    # Extract text
    print("Extracting text from PDF...")
    full_text = extract_text_from_pdf()
    print(f"Total text: {len(full_text):,} characters")
    
    # Find chapters
    print("Finding chapter boundaries...")
    chapters = find_chapters(full_text)
    print(f"Found {len(chapters)} chapters")
    
    # Print chapter summary
    for i, ch in enumerate(chapters[:5]):
        print(f"  Ch {i+1}: {ch['chapter_name']}")
        print(f"    Title: {ch['title'][:80]}")
        print(f"    Content length: {len(ch['content']):,} chars")
    
    # Build JSON
    print("\nBuilding JSON...")
    json_output = build_json(chapters, en_chapters)
    
    # Validate
    filled = sum(1 for ch in json_output if ch['content'])
    sizes = [len(ch['content']) for ch in json_output]
    print(f"\nValidation:")
    print(f"  Chapters with content: {filled}/{len(json_output)}")
    print(f"  Total chars: {sum(sizes):,}")
    print(f"  Min/Max/Avg size: {min(sizes):,} / {max(sizes):,} / {sum(sizes)//len(sizes):,}")
    
    # Write output
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        json.dump(json_output, f, ensure_ascii=False, indent=2)
    
    print(f"\nWritten to: {OUTPUT_PATH}")
    
    # Show sample of first chapter
    print(f"\n=== Sample (Chapter 1, first 300 chars) ===")
    print(json_output[0]['content'][:300])


if __name__ == '__main__':
    main()
