#!/usr/bin/env python3
"""Comprehensive cleanup for Telugu Sai Satcharita - remove OCR/PDF artifacts."""

import json
import re
import copy

TE_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_te.json'
EN_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'

TELUGU_CONSONANTS = r'[\u0C15-\u0C39]'  # క-హ
TELUGU_VOWELS = r'[\u0C05-\u0C14]'  # అ-ఔ 
TELUGU_SIGNS = r'[\u0C3E-\u0C56]'  # vowel signs
TELUGU_CHAR = r'[\u0C00-\u0C7F]'  # any Telugu

def clean_te_content(text):
    """Clean Telugu content text - remove OCR/PDF artifacts."""

    # ===== PHASE 1: Remove specific known garbage patterns =====
    
    # Page number + fragment combos from PDF page boundaries
    text = re.sub(r'త్ 5 ఆం అ, ౨ఇరి\.?', '', text)
    text = re.sub(r'౮ ౮ చ,\s*', '', text)
    text = re.sub(r'ణి శ \d+ చ్\s*', '', text)
    
    # "ల్ని 17 టం" type patterns (stray chars + page number + stray chars)
    text = re.sub(r'ల్ని\s+\d+\s+టం\s*', '', text)
    
    # ===== PHASE 2: Remove stray single Telugu chars at boundaries =====
    # These are fragments from page breaks where a word got split
    
    # After period + space: single stray char before next sentence
    # "కలదు. శ్ సాయిబాబా" → "కలదు. సాయిబాబా"  
    for _ in range(3):  # Multiple passes
        text = re.sub(
            r'(?<=\.)\s+(' + TELUGU_CHAR + r'్?\s)(?=' + TELUGU_CHAR + r'{2,})',
            ' ',
            text
        )
    
    # After newline: stray single char at start of paragraph
    for _ in range(3):
        text = re.sub(
            r'(?<=\n)\s*(' + TELUGU_CHAR + r'్?\s)(?=' + TELUGU_CHAR + r'{2,})',
            '',
            text
        )
    
    # Stray single chars at end of paragraphs (before \n\n or end)
    text = re.sub(r'\s+' + TELUGU_CHAR + r'్?\s*(?=\n\n|$)', '', text)
    
    # ===== PHASE 3: Remove embedded page numbers =====
    # Pattern: Telugu text + isolated 2-digit number + Telugu text
    # But preserve legitimate numbers like years (1910, 1700) and counts (95, etc.)
    
    # Remove 2-digit numbers flanked by Telugu text when they look like page numbers
    # "శాశ్వతమైన 30 తృప్తిని" → "శాశ్వతమైన తృప్తిని"
    text = re.sub(r'(?<=' + TELUGU_SIGNS + r')\s+\d{1,2}\s+(?=' + TELUGU_CHAR + r')', ' ', text)
    
    # "1700 క సంవత్సరములో" → "1700 సంవత్సరములో"
    text = re.sub(r'(\d{4})\s+క\s+', r'\1 ', text)
    
    # ===== PHASE 4: Remove stray punctuation artifacts =====
    
    # Stray quotes in middle of sentences
    text = re.sub(r'(?<=' + TELUGU_SIGNS + r')\s+"\s+(?=' + TELUGU_CHAR + r')', ' ', text)
    text = re.sub(r'(?<=\.)\s+"\s+(?=' + TELUGU_CHAR + r')', ' ', text)
    
    # Stray underscores
    text = re.sub(r'\s+_\s+', ' ', text)
    
    # Stray "వొ" (OCR artifact)
    text = re.sub(r'\bవొ\s+(?=' + TELUGU_CHAR + r')', '', text)
    
    # ===== PHASE 5: Remove Telugu digit artifacts =====
    text = re.sub(r'\s+౫\s+(?=' + TELUGU_CHAR + r')', ' ', text)
    text = re.sub(r'(?<=' + TELUGU_SIGNS + r')\s+౫\s*(?=\n)', '', text)
    
    # ===== PHASE 6: Clean up chapter preamble from content start =====
    # Many chapters start with: "ఎ జీవిత చరిత్రము XXవ అధ్యాయము"
    # We strip ONLY the first line if it matches the preamble pattern
    
    lines = text.split('\n')
    # Check if first non-empty line is a preamble
    first_line_idx = -1
    for i, line in enumerate(lines):
        if line.strip():
            first_line_idx = i
            break
    
    if first_line_idx >= 0:
        first_line = lines[first_line_idx].strip()
        # Pattern: optional garbage + "జీవిత చరిత్రము" + chapter name + "అధ్యాయము"
        preamble_match = re.match(
            r'^(?:.*?జీవిత\s*చరి(?:త్రము|తరము)\s+)?'  # Optional "జీవిత చరిత్రము"
            r'(?:' + TELUGU_CHAR + r'+వ|మొదటి|రెండవ|మూడవ|నాలుగవ|అయిదవ)\s+'
            r'అధ్(?:యా|ాా)యము\s*'
            r'(.*)',  # Rest after chapter marker
            first_line
        )
        if preamble_match:
            rest = preamble_match.group(1).strip()
            if rest:
                lines[first_line_idx] = rest
            else:
                lines[first_line_idx] = ''
    
    text = '\n'.join(lines)
    
    # Also remove standalone preamble patterns
    text = re.sub(r'^శ్రీ సాయినాధాయ నమః\s+శ్రీ సాయిబాబా\s+జీవిత చరిత్రము\s+మొదటి అధ్యాయము\s+', '', text)
    
    # Remove day/reading annotations but only at very start
    text = re.sub(r'^%\s*', '', text)
    text = re.sub(r'^=\s*', '', text)
    
    # Remove "రెండవరోజు/ఐదవరోజు పారాయణము సమాప్తము" lines
    text = re.sub(r'^' + TELUGU_CHAR + r'+రోజు పారాయణము సమాప్తము\.?\s*\n*', '', text)
    
    # Remove "ఓం శ్రీ సాయిబాబా" preamble lines at start  
    text = re.sub(r'^(?:\d+\s+)?(?:ఓెం|ఓం)\s+శ్రీ\s+సాయిబాబా\s*(?:ల్)?\s*\n*', '', text)
    text = re.sub(r'^(?:\d+\s+)?(?:ఓెం|ఓం)\s+శ్రీ\s*\n*', '', text)
    
    # Remove day annotations
    text = re.sub(r'^\(?\d*వ?\s*(?:రోజు\s+)?పారాయణ(?:ము)?\s*[-–]?\s*' + TELUGU_CHAR + r'*వారము\s*\)?\s*\n*', '', text)
    text = re.sub(r'^' + TELUGU_CHAR + r'+వదినము\s+పారాయణము\s*[-–]?\s*' + TELUGU_CHAR + r'*వారము\s*\)?\s*\n*', '', text)
    
    # Remove garbage at start: "న సాయిబాబా ల్ ఎ జీవిత చరిత్రము"
    text = re.sub(r'^(?:న్?|నే|ల్ని|॥్?|లి)\s+(?:సాయిబాబా\s+)?(?:ల్?\s+)?(?:శ\s+)?(?:ఎ|ఇ|న|టి)?\s*జీవిత\s*చరి(?:త్రము|తరము)\s*', '', text)
    text = re.sub(r'^(?:న్?|నే)\s+సాయిబాబా\s+(?:ల్?\s+)?(?:శ\s+)?(?:ఎ|ఇ|న)?\s*\n*', '', text)
    
    # Remove stray "ళ్‌" 
    text = re.sub(r'\s+ళ్‌', '', text)
    
    # Remove "కిని ంచిాకి." and similar OCR noise
    text = re.sub(r'కిని\s+ంచిాకి\.?\s*', '', text)
    text = re.sub(r'జిని\s+వినిల\s+చికి\.?\s*', '', text)
    text = re.sub(r'క్షిాకి\.?\s*', '', text)
    
    # Remove stray "ం" at sentence boundary
    text = re.sub(r'తొలిపలుకు\s+ం\s+', 'తొలిపలుకు ', text)
    
    # Remove "1..." from heading
    text = re.sub(r'## 1\.\.\.\s+', '## ', text)
    
    # Remove "ప్రస్తావన ః" → "ప్రస్తావన"
    text = re.sub(r'ప్రస్తావన\s+ః\s+', 'ప్రస్తావన ', text)
    
    # ===== PHASE 7: Clean up remaining stray single chars at content start =====
    # Some chapters start with "లు ", "లో ", "లి ", "ల్ " - fragments from prev chapter
    for _ in range(3):
        text = re.sub(r'^' + TELUGU_CHAR + r'{1,2}[్ుిీూెేైొోౌం]?\s+(?=' + TELUGU_CHAR + r'{3,}|##|\d)', '', text)
    
    # Remove "గ!" at start
    text = re.sub(r'^గ!\s*', '', text)
    
    # ===== PHASE 8: Final whitespace cleanup =====
    text = re.sub(r'  +', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    lines = text.split('\n')
    lines = [line.strip() for line in lines]
    text = '\n'.join(lines).strip()
    
    return text


def clean_te_title(title):
    """Clean Telugu chapter title."""
    # Remove "ఎ " prefix
    title = re.sub(r'^ఎ\s+', '', title)
    
    # Remove "(." or "/." prefix
    title = re.sub(r'^[(/]+\.\s*', '', title)
    title = re.sub(r'^/\.\s*', '', title)
    
    # Remove trailing digits
    title = re.sub(r'\s+\d\s*$', '', title)
    
    # Remove "ళ్‌" and similar
    title = re.sub(r'ళ్‌', '', title)
    title = re.sub(r'ల్ని\s+\d+\s+టం', '', title)
    
    # Remove "!" artifact
    title = re.sub(r'\s*!\s*', ' ', title)
    
    # Remove "న్‌" artifacts
    title = re.sub(r'^న్‌\s*', '', title)
    
    # Remove chapter header parts: "జీవిత చరిత్రము XXవ అధ్యాయము"
    title = re.sub(r'^.*?అధ్యాయము\s*', '', title)
    
    # Remove day annotations
    title = re.sub(r'.*రోజు\s+పారాయణము\s+సమాప్తము\.?\s*', '', title)
    
    # Remove "5 " and "%" prefixes
    title = re.sub(r'^\d+\s+', '', title)
    title = re.sub(r'^%\s*', '', title)
    
    # Remove "శ్రీ సాయిబాబా" standalone  
    title = re.sub(r'^శ్రీ\s+సాయిబాబా\s*$', '', title)
    title = re.sub(r'^\d*\s*ఓం\s+శ్రీ.*$', '', title)
    
    # Remove stray single chars
    title = re.sub(r'^' + TELUGU_CHAR + r'{1,2}[్ుిీూెేైొోౌం]?\s+', '', title)
    title = re.sub(r'\s+' + TELUGU_CHAR + r'{1,2}[్ుిీూెేైొోౌం]?\s*$', '', title)
    
    # Remove "॥"
    title = re.sub(r'॥్?\s*', '', title)
    
    # Clean up
    title = re.sub(r'\s+', ' ', title).strip(' .,;:/"\'!()')
    
    return title


def derive_title_from_content(content):
    """Extract title from cleaned content - first meaningful line before ## heading."""
    for line in content.split('\n'):
        line = line.strip()
        if not line:
            continue
        if line.startswith('##'):
            break
        if len(line) > 10:
            return line[:200]
    return ''


def main():
    with open(TE_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)
    with open(EN_PATH, 'r', encoding='utf-8') as f:
        en_data = json.load(f)
    
    for i, ch in enumerate(data):
        # Clean content
        ch['content'] = clean_te_content(ch['content'])
        
        # Clean title
        ch['title'] = clean_te_title(ch['title'])
        
        # If title empty or too short, derive from content
        if not ch['title'] or len(ch['title']) < 5:
            ch['title'] = derive_title_from_content(ch['content'])
    
    # Save
    with open(TE_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    # Report
    print("=== Chapter Titles ===")
    for ch in data:
        print(f"Ch {ch['number']}: [{ch['title'][:100]}]")
    
    # Verify - check for remaining artifacts
    print("\n=== Remaining Issues ===")
    issue_count = 0
    for ch in data:
        content = ch['content']
        # Check for garbage patterns
        garbage = re.findall(r'(?:త్ 5|౮ ౮|ల్ని \d+ టం|ణి శ \d+)', content)
        stray_quotes = re.findall(r'\s"\s' + TELUGU_CHAR, content)
        stray_underscores = re.findall(r'\s_\s', content)
        
        issues = []
        if garbage:
            issues.append(f'{len(garbage)} garbage')
        if stray_quotes:
            issues.append(f'{len(stray_quotes)} quotes')
        if stray_underscores:
            issues.append(f'{len(stray_underscores)} underscores')
        
        if issues:
            issue_count += 1
            print(f"  Ch {ch['number']}: {', '.join(issues)}")
    
    if issue_count == 0:
        print("  All clean!")
    
    # Verify chapter 1 specifically (the user's highlighted issue)
    print("\n=== Ch 1 verification ===")
    ch1 = data[0]
    print(f"Title: [{ch1['title'][:100]}]")
    print(f"Content (first 500 chars):")
    print(ch1['content'][:500])


if __name__ == '__main__':
    main()
