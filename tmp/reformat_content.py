"""
Reformat OCR-extracted Satcharita content to match English format.
"""

import json
import re
import os
import sys

CONTENT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "om_sai_ram", "assets", "content"
)

OCR_LANGS = ['te', 'bn', 'gu', 'pa', 'kn', 'ta', 'ml', 'or', 'ne']


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def get_english_structure():
    en_path = os.path.join(CONTENT_DIR, "satcharita_en.json")
    en_data = load_json(en_path)
    structure = {}
    for ch in en_data:
        content = ch["content"]
        paras = content.split("\n\n")
        para_counts = []
        current_count = 0
        for p in paras:
            s = p.strip()
            if s.startswith("## "):
                para_counts.append(current_count)
                current_count = 0
            elif s == "---":
                para_counts.append(current_count)
                current_count = 0
            elif not s.startswith("_") and not re.match(r'^\d+\.', s) and s:
                current_count += 1
        if current_count > 0:
            para_counts.append(current_count)

        heading_positions = []
        total_len = len(content)
        pos = 0
        for p in paras:
            if p.strip().startswith("## "):
                heading_positions.append(pos / total_len if total_len > 0 else 0)
            pos += len(p) + 2

        structure[ch["number"]] = {
            "heading_positions": heading_positions,
            "para_counts": para_counts,
        }
    return structure


def clean_line(line):
    s = line.strip()
    if not s:
        return ""
    # Remove noise prefixes
    c = re.sub(r'^[|/!\"\'\[\](.#*॥।~$]{1,3}\s*', '', s)
    c = re.sub(r'^[.,]\s+', '', c)
    c = re.sub(r'^\d{1,3}\s{2,}', '', c)
    # Remove noise suffixes
    c = re.sub(r'\s*[|/\[\]~]{1,2}\s*$', '', c)
    c = re.sub(r'\s+\d{1,3}\s*$', '', c)
    c = re.sub(r'\s*[॥।]+\s*$', '', c)
    c = re.sub(r'\s*[*]+\s*$', '', c)
    # Clean inner noise
    c = re.sub(r'\s+["\']\s+', ' ', c)
    c = re.sub(r'\s{2,}', ' ', c)
    return c.strip()


def is_likely_heading(line, avg_len):
    s = line.strip()
    if len(s) < 12 or len(s) > 70:
        return False
    if len(s) > avg_len * 0.6:
        return False
    if sum(1 for c in s if ord(c) > 0x0900) < 5:
        return False
    if s.endswith(',') or s.endswith(':'):
        return False
    if re.match(r'^\d+\)', s) or re.match(r'^\(\d+\)', s):
        return False
    return True


def find_native_headings(lines, en_positions, total_chars):
    if not en_positions:
        return []
    offsets = []
    off = 0
    for l in lines:
        offsets.append(off)
        off += len(l) + 1
    long_lines = [l for l in lines if len(l.strip()) > 30]
    avg_len = sum(len(l) for l in long_lines) / max(len(long_lines), 1)
    found = []
    for frac in en_positions:
        target = frac * total_chars
        window = total_chars * 0.10
        cands = []
        for i, l in enumerate(lines):
            dist = abs(offsets[i] - target)
            if dist > window:
                continue
            if i in [h[0] for h in found]:
                continue
            if is_likely_heading(l.strip(), avg_len):
                cands.append((dist + len(l.strip()) * 5, i, l.strip()))
        if cands:
            cands.sort()
            found.append((cands[0][1], cands[0][2]))
    return found


def split_into_paragraphs(text, target_count):
    if target_count <= 1 or len(text) < 200:
        return [text]
    breaks = [m.end() for m in re.finditer(r'[।॥.]\s+', text)]
    if not breaks:
        return [text]
    target_len = len(text) / target_count
    paras = []
    last = 0
    for i in range(1, target_count):
        target_pos = i * target_len
        valid = [b for b in breaks if b > last]
        if not valid:
            break
        best = min(valid, key=lambda b: abs(b - target_pos))
        if best < len(text) - 50:
            paras.append(text[last:best].strip())
            last = best
    rem = text[last:].strip()
    if rem:
        paras.append(rem)
    return paras


