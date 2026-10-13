#!/usr/bin/env python3
"""
Re-extract BN, NE, PA from OCR cache with proper chapter detection.
Also fix TE Ch9 and UR Ch1/44/46 truncation from PDF text.
Preserves English ## subheadings by re-injecting them after rebuild.
"""

import json, re, os, sys

BASE_DIR = '/home/vdamarl/pers/OmSaiRam'
CACHE_DIR = os.path.join(BASE_DIR, 'tmp/ocr_cache')
CONTENT_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/content')
PDF_DIR = os.path.join(BASE_DIR, 'om_sai_ram/assets/source_pdfs')

BN_DIGITS = '০১২৩৪৫৬৭৮৯'


def indic_to_int(s, digit_str=None):
    result = ''
    for c in s:
        if digit_str and c in digit_str:
            result += str(digit_str.index(c))
        elif c.isdigit():
            result += c
    return int(result) if result else 0


def clean_content(text):
    text = re.sub(r'^\s*\d{1,3}\s*$', '', text, flags=re.MULTILINE)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r' *\n *', '\n', text)
    return text.strip()


def get_title(content, max_len=150):
    lines = content.split('\n')
    parts = []
    for line in lines:
        line = line.strip()
        if not line or len(line) < 5 or line.isdigit():
            continue
        if re.match(r'^[\d\s|্‌.€₹%#]+$', line):
            continue
        parts.append(line)
        if len(' '.join(parts)) > 60:
            break
    title = ' '.join(parts[:2])
    return title[:max_len] if title else "Chapter"


def load_en_subheadings():
    """Load English chapter subheadings for re-injection."""
    with open(os.path.join(CONTENT_DIR, 'satcharita_en.json')) as f:
        en = json.load(f)
    result = {}
    for ch in en:
        content = ch['content']
        total_len = len(content)
        if total_len == 0:
            result[ch['number']] = []
            continue
        headings = []
        pos = 0
        for block in content.split('\n\n'):
            trimmed = block.strip()
            if trimmed.startswith('## '):
                frac = pos / total_len
                headings.append((frac, trimmed))
            pos += len(block) + 2
        result[ch['number']] = headings
    return result


def insert_subheadings(content, headings):
    if not headings:
        return content
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
    used_indices = set()
    for frac, heading_text in headings:
        target_pos = frac * total_len
        best_idx = 0
        best_dist = abs(offsets[0] - target_pos)
        for i, off in enumerate(offsets):
            dist = abs(off - target_pos)
            if dist < best_dist:
                best_dist = dist
                best_idx = i
        if best_idx == 0 and len(blocks) > 1:
            best_idx = 1
        while best_idx in used_indices and best_idx < len(blocks):
            best_idx += 1
        used_indices.add(best_idx)
        insertions.append((best_idx, heading_text))
    insertions.sort(key=lambda x: x[0], reverse=True)
    for idx, heading_text in insertions:
        blocks.insert(idx, heading_text)
    return '\n\n'.join(blocks)


def find_chapter_headers(full_text, header_pattern, digit_chars=None):
    """Find chapter headers, filtering out inline references."""
    matches = list(re.finditer(header_pattern, full_text, re.MULTILINE))
    headers = []
    for m in matches:
        pos = m.start()
        # Check if this is at line start (real header) vs inline reference
        line_start = full_text.rfind('\n', 0, pos)
        prefix = full_text[line_start+1:pos].strip() if line_start >= 0 else full_text[:pos].strip()
        # Real headers have short or no prefix before them
        is_line_start = len(prefix) < 30

        num_match = re.search(r'[০-৯੦-੯0-9]+', m.group())
        if num_match:
            num = indic_to_int(num_match.group(), digit_chars)
        else:
            continue

        # Skip inline references (chapter mentioned in body text)
        if not is_line_start:
            continue
        # Skip if number > 51 (invalid)
        if num > 51 or num < 1:
            continue

        headers.append((pos, num, m.group().strip()))
    return headers


