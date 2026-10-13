"""
Comprehensive proofreading fix for Sai Satcharita content.

Fixes:
1. DE/ES/FR titles that are mid-sentence content fragments
2. Verifies and reports all remaining issues

Issues documented but NOT fixed (require re-extraction):
- Chapter misalignment in BN, FR, GU, HI, KOK, MR, NE, PA
- Truncated chapters in BN, NE, PA, TE, UR
- OCR artifacts in BN, PA, UR, SD
"""

import json
import os
import re
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


def extract_fr_title(content):
    """Extract title from French chapter content.
    French chapters often start with: CHAPITRE N\n\nTitle Line"""
    lines = content.strip().split('\n')
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('CHAPITRE') and re.match(r'CHAPITRE\s+\d+', stripped):
            # Next non-empty line after chapter marker should be the title
            for j in range(i + 1, min(i + 5, len(lines))):
                candidate = lines[j].strip()
                if candidate and not candidate.startswith('##') and not candidate.startswith('CHAPITRE'):
                    if len(candidate) > 5 and candidate[0].isupper():
                        return candidate
    return None


def extract_de_title(content):
    """Extract title from German content.
    German chapters typically have descriptive content after chapter header."""
    # Look for section header patterns
    lines = content.strip().split('\n')
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('Kapitel') or stripped.startswith('KAPITEL'):
            for j in range(i + 1, min(i + 5, len(lines))):
                candidate = lines[j].strip()
                if candidate and len(candidate) > 5 and candidate[0].isupper():
                    return candidate
    return None


def extract_es_title(content):
    """Extract title from Spanish content."""
    lines = content.strip().split('\n')
    for i, line in enumerate(lines):
        stripped = line.strip()
        if re.match(r'(?:CAPÍTULO|Capítulo)\s+\d+', stripped):
            for j in range(i + 1, min(i + 5, len(lines))):
                candidate = lines[j].strip()
                if candidate and len(candidate) > 5 and candidate[0].isupper():
                    return candidate
    return None


def fix_titles_for_latin_langs():
    """Fix DE/ES/FR titles that are mid-sentence fragments."""
    en_data = load_json(os.path.join(CONTENT_DIR, "satcharita_en.json"))
    en_titles = {ch['number']: ch['title'] for ch in en_data}

    fixes = {'de': 0, 'es': 0, 'fr': 0}

    for lang, extractor in [('fr', extract_fr_title), ('de', extract_de_title), ('es', extract_es_title)]:
        path = os.path.join(CONTENT_DIR, f"satcharita_{lang}.json")
        data = load_json(path)
        modified = False

        for ch in data:
            title = ch['title'].strip()
            # Detect bad titles (start with lowercase = mid-sentence fragment)
            if title and title[0].islower():
                # Try to extract from content
                extracted = extractor(ch['content'])
                if extracted and len(extracted) > 10:
                    old_title = ch['title']
                    ch['title'] = extracted
                    fixes[lang] += 1
                    modified = True
                    print(f"  [{lang}] Ch {ch['number']}: '{old_title[:50]}' -> '{extracted[:50]}'")
                else:
                    # Fallback to English title
                    en_title = en_titles.get(ch['number'], '')
                    if en_title:
                        ch['title'] = en_title
                        fixes[lang] += 1
                        modified = True
                        print(f"  [{lang}] Ch {ch['number']}: '{title[:50]}' -> EN: '{en_title[:50]}'")

        if modified:
            save_json(path, data)

    return fixes