def join_and_paragraph(lines, heading_idx, en_para_counts):
    sections = []
    cur = []
    for i, l in enumerate(lines):
        if i in heading_idx:
            if cur:
                sections.append(("text", cur))
            sections.append(("heading", [l]))
            cur = []
        else:
            if l.strip():
                cur.append(l)
    if cur:
        sections.append(("text", cur))

    parts = []
    sec_i = 0
    for stype, slines in sections:
        if stype == "heading":
            h = slines[0].strip()
            h = re.sub(r'\s*[॥।|*,.]+\s*$', '', h)
            parts.append(f"## {h}")
        else:
            joined = " ".join(l.strip() for l in slines if l.strip())
            joined = re.sub(r'\s{2,}', ' ', joined)
            if not joined.strip():
                continue
            target = en_para_counts[sec_i] if sec_i < len(en_para_counts) else 3
            sec_i += 1
            if target <= 1:
                parts.append(joined)
            else:
                parts.extend(split_into_paragraphs(joined, target))

    return "\n\n".join(parts)


def reformat_chapter(content, en_struct):
    # Remove existing ## headings
    c = re.sub(r'\n\n## .+\n\n', '\n', content)
    c = re.sub(r'^## .+$', '', c, flags=re.MULTILINE)
    
    lines = [clean_line(l) for l in c.split('\n')]
    lines = [l for l in lines if l]
    if not lines:
        return content

    total = sum(len(l) + 1 for l in lines)
    headings = find_native_headings(lines, en_struct.get("heading_positions", []), total)
    h_idx = set(h[0] for h in headings)
    return join_and_paragraph(lines, h_idx, en_struct.get("para_counts", [3]))


def main():
    langs = sys.argv[1:] if len(sys.argv) > 1 else OCR_LANGS
    print("Loading English structure...")
    en_struct = get_english_structure()
    print(f"  {len(en_struct)} chapters")

    for lang in langs:
        print(f"\nProcessing: {lang}")
        fpath = os.path.join(CONTENT_DIR, f"satcharita_{lang}.json")
        data = load_json(fpath)
        modified = 0
        for ch in data:
            s = en_struct.get(ch["number"], {"heading_positions": [], "para_counts": [3]})
            new = reformat_chapter(ch["content"], s)
            if new != ch["content"]:
                ch["content"] = new
                modified += 1
        save_json(fpath, data)
        print(f"  Modified {modified} chapters")

        # Verify
        total_h = sum(len(re.findall(r'^## .+', ch["content"], re.MULTILINE)) for ch in data)
        total_p = sum(len(ch["content"].split("\n\n")) for ch in data)
        snl = sum(p.count('\n') for ch in data for p in ch["content"].split("\n\n") if not p.startswith("##"))
        print(f"  Result: {total_h} headings, {total_p} paragraphs, {snl} single-newlines")

        # Sample
        ch5 = data[4]["content"] if len(data) > 4 else data[0]["content"]
        ps = ch5.split("\n\n")
        print(f"  Ch.5 sample ({len(ps)} paras):")
        for i, p in enumerate(ps[:4]):
            t = "HDG" if p.startswith("##") else "TXT"
            print(f"    [{i}] {t}({len(p)}): {p[:90]}...")


if __name__ == "__main__":
    main()
"""
Reformat OCR-extracted Satcharita content to match English format.

For each non-English chapter (OCR-extracted languages):
1. Remove any existing ## headings
2. Clean OCR noise characters from line starts/ends
3. Join lines into continuous text (remove page-width line breaks)
4. Detect and mark native language subheadings with ##
5. Split content into paragraphs matching English structure proportionally
"""

import json
import re
import os
import sys

CONTENT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "om_sai_ram", "assets", "content"
)

OCR_LANGS = ['te', 'bn', 'gu', 'pa', 'kn', 'ta', 'ml', 'or', 'ne']


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def get_english_structure():
    """Extract paragraph structure from English chapters."""
    en_path = os.path.join(CONTENT_DIR, "satcharita_en.json")
    en_data = load_json(en_path)

    structure = {}
    for ch in en_data:
        content = ch["content"]
        paras = content.split("\n\n")

        para_counts_per_section = []
        current_count = 0

        for p in paras:
            stripped = p.strip()
            if stripped.startswith("## "):
                para_counts_per_section.append(current_count)
                current_count = 0
            elif stripped == "---":
                para_counts_per_section.append(current_count)
                current_count = 0
            elif not stripped.startswith("_") and not re.match(r'^\d+\.', stripped) and stripped:
                current_count += 1

        if current_count > 0:
            para_counts_per_section.append(current_count)

        # Heading positions as fractions
        heading_positions = []
        total_len = len(content)
        pos = 0
        for p in paras:
            if p.strip().startswith("## "):
                heading_positions.append(pos / total_len if total_len > 0 else 0)
            pos += len(p) + 2

        structure[ch["number"]] = {
            "heading_positions": heading_positions,
            "para_counts": para_counts_per_section,
        }

    return structure