def map_source_to_47(source_chapters):
    """Map source chapter list (up to 51 chapters) to our 47-entry structure.
    Merges: 16+17→16, 18+19→17, 43+44→41."""
    en_map = {}
    # Our 47 entries map to original chapter numbers:
    # Entry 1-15 → Ch 1-15
    # Entry 16 → Ch 16+17
    # Entry 17 → Ch 18+19
    # Entry 18-40 → Ch 20-42
    # Entry 41 → Ch 43+44
    # Entry 42-47 → Ch 45-50

    for i in range(1, 16):
        en_map[i] = [i]
    en_map[16] = [16, 17]
    en_map[17] = [18, 19]
    for i in range(18, 41):
        en_map[i] = [i + 2]  # entry 18→ch20, entry 19→ch21, ...entry 40→ch42
    en_map[41] = [43, 44]
    for i in range(42, 48):
        en_map[i] = [i + 3]  # entry 42→ch45, ...entry 47→ch50

    # Invert: source_ch → entry_num
    ch_to_entry = {}
    for entry, chs in en_map.items():
        for ch in chs:
            ch_to_entry[ch] = entry

    # Build output entries
    result = {}
    for src_ch_num, content in source_chapters.items():
        entry = ch_to_entry.get(src_ch_num)
        if entry:
            if entry in result:
                result[entry] += '\n\n' + content
            else:
                result[entry] = content

    return result


def build_from_cache(lang, cache_file, header_pattern, heading_prefix, digit_chars=None, content_start_page=0):
    """Generic builder from OCR cache."""
    with open(cache_file, 'r') as f:
        pages = json.load(f)

    # Skip preface pages
    content_pages = pages[content_start_page:]
    full_text = '\n\n'.join(content_pages)

    headers = find_chapter_headers(full_text, header_pattern, digit_chars)

    # Deduplicate: keep first occurrence of each chapter number
    seen = {}
    unique_headers = []
    for pos, num, text in headers:
        if num not in seen:
            seen[num] = True
            unique_headers.append((pos, num, text))

    # Sort by position
    unique_headers.sort(key=lambda x: x[0])

    print(f"  Found {len(unique_headers)} unique chapter headers")
    for pos, num, text in unique_headers[:5]:
        print(f"    Ch {num}: '{text[:60]}'")
    if len(unique_headers) > 5:
        print(f"    ... and {len(unique_headers)-5} more")

    # Split into source chapters
    source_chapters = {}
    for i, (pos, num, text) in enumerate(unique_headers):
        end = unique_headers[i+1][0] if i+1 < len(unique_headers) else len(full_text)
        content = full_text[pos:end]
        content = clean_content(content)
        if len(content) > 50:
            source_chapters[num] = content

    # Handle content before first header (might be Ch 1)
    if unique_headers:
        first_pos = unique_headers[0][0]
        first_num = unique_headers[0][1]
        pre_content = clean_content(full_text[:first_pos])
        if len(pre_content) > 200 and first_num > 1:
            # Content before first header is likely Chapter 1
            source_chapters[1] = pre_content
            print(f"  Added pre-header content as Ch 1 ({len(pre_content)} chars)")

    print(f"  Source chapters found: {sorted(source_chapters.keys())}")

    # Map to 47-entry structure
    mapped = map_source_to_47(source_chapters)
    print(f"  Mapped to {len(mapped)} entries: {sorted(mapped.keys())}")

    # Load English for reference
    with open(os.path.join(CONTENT_DIR, 'satcharita_en.json')) as f:
        en = json.load(f)
    en_headings = load_en_subheadings()

    output = []
    for entry_num in range(1, 48):
        content = mapped.get(entry_num, '')
        en_ch = en[entry_num - 1]

        if not content or len(content) < 50:
            print(f"  WARNING: Entry {entry_num} has no/insufficient content ({len(content)} chars)")
            continue

        # Add English subheadings
        headings = en_headings.get(entry_num, [])
        if headings:
            # Only add if not already present
            existing = sum(1 for line in content.split('\n') if line.strip().startswith('## '))
            if existing == 0:
                content = insert_subheadings(content, headings)

        output.append({
            "id": entry_num,
            "number": entry_num,
            "chapterLabel": en_ch['chapterLabel'],
            "heading": f"{heading_prefix} {entry_num}" if '-' not in en_ch['chapterLabel'] else f"{heading_prefix} {en_ch['chapterLabel']}",
            "title": get_title(content),
            "content": content,
            "language": lang,
            "version": 1
        })

    return output


def rebuild_bengali():
    print("\n=== Rebuilding Bengali (BN) ===")
    cache_file = os.path.join(CACHE_DIR, 'bn_pages.json')

    with open(cache_file) as f:
        pages = json.load(f)

    # BN pages: 0 is garbled preface, 1-4 is Ch 1, 5+ is Ch 2 onwards
    # Page 1 has "অধ্যার - ১" (OCR misread অধ্যায় as অধ্যার)
    # Match both অধ্যায় and অধ্যার with dash, plus combined chapters like ৪৩-৪৪
    header_pattern = r'অধ্যা(?:য়|র)\s*[-–.]\s*[০-৯0-9]+(?:\s*[-–]\s*[০-৯0-9]+)?'

    # Skip page 0 (garbled)
    return build_from_cache('bn', cache_file, header_pattern, 'অধ্যায়', BN_DIGITS, content_start_page=1)


