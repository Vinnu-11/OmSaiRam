"""
Add English ## subheadings to all non-English Satcharita JSON files.

Strategy:
- For each English chapter, extract ## subheading texts and their fractional
  position (character offset / total content length).
- For each non-English chapter, insert those same English subheading lines
  at the closest paragraph boundary matching the same fractional position.
- A paragraph boundary = "\n\n" split point.
- The heading is inserted as its own paragraph: "## Heading Text"
"""

import json
import glob
import os
import copy

CONTENT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "om_sai_ram", "assets", "content",
)

def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def extract_subheadings(en_chapters):
    """Return {chapter_number: [(frac_position, heading_text), ...]}"""
    result = {}
    for ch in en_chapters:
        content = ch["content"]
        total_len = len(content)
        if total_len == 0:
            result[ch["number"]] = []
            continue

        headings = []
        pos = 0
        for block in content.split("\n\n"):
            trimmed = block.strip()
            if trimmed.startswith("## "):
                frac = pos / total_len
                headings.append((frac, trimmed))
            pos += len(block) + 2  # +2 for the \n\n separator
        result[ch["number"]] = headings
    return result

def insert_subheadings(content, headings):
    """Insert heading lines into content at proportional positions.
    
    headings: [(frac_position, heading_text), ...]
    Returns new content string.
    """
    if not headings:
        return content

    # Split into paragraph blocks
    blocks = content.split("\n\n")
    total_len = len(content)
    if total_len == 0:
        return content

    # Compute cumulative character offsets for each block start
    offsets = []
    pos = 0
    for block in blocks:
        offsets.append(pos)
        pos += len(block) + 2
    # offsets[i] = character offset of the start of blocks[i]

    # For each heading, find the best block index to insert before
    insertions = []  # (block_index, heading_text)
    used_indices = set()

    for frac, heading_text in headings:
        target_pos = frac * total_len
        # Find closest block boundary
        best_idx = 0
        best_dist = abs(offsets[0] - target_pos)
        for i, off in enumerate(offsets):
            dist = abs(off - target_pos)
            if dist < best_dist:
                best_dist = dist
                best_idx = i

        # Don't insert at index 0 if it would be the very first thing
        # (the italic summary line is usually first)
        if best_idx == 0 and len(blocks) > 1:
            best_idx = 1

        # Avoid inserting two headings at the same position
        while best_idx in used_indices and best_idx < len(blocks):
            best_idx += 1
        used_indices.add(best_idx)
        insertions.append((best_idx, heading_text))

    # Sort by block index descending so insertions don't shift earlier indices
    insertions.sort(key=lambda x: x[0], reverse=True)

    for idx, heading_text in insertions:
        blocks.insert(idx, heading_text)

    return "\n\n".join(blocks)

def main():
    en_path = os.path.join(CONTENT_DIR, "satcharita_en.json")
    en_data = load_json(en_path)
    heading_map = extract_subheadings(en_data)

    # Count total headings
    total_headings = sum(len(h) for h in heading_map.values())
    print(f"Extracted {total_headings} subheadings from English across {len(en_data)} chapters")

    # Process each non-English file
    files = sorted(glob.glob(os.path.join(CONTENT_DIR, "satcharita_*.json")))
    for fpath in files:
        fname = os.path.basename(fpath)
        lang = fname.replace("satcharita_", "").replace(".json", "")
        if lang == "en":
            continue

        data = load_json(fpath)
        modified = 0
        for ch in data:
            ch_num = ch["number"]
            headings = heading_map.get(ch_num, [])
            if not headings:
                continue

            # Skip if chapter already has ## headings
            existing = sum(1 for line in ch["content"].split("\n") if line.strip().startswith("## "))
            if existing > 0:
                continue

            new_content = insert_subheadings(ch["content"], headings)
            if new_content != ch["content"]:
                ch["content"] = new_content
                modified += 1

        if modified > 0:
            save_json(fpath, data)
            # Verify
            verify_data = load_json(fpath)
            verify_h2 = sum(
                1 for c in verify_data
                for line in c["content"].split("\n")
                if line.strip().startswith("## ")
            )
            print(f"  {lang}: updated {modified} chapters, {verify_h2} total ## headings now")
        else:
            print(f"  {lang}: no changes needed")

if __name__ == "__main__":
    main()