def clean_line(line):
    """Remove OCR noise from a single line."""
    stripped = line.strip()
    if not stripped:
        return ""

    # Remove noise prefixes (OCR artifacts from page margins)
    cleaned = re.sub(r'^[|/!\"\'\[\](.#*॥।~$]{1,3}\s*', '', stripped)
    # Leading period/comma alone
    cleaned = re.sub(r'^[.,]\s+', '', cleaned)
    # Leading page numbers (digits + multi-space)
    cleaned = re.sub(r'^\d{1,3}\s{2,}', '', cleaned)

    # Remove trailing noise
    cleaned = re.sub(r'\s*[|/\[\]~]{1,2}\s*$', '', cleaned)
    cleaned = re.sub(r'\s+\d{1,3}\s*$', '', cleaned)
    cleaned = re.sub(r'\s*[॥।]+\s*$', '', cleaned)
    cleaned = re.sub(r'\s*[*]+\s*$', '', cleaned)

    # Remove stray quotes surrounded by spaces
    cleaned = re.sub(r'\s+["\']\s+', ' ', cleaned)
    # Collapse multiple spaces
    cleaned = re.sub(r'\s{2,}', ' ', cleaned)

    return cleaned.strip()


def is_likely_heading(line, avg_line_len):
    """Check if a line is likely a native subheading."""
    stripped = line.strip()
    if len(stripped) < 12 or len(stripped) > 70:
        return False
    if len(stripped) > avg_line_len * 0.6:
        return False

    # Must have Indic script chars
    script_chars = sum(1 for c in stripped if ord(c) > 0x0900)
    if script_chars < 5:
        return False

    # Not a continuation
    if stripped.endswith(',') or stripped.endswith(':'):
        return False

    # Not a numbered item
    if re.match(r'^\d+\)', stripped) or re.match(r'^\(\d+\)', stripped):
        return False

    return True


def find_native_headings(content_lines, en_heading_positions, total_chars):
    """Find native language headings near expected positions."""
    if not en_heading_positions:
        return []

    line_offsets = []
    offset = 0
    for line in content_lines:
        line_offsets.append(offset)
        offset += len(line) + 1

    long_lines = [l for l in content_lines if len(l.strip()) > 30]
    avg_line_len = sum(len(l) for l in long_lines) / max(len(long_lines), 1)

    found_headings = []

    for frac_pos in en_heading_positions:
        target_offset = frac_pos * total_chars
        window_size = total_chars * 0.10

        candidates = []
        for i, line in enumerate(content_lines):
            stripped = line.strip()
            line_offset = line_offsets[i]
            distance = abs(line_offset - target_offset)

            if distance > window_size:
                continue
            if i in [h[0] for h in found_headings]:
                continue

            if is_likely_heading(stripped, avg_line_len):
                score = distance + len(stripped) * 5
                candidates.append((score, i, stripped))

        if candidates:
            candidates.sort()
            found_headings.append((candidates[0][1], candidates[0][2]))

    return found_headings


def split_into_paragraphs(text, target_count):
    """Split text into paragraphs at sentence boundaries."""
    if target_count <= 1 or len(text) < 200:
        return [text]

    # Sentence boundaries: purna viram, double danda, period+space
    sentence_breaks = [m.end() for m in re.finditer(r'[।॥.]\s+', text)]

    if not sentence_breaks:
        return [text]

    target_len = len(text) / target_count
    paragraphs = []
    last_split = 0

    for i in range(1, target_count):
        target_pos = i * target_len
        best_break = min(
            (brk for brk in sentence_breaks if brk > last_split),
            key=lambda b: abs(b - target_pos),
            default=None
        )

        if best_break and best_break < len(text) - 50:
            paragraphs.append(text[last_split:best_break].strip())
            last_split = best_break

    remaining = text[last_split:].strip()
    if remaining:
        paragraphs.append(remaining)

    return paragraphs