def rebuild_nepali():
    print("\n=== Rebuilding Nepali (NE) ===")
    cache_file = os.path.join(CACHE_DIR, 'ne_pages.json')

    with open(cache_file) as f:
        pages = json.load(f)

    # NE: Pages 0-5 are prayers/mantras, Page 6 has Ch 1
    # Header pattern: "अध्याय N" at near-line-start, followed by short content
    # Need to distinguish from inline refs like "गीताकी अध्याय 5-16"
    header_pattern = r'अध्याय\s*[-–]?\s*[0-9]+(?:\s*र\s*[0-9]+)?'

    return build_from_cache('ne', cache_file, header_pattern, 'अध्याय', content_start_page=6)


def rebuild_punjabi():
    print("\n=== Rebuilding Punjabi (PA) ===")
    cache_file = os.path.join(CACHE_DIR, 'pa_pages.json')

    with open(cache_file) as f:
        pages = json.load(f)

    # PA: Page 2 has Ch 3 ("ਅਧਿਆਇ-3"), Page 7 has Ch 4
    # Missing Ch 1 and Ch 2 markers
    header_pattern = r'ਅਧਿਆਇ\s*[-–]?\s*[0-9]+(?:\s*[-–]\s*[0-9]+)?'

    return build_from_cache('pa', cache_file, header_pattern, 'ਅਧਿਆਇ', content_start_page=0)


def fix_telugu_ch9():
    """Fix truncated Telugu Chapter 9 by re-extracting from PDF."""
    print("\n=== Fixing Telugu Ch 9 ===")
    import fitz

    pdf_path = os.path.join(PDF_DIR, 'satcharita_te.pdf')
    json_path = os.path.join(CONTENT_DIR, 'satcharita_te.json')

    doc = fitz.open(pdf_path)
    with open(json_path) as f:
        te = json.load(f)

    # Find Ch 9 boundaries in PDF
    # Telugu Ch 9 = "తొమ్మిదవ అధ్యాయము"
    ch9_start = None
    ch10_start = None
    ch9_pattern = re.compile(r'తొమ్మిదవ\s+అధ్యాయము|తొమ్మిదవ\s*అధ్యాయము')
    ch10_pattern = re.compile(r'పదవ\s+అధ్యాయము|పదవ\s*అధ్యాయము')

    for i in range(doc.page_count):
        text = doc[i].get_text()
        if ch9_start is None and ch9_pattern.search(text):
            ch9_start = i
        if ch9_start is not None and ch10_start is None and ch10_pattern.search(text) and i > ch9_start:
            ch10_start = i
            break

    if ch9_start is not None and ch10_start is not None:
        print(f"  Ch 9: pages {ch9_start+1}-{ch10_start}")
        ch9_text = ''
        for i in range(ch9_start, ch10_start):
            ch9_text += doc[i].get_text() + '\n'
        ch9_text = clean_content(ch9_text)
        # Remove page numbers
        ch9_text = re.sub(r'^\d+\s*$', '', ch9_text, flags=re.MULTILINE)
        ch9_text = re.sub(r'\n{3,}', '\n\n', ch9_text)
        ch9_text = ch9_text.strip()

        old_len = len(te[8]['content'])
        te[8]['content'] = ch9_text
        te[8]['title'] = get_title(ch9_text)
        print(f"  Ch 9 content: {old_len} -> {len(ch9_text)} chars")

        with open(json_path, 'w') as f:
            json.dump(te, f, ensure_ascii=False, indent=2)
        print("  Saved.")
    else:
        print(f"  Could not find Ch 9 boundaries (start={ch9_start}, end={ch10_start})")
    doc.close()


