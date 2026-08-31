#!/usr/bin/env python3
"""Clean Telugu Sai Satcharita JSON - remove OCR/PDF extraction artifacts."""

import json
import re
import copy

TE_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_te.json'
EN_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def clean_content(text):
    """Remove OCR/PDF artifacts from Telugu content text."""
    
    # 1. Remove specific known garbage sequences (page number + fragment combos)
    # Pattern: Telugu fragment + number + Telugu fragment (page boundary garbage)
    # e.g., "త్ 5 ఆం అ, ౨ఇరి." or "౮ ౮ చ," or "ల్ని 17 టం" or "ణి శ 18 చ్"
    # These are short garbage fragments: a few Telugu chars + digits + a few Telugu chars
    text = re.sub(r'త్ 5 ఆం అ, ౨ఇరి\.', '', text)
    text = re.sub(r'౮ ౮ చ,\s*', '', text)
    text = re.sub(r'ల్ని \d+ టం\s*', '', text)
    text = re.sub(r'ణి శ \d+ చ్\s*', '', text)
    
    # Generic pattern: 1-3 Telugu chars + space + 1-3 digit number + space + 1-3 Telugu chars
    # at sentence/paragraph boundaries (these are page number artifacts)
    # Be careful not to remove legitimate numbers like years (1910, 1700, etc.)
    text = re.sub(r'(?<=[\u0C3E-\u0C56।.!?])\s+[\u0C00-\u0C7F]{1,3}\s+\d{1,2}\s+[\u0C00-\u0C7F]{1,3}\s+(?=[\u0C05-\u0C39])', ' ', text)
    
    # 2. Remove stray single Telugu characters at paragraph/sentence boundaries
    # These are fragments from page breaks: "శ్ తరువాత" → "తరువాత"
    # Pattern: after sentence-ending punct or newline, a single Telugu char (possibly with virama) then space
    text = re.sub(r'(?<=\.)\s+[\u0C00-\u0C7F]్?\s+(?=[\u0C05-\u0C39])', ' ', text)
    text = re.sub(r'(?<=\n)\s*[\u0C00-\u0C7F]్?\s+(?=[\u0C05-\u0C39])', '', text)
    
    # After comma + space, stray char
    text = re.sub(r',\s+[\u0C00-\u0C7F]్\s+(?=[\u0C05-\u0C39])', ', ', text)
    
    # 3. Remove stray "ళ్" at end of paragraphs (before \n\n)
    text = re.sub(r'\s+ళ్\s*(?=\n|$)', '', text)
    text = re.sub(r'\s+శ్\s*(?=\n|$)', '', text)
    text = re.sub(r'\s+ః\s*(?=\n|$)', '', text)
    text = re.sub(r'\s+చ్\s*(?=\n|$)', '', text)
    
    # 4. Remove stray quotes and underscores used as PDF artifacts
    # " appearing randomly in middle of sentences (not around dialogue)
    text = re.sub(r'\s+"(?=\s+[\u0C05-\u0C39])', ' ', text)
    text = re.sub(r'(?<=[\u0C3E-\u0C56])\s+"(?=\s)', ' ', text)
    # Stray underscores
    text = re.sub(r'\s+_\s+', ' ', text)
    
    # 5. Remove stray "వొ" (OCR artifact for some other word)
    text = re.sub(r'\bవొ\s+(?=[\u0C05-\u0C39])', '', text)
    
    # 6. Remove embedded page numbers that appear as standalone numbers
    # Pattern: number on its own between Telugu text (not years like 1910, 1700, etc.)
    # Only remove 2-digit numbers that look like page numbers (17-99) when isolated
    text = re.sub(r'(?<=[\u0C3E-\u0C56।.!?])\s+\d{1,2}\s+(?=[\u0C05-\u0C39])', ' ', text)
    
    # 7. Remove "౫" (Telugu digit 5) when used as stray artifact  
    text = re.sub(r'\s+౫\s+(?=[\u0C05-\u0C39])', ' ', text)
    text = re.sub(r'(?<=[\u0C3E-\u0C56])\s+౫\s*(?=\n)', '', text)
    
    # 8. Remove "ం" and similar stray anusvara at line starts
    text = re.sub(r'(?<=\n)\s*ం\s+"?\s*(?=[\u0C05-\u0C39])', '', text)
    
    # 9. Remove "1" at end of content (page artifacts)  
    text = re.sub(r'\s+1\s*$', '', text)
    
    # 10. Remove stray "క" at word boundaries when it's isolated
    # "1700 క సంవత్సరములో" → "1700 సంవత్సరములో"
    text = re.sub(r'(\d{4})\s+క\s+', r'\1 ', text)
    
    # 11. Remove "శ్రీ సాయినాధాయ నమః" prefix artifacts from content start
    # (these belong in heading, not content)
    
    # 12. Remove "లః" and similar stray combos
    text = re.sub(r'\s+లః\s+', ' ', text)
    
    # 13. Clean up multiple spaces
    text = re.sub(r'  +', ' ', text)
    
    # 14. Clean up multiple newlines (max 2)
    text = re.sub(r'\n{3,}', '\n\n', text)
    
    # 15. Clean trailing/leading whitespace on lines
    lines = text.split('\n')
    lines = [line.strip() for line in lines]
    text = '\n'.join(lines)
    
    # 16. Remove empty lines at start/end
    text = text.strip()
    
    return text