def join_and_paragraph(content_lines, heading_indices, en_para_counts):
    """Join lines into continuous text and split into paragraphs."""
    sections = []
    current_lines = []

    for i, line in enumerate(content_lines):
        if i in heading_indices:
            if current_lines:
                sections.append(("text", current_lines))
            sections.append(("heading", [line]))
            current_lines = []
        else:
            if line.strip():
                current_lines.append(line)
    if current_lines:
        sections.append(("text", current_lines))

    result_parts = []
    section_idx = 0

    for sec_type, sec_lines in sections:
        if sec_type == "heading":
            heading_text = sec_lines[0].strip()
            heading_text = re.sub(r'\s*[॥।|*,.]+\s*$', '', heading_text)
            result_parts.append(f"## {heading_text}")
        else:
            joined = " ".join(l.strip() for l in sec_lines if l.strip())
            joined = re.sub(r'\s{2,}', ' ', joined)

            if not joined.strip():
                continue

            target_paras = en_para_counts[section_idx] if section_idx < len(en_para_counts) else 3
            section_idx += 1

            if target_paras <= 1:
                result_parts.append(joined)
            else:
                paragraphs = split_into_paragraphs(joined, target_paras)
                result_parts.extend(paragraphs)

    return "\n\n".join(result_parts)


def reformat_chapter(chapter_content, en_structure):
    """Reformat a single chapter's content."""
    # Remove existing ## headings
    content = re.sub(r'\n\n## .+\n\n', '\n', chapter_content)
    content = re.sub(r'^## .+$', '', content, flags=re.MULTILINE)

    # Clean lines
    raw_lines = content.split('\n')
    cleaned_lines = [clean_line(l) for l in raw_lines]
    cleaned_lines = [l for l in cleaned_lines if l]

    if not cleaned_lines:
        return chapter_content

    # Find native headings
    total_chars = sum(len(l) + 1 for l in cleaned_lines)
    native_headings = find_native_headings(
        cleaned_lines,
        en_structure.get("heading_positions", []),
        total_chars
    )
    heading_indices = set(h[0] for h in native_headings)

    # Build paragraphed output
    return join_and_paragraph(
        cleaned_lines,
        heading_indices,
        en_structure.get("para_counts", [3])
    )


def process_language(lang, en_structure_map):
    """Process all chapters for a language."""
    fpath = os.path.join(CONTENT_DIR, f"satcharita_{lang}.json")
    data = load_json(fpath)

    modified = 0
    for ch in data:
        ch_num = ch["number"]
        en_struct = en_structure_map.get(ch_num, {
            "heading_positions": [],
            "para_counts": [3],
        })

        old_content = ch["content"]
        new_content = reformat_chapter(old_content, en_struct)

        if new_content != old_content:
            ch["content"] = new_content
            modified += 1

    save_json(fpath, data)
    return modified


def verify_language(lang):
    """Print verification info."""
    fpath = os.path.join(CONTENT_DIR, f"satcharita_{lang}.json")
    data = load_json(fpath)

    total_headings = 0
    total_paras = 0
    single_newlines = 0

    for ch in data:
        content = ch["content"]
        total_headings += len(re.findall(r'^## .+', content, re.MULTILINE))
        paras = content.split("\n\n")
        total_paras += len(paras)
        for p in paras:
            if not p.startswith("##"):
                single_newlines += p.count('\n')

    print(f"  {lang}: {total_headings} headings, {total_paras} paragraphs, {single_newlines} single-newlines")

    ch5 = data[4]["content"] if len(data) > 4 else data[0]["content"]
    paras = ch5.split("\n\n")
    print(f"    Ch.5: {len(paras)} paragraphs")
    for i, p in enumerate(paras[:6]):
        ptype = "HEADING" if p.startswith("##") else "TEXT"
        print(f"      [{i}] {ptype} ({len(p)}): {p[:80]}...")


def main():
    langs = sys.argv[1:] if len(sys.argv) > 1 else OCR_LANGS

    print("Loading English structure...")
    en_structure = get_english_structure()
    print(f"  {len(en_structure)} chapters analyzed")

    for lang in langs:
        print(f"\nProcessing: {lang}")
        modified = process_language(lang, en_structure)
        print(f"  Modified {modified} chapters")
        verify_language(lang)


if __name__ == "__main__":
    main()