def fix_urdu_truncated():
    """Fix truncated Urdu chapters by re-extracting from PDF."""
    print("\n=== Fixing Urdu truncated chapters ===")
    import fitz

    pdf_path = os.path.join(PDF_DIR, 'satcharita_ur.pdf')
    json_path = os.path.join(CONTENT_DIR, 'satcharita_ur.json')

    doc = fitz.open(pdf_path)
    total_pages = doc.page_count
    print(f"  Urdu PDF: {total_pages} pages")

    # Check if PDF has embedded text
    sample_text = doc[0].get_text().strip()
    if not sample_text:
        print("  Urdu PDF has no embedded text - OCR needed. Skipping.")
        doc.close()
        return

    with open(json_path) as f:
        ur = json.load(f)

    with open(os.path.join(CONTENT_DIR, 'satcharita_en.json')) as f:
        en = json.load(f)

    # Get full text from PDF
    all_text = ''
    for i in range(total_pages):
        all_text += doc[i].get_text() + '\n\n'

    # Find chapter markers: باب N
    pattern = r'باب\s+(\d+)'
    matches = list(re.finditer(pattern, all_text))
    print(f"  Found {len(matches)} باب markers")

    if len(matches) < 20:
        print("  Too few markers, using proportional approach instead")
        # Proportional re-extraction for truncated chapters
        total_len = len(all_text)
        en_total = sum(len(ch['content']) for ch in en)

        for entry_idx in [0, 43, 45]:  # Ch 1, 44, 46 (0-indexed)
            en_ch = en[entry_idx]
            # Calculate proportional position
            en_before = sum(len(en[j]['content']) for j in range(entry_idx))
            en_ch_len = len(en_ch['content'])
            frac_start = en_before / en_total
            frac_end = (en_before + en_ch_len) / en_total

            start_pos = int(frac_start * total_len)
            end_pos = int(frac_end * total_len)
            new_content = clean_content(all_text[start_pos:end_pos])

            old_len = len(ur[entry_idx]['content'])
            if len(new_content) > old_len * 1.5:
                ur[entry_idx]['content'] = new_content
                ur[entry_idx]['title'] = get_title(new_content)
                print(f"  Ch {ur[entry_idx]['number']}: {old_len} -> {len(new_content)} chars")

        with open(json_path, 'w') as f:
            json.dump(ur, f, ensure_ascii=False, indent=2)
        print("  Saved.")
    else:
        # Use chapter markers for proper extraction
        # (implementation for marker-based extraction)
        pass

    doc.close()


def save_output(output, lang, heading_prefix):
    """Save rebuilt chapters and validate."""
    out_path = os.path.join(CONTENT_DIR, f'satcharita_{lang}.json')

    # Validate: need 47 chapters
    if len(output) < 47:
        print(f"  WARNING: Only {len(output)} chapters (expected 47)")
        # Fill missing with previous content
        with open(out_path) as f:
            old = json.load(f)
        old_by_num = {ch['number']: ch for ch in old}

        existing_nums = {ch['number'] for ch in output}
        for num in range(1, 48):
            if num not in existing_nums:
                old_ch = old_by_num.get(num)
                if old_ch:
                    print(f"    Keeping old content for Ch {num} ({len(old_ch['content'])} chars)")
                    output.append(old_ch)

    output.sort(key=lambda x: x['number'])

    with open(out_path, 'w') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print(f"  Saved {len(output)} chapters to {out_path}")

    # Print comparison with English
    with open(os.path.join(CONTENT_DIR, 'satcharita_en.json')) as f:
        en = json.load(f)

    print(f"\n  Content length comparison (vs English):")
    en_by_num = {ch['number']: ch for ch in en}
    out_by_num = {ch['number']: ch for ch in output}
    issues = 0
    for num in range(1, 48):
        en_len = len(en_by_num[num]['content'])
        out_len = len(out_by_num.get(num, {}).get('content', ''))
        ratio = out_len / en_len if en_len else 0
        flag = " *** LOW" if ratio < 0.3 else ""
        if flag:
            issues += 1
            print(f"    Ch {num:2d}: {out_len:6d} chars ({ratio:.0%} of English){flag}")
    if issues == 0:
        print(f"    All chapters within acceptable range")
    else:
        print(f"    {issues} chapters still below 30% threshold")


def main():
    targets = sys.argv[1:] if len(sys.argv) > 1 else ['bn', 'ne', 'pa', 'te', 'ur']

    for lang in targets:
        if lang == 'bn':
            output = rebuild_bengali()
            if output:
                save_output(output, 'bn', 'অধ্যায়')
        elif lang == 'ne':
            output = rebuild_nepali()
            if output:
                save_output(output, 'ne', 'अध्याय')
        elif lang == 'pa':
            output = rebuild_punjabi()
            if output:
                save_output(output, 'pa', 'ਅਧਿਆਇ')
        elif lang == 'te':
            fix_telugu_ch9()
        elif lang == 'ur':
            fix_urdu_truncated()


if __name__ == '__main__':
    main()