def check_and_report():
    """Generate comprehensive report of all issues."""
    en_data = load_json(os.path.join(CONTENT_DIR, "satcharita_en.json"))
    en_titles = {ch['number']: ch['title'] for ch in en_data}

    report = []
    report.append("=" * 80)
    report.append("SAI SATCHARITA CONTENT PROOFREADING REPORT")
    report.append("=" * 80)

    langs = sorted([f.replace('satcharita_', '').replace('.json', '')
                    for f in os.listdir(CONTENT_DIR) if f.endswith('.json')])

    # === ISSUE 1: English subheadings in non-English content ===
    report.append("\n\n1. ENGLISH SUBHEADINGS IN NON-ENGLISH CONTENT")
    report.append("-" * 50)
    total_en_headers = 0
    for lang in langs:
        if lang == 'en':
            continue
        data = load_json(os.path.join(CONTENT_DIR, f"satcharita_{lang}.json"))
        en_header_count = 0
        for ch in data:
            headers = re.findall(r'^##\s+(.+)$', ch['content'], re.MULTILINE)
            en_headers = [h for h in headers if re.match(r'^[A-Za-z\s\'\-\(\)\d,\.]+$', h.strip())]
            en_header_count += len(en_headers)
        total_en_headers += en_header_count
        report.append(f"  {lang}: {en_header_count} English headers")
    report.append(f"  TOTAL: {total_en_headers} English headers across all languages")
    report.append("  STATUS: These provide section navigation. Keep or translate.")

    # === ISSUE 2: Chapter misalignment ===
    report.append("\n\n2. CHAPTER CONTENT MISALIGNMENT")
    report.append("-" * 50)
    total_misaligned = 0
    for lang in langs:
        if lang == 'en':
            continue
        data = load_json(os.path.join(CONTENT_DIR, f"satcharita_{lang}.json"))
        misaligned = []
        for ch in data:
            content_start = ch['content'][:300]
            found_nums = re.findall(
                r'(?:chapter|अध्याय|অধ্যায়|ਅਧਿਆਇ|adhyay|kapitel|chapitre|capítulo|అధ్యాయం|அத்தியாயம்|ಅಧ್ಯಾಯ|അധ്യായം|ଅଧ୍ୟାୟ|باب|અધ્યાય)\s*[-:]*\s*(\d+)',
                content_start, re.IGNORECASE)
            if found_nums:
                found_set = set(int(x) for x in found_nums)
                expected_nums = set(int(x) for x in re.findall(r'\d+', ch['heading']))
                if found_set and expected_nums and not (found_set & expected_nums):
                    misaligned.append(ch['number'])
        if misaligned:
            total_misaligned += len(misaligned)
            report.append(f"  {lang}: {len(misaligned)} misaligned chapters: {misaligned}")
    report.append(f"  TOTAL: {total_misaligned} misaligned chapters")
    report.append("  STATUS: Requires re-extraction from PDFs with proper chapter detection")

    # === ISSUE 3: Truncated chapters ===
    report.append("\n\n3. TRUNCATED CHAPTERS (< 30% of English length)")
    report.append("-" * 50)
    total_truncated = 0
    for lang in langs:
        if lang == 'en':
            continue
        data = load_json(os.path.join(CONTENT_DIR, f"satcharita_{lang}.json"))
        truncated = []
        for i, ch in enumerate(data):
            en_len = len(en_data[i]['content'])
            lang_len = len(ch['content'])
            ratio = lang_len / en_len if en_len else 0
            if ratio < 0.3:
                truncated.append((ch['number'], f"{ratio:.0%}"))
        if truncated:
            total_truncated += len(truncated)
            report.append(f"  {lang}: {truncated}")
    report.append(f"  TOTAL: {total_truncated} truncated chapters")
    report.append("  STATUS: Requires re-extraction with better OCR")

    # === ISSUE 4: Bad titles ===
    report.append("\n\n4. BAD/FRAGMENT TITLES (DE/ES/FR)")
    report.append("-" * 50)
    for lang in ['de', 'es', 'fr']:
        data = load_json(os.path.join(CONTENT_DIR, f"satcharita_{lang}.json"))
        bad = [ch['number'] for ch in data if ch['title'].strip() and ch['title'].strip()[0].islower()]
        if bad:
            report.append(f"  {lang}: {len(bad)} remaining bad titles: {bad}")
        else:
            report.append(f"  {lang}: All titles OK")

    return "\n".join(report)


def main():
    print("=== Fixing DE/ES/FR titles ===\n")
    fixes = fix_titles_for_latin_langs()
    print(f"\nTitle fixes applied: DE={fixes['de']}, ES={fixes['es']}, FR={fixes['fr']}")

    print("\n\n=== Generating report ===\n")
    report = check_and_report()
    print(report)

    # Save report
    report_path = os.path.join(os.path.dirname(__file__), "proofread_report.txt")
    with open(report_path, "w") as f:
        f.write(report)
    print(f"\nReport saved to: {report_path}")


if __name__ == "__main__":
    main()