"""Reformat OCR-extracted Satcharita content to match English format."""

import json, re, os, sys

CONTENT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "om_sai_ram", "assets", "content")
OCR_LANGS = ['te', 'bn', 'gu', 'pa', 'kn', 'ta', 'ml', 'or', 'ne']

def load_json(path):
    with open(path, encoding="utf-8") as f: return json.load(f)

def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f: json.dump(data, f, ensure_ascii=False, indent=2)

def get_english_structure():
    en_data = load_json(os.path.join(CONTENT_DIR, "satcharita_en.json"))
    structure = {}
    for ch in en_data:
        content = ch["content"]
        paras = content.split("\n\n")
        para_counts = []
        cur = 0
        for p in paras:
            s = p.strip()
            if s.startswith("## "):
                para_counts.append(cur); cur = 0
            elif s == "---":
                para_counts.append(cur); cur = 0
            elif not s.startswith("_") and not re.match(r'^\d+\.', s) and s:
                cur += 1
        if cur > 0: para_counts.append(cur)
        
        hpos = []
        total_len = len(content)
        pos = 0
        for p in paras:
            if p.strip().startswith("## "):
                hpos.append(pos / total_len if total_len > 0 else 0)
            pos += len(p) + 2
        structure[ch["number"]] = {"heading_positions": hpos, "para_counts": para_counts}
    return structure

def clean_line(line):
    s = line.strip()
    if not s: return ""
    c = re.sub(r'^[|/!\"\'\[\](.#*\u0965\u0964~$]{1,3}\s*', '', s)
    c = re.sub(r'^[.,]\s+', '', c)
    c = re.sub(r'^\d{1,3}\s{2,}', '', c)
    c = re.sub(r'\s*[|/\[\]~]{1,2}\s*$', '', c)
    c = re.sub(r'\s+\d{1,3}\s*$', '', c)
    c = re.sub(r'\s*[\u0965\u0964]+\s*$', '', c)
    c = re.sub(r'\s*[*]+\s*$', '', c)
    c = re.sub(r'\s+["\']\s+', ' ', c)
    c = re.sub(r'\s{2,}', ' ', c)
    return c.strip()

def is_likely_heading(line, avg_len):
    s = line.strip()
    if len(s) < 12 or len(s) > 70: return False
    if len(s) > avg_len * 0.6: return False
    if sum(1 for c in s if ord(c) > 0x0900) < 5: return False
    if s.endswith(',') or s.endswith(':'): return False
    if re.match(r'^\d+\)', s): return False
    return True

def find_native_headings(lines, en_positions, total_chars):
    if not en_positions: return []
    offsets = []
    off = 0
    for l in lines:
        offsets.append(off)
        off += len(l) + 1
    long_l = [l for l in lines if len(l.strip()) > 30]
    avg = sum(len(l) for l in long_l) / max(len(long_l), 1)
    found = []
    for frac in en_positions:
        target = frac * total_chars
        window = total_chars * 0.10
        cands = []
        for i, l in enumerate(lines):
            dist = abs(offsets[i] - target)
            if dist > window: continue
            if i in [h[0] for h in found]: continue
            if is_likely_heading(l.strip(), avg):
                cands.append((dist + len(l.strip()) * 5, i, l.strip()))
        if cands:
            cands.sort()
            found.append((cands[0][1], cands[0][2]))
    return found

def split_paragraphs(text, target_count):
    if target_count <= 1 or len(text) < 200: return [text]
    breaks = [m.end() for m in re.finditer(r'[\u0964\u0965.]\s+', text)]
    if not breaks: return [text]
    tlen = len(text) / target_count
    paras = []
    last = 0
    for i in range(1, target_count):
        tpos = i * tlen
        valid = [b for b in breaks if b > last]
        if not valid: break
        best = min(valid, key=lambda b: abs(b - tpos))
        if best < len(text) - 50:
            paras.append(text[last:best].strip())
            last = best
    rem = text[last:].strip()
    if rem: paras.append(rem)
    return paras