def clean_title(title, ch_num, en_title=""):
    """Clean up chapter title."""
    # Remove "ఎ " prefix (artifact from "ఓెం" getting mangled)
    title = re.sub(r'^ఎ\s+', '', title)
    
    # Remove "(." prefix
    title = re.sub(r'\(\.\s*', '', title)
    
    # Remove trailing "1" or other single digits
    title = re.sub(r'\s+\d\s*$', '', title)
    
    # Remove "ళ్‌" and similar stray characters
    title = re.sub(r'ళ్‌', '', title)
    title = re.sub(r'ల్ని\s+\d+\s+టం', '', title)
    
    # Remove "!" artifact
    title = re.sub(r'\s*!\s*', ' ', title)
    
    # Remove "న్‌" artifacts
    title = re.sub(r'న్‌\s*', '', title)
    
    # Remove chapter preamble from title if it duplicates heading
    # e.g., "జీవిత చరిత్రము రెండవ అధ్యాయము" should be removed if it's just repeating
    title = re.sub(r'^.*?అధ్యాయము\s*', '', title)
    
    # Remove "మొదటిరోజు పారాయణము సమాప్తము" type artifacts
    title = re.sub(r'మొదటిరోజు పారాయణము సమాప్తము\.?\s*', '', title)
    title = re.sub(r'రెండవరోజు పారాయణము సమాప్తము\.?\s*', '', title)
    
    # Remove stray "శ" at boundaries
    title = re.sub(r'\s+శ\s+', ' ', title)
    title = re.sub(r'^శ\s+', '', title)
    
    # Remove "5 " prefix artifact
    title = re.sub(r'^\d+\s+', '', title)
    
    # Clean up multiple spaces
    title = re.sub(r'\s+', ' ', title).strip()
    
    # Remove leading/trailing punctuation artifacts
    title = title.strip('(./"\'! ')
    
    return title


def clean_heading(heading):
    """Clean chapter heading."""
    # Already seems mostly clean, just ensure format
    heading = heading.strip()
    return heading


def main():
    te_data = load_json(TE_PATH)
    en_data = load_json(EN_PATH)
    
    cleaned = copy.deepcopy(te_data)
    
    for i, ch in enumerate(cleaned):
        en_ch = en_data[i] if i < len(en_data) else {}
        
        # Clean content
        original_content = ch['content']
        ch['content'] = clean_content(original_content)
        
        # Clean title
        original_title = ch['title']
        ch['title'] = clean_title(original_title, ch['number'], en_ch.get('title', ''))
        
        # Clean heading
        ch['heading'] = clean_heading(ch['heading'])
        
        # Report changes
        content_diff = len(original_content) - len(ch['content'])
        if content_diff != 0 or original_title != ch['title']:
            print(f"Ch {ch['number']}: content reduced by {content_diff} chars")
            if original_title != ch['title']:
                print(f"  Title: [{original_title[:60]}] → [{ch['title'][:60]}]")
    
    # Save
    with open(TE_PATH, 'w', encoding='utf-8') as f:
        json.dump(cleaned, f, ensure_ascii=False, indent=2)
    
    print(f"\nSaved cleaned Telugu to {TE_PATH}")
    
    # Verify - rescan for remaining issues
    print("\n=== Post-cleanup scan ===")
    for ch in cleaned:
        content = ch['content']
        stray = re.findall(r'(?:^|\n\n|\.\s+)[\u0C00-\u0C7F]్?\s(?=[\u0C05-\u0C39])', content)
        if stray:
            print(f"  Ch {ch['number']}: {len(stray)} remaining stray chars")
            for s in stray[:3]:
                idx = content.find(s)
                ctx = content[max(0,idx-20):idx+30]
                print(f"    ...{ctx.replace(chr(10),' ')}...")


if __name__ == '__main__':
    main()