def join_and_paragraph(lines, h_idx, para_counts):
    sections = []/double chars that OCR artifacts from page margins)
    cleaned = re.sub(r'^[|/!\"\'\[\](.#*॥।]{1,3}\s*', '', stripped)
    # Leading period or comma alone
    cleaned = re.sub(r'^[.,]\s+', '', cleaned)
    # Leading digits + multi-space (page numbers)
    cleaned = re.sub(r'^\d{1,3}\s{2,}', '', cleaned)

    # Remove trailing noise
    cleaned = re.sub(r'\s*[|/\[\]]{1,2}\s*$', '', cleaned)
    cleaned = re.sub(r'\s+\d{1,3}\s*$', '', cleaned)
    cleaned = re.sub(r'\s*[॥।]+\s*$', '', cleaned)
    cleaned = re.sub(r'\s*[*,]+\s*$', '', cleaned)

    # Remove stray quote marks surrounded by spaces (OCR noise)
    cleaned = re.sub(r'\s+["\']\s+', ' ', cleaned)
    # Collapse multiple spaces
    cleaned = re.sub(r'\s{2,}', ' bers, margin chars)
    cleaned = re.sub(r'\s*[|/\[\]]{1,2}\s*$', '', cleaned)
    if len(stripped) < 12 or len(stripped) > 70:
        return False
    if len(stripped) > avg_line_len * 0.6:
        return False

    # Must contain substantial Indic script text
    script_chars = sum(1 for c in stripped if ord(c) > 0x0900)
    if script_chars < 5:
        return False

    # Should not end with continuation patterns
    if stripped.endswith(',') or stripped.endswith(':'):
        return False

    # Avoid verse numbers or numbered items
    if re.match(r'^\d+\)', stripped) or re.match(r'^\(\d+\)', stripped):
        return False

    return Tru < 5:
        return False

    # Should not end with sentence-continuation patterns
    if stripped.endswith(',') or stripped.endswith(':'):
        return False

    # Avoid lines that look like verse numbers or short fragments
    if re.match(r'^\d+\)', stripped) or re.match(r'^\(\d+\)', stripped)

def reformat_chapter(content, en_struct):
    c = re.sub(r'\n\n## .+\n\n', '\n', content)
    c = re.sub(r'^## .+$', '', c, flags=re.MULTILINE)
    lines = [clean_line(l) for l in c.split('\n')]
    lines = [l for l in lines if l]
    if not lines: return content
    total = sum(len(l) + 1 for l in lines)
    hdgs = find_native_headings(lines, en_struct.get("heading_positions", []), total)
    return join_and_paragraph(lines, set(h[0] for h in hdgs), en_struct.get("para_counts", [3]))

def main():
    langs = sys.argv[1:] if len(sys.argv) > 1 else OCR_LANGS
    print("Loading English structure...")
    en_struct = get_english_structure()
    print(f"  {len(en_struct)} chapters")

    for lang in langs:
        print(f"\nProcessing: {lang}")
        fpath = os.path.join(CONTENT_DIR, f"satcharita_{lang}.json")
        data = load_json(fpath)
        mod = 0
        for ch in data:
            s = en_struct.get(ch["number"], {"heading_positions": [], "para_counts": [3]})
            new = reformat_chapter(ch["content"], s)
            if new != ch["content"]:

        # Search in a window around the target position (10% of total)
        window_size = total_chars * 0.10

        candidates = []

        for i, line in enumerate(content_lines):
            stripped = line.strip()
            line_offset = line_offsets[i]

            # Check if within search window
            distance = abs(line_offset - target_offset)
            if distance > window_size:
                continue

            # Skip if already used
            if i in [h[0] for h in found_headings]:
                continue

            # Check if this line looks like a heading
            if is_likely_heading(stripped, avg_line_len):
                # Score: prefer shorter lines closer to target
                score = distance + len(stripped) * 5  # penalize longer lines
                candidates.append((score, i, stripped))

        if candidates:
            candidates.sort()
            best = candidates[0]
            found_headings.append((best[1], best[2])ALL ## headings (both English and native from previous runs)
    content = re.sub(r'\n\n## .+\n\n', '\n', chapter_content)
    content = re.sub(r'^## .+$', '', content, flags=re.MULTILINE)
    # Also clean any doubled ## from previous bad runs
    content = re.sub(r'^##\s*##\s*# Try to reload from OCR cache to get clean source content
    cache_path = os.path.join(os.path.dirname(__file__), "ocr_cache", f"{lang}_pages.json")
    ocr_extract_path = os.path.join(os.path.dirname(__file__), "ocr_extract.py")

    # If we have a fresh original backup, use it. Otherwise work from current content.
    # For idempotency: always strip any existing ## headings before processing

    