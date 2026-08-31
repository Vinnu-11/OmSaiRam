#!/usr/bin/env python3
"""Second pass cleanup for Telugu Sai Satcharita - fix remaining artifacts."""

import json
import re
import copy

TE_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_te.json'
EN_PATH = '/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content/satcharita_en.json'

def load_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def clean_content_pass2(text):
    """Second pass content cleanup."""
    
    # 1. Remove chapter preamble at content start
    # Pattern: "ఎ జీవిత చరిత్రము XXXవ అధ్యాయము" or similar
    text = re.sub(r'^(?:ఎ|న్|నే|న|ల్ని|॥్)\s+(?:సాయిబాబా\s+)?(?:ల్?\s+)?(?:శ\s+)?(?:ఇ\s+)?జీవిత\s*చరిత్రము\s+', '', text)
    text = re.sub(r'^(?:జీవితచరిత్రము\s+)', '', text)
    
    # Remove "నాలుగవ అధ్యాయము" etc at start
    text = re.sub(r'^[\u0C00-\u0C7F]+వ\s+అధ్యాయము\s+', '', text)
    # Remove "మొదటి అధ్యాయము" 
    text = re.sub(r'^మొదటి\s+అధ్యాయము\s+', '', text)
    # "అయిదవ అధ్యాయము" etc
    text = re.sub(r'^అయిదవ\s+అధ్యాయము\s+', '', text)
    
    # 2. Remove remaining stray single Telugu chars at sentence/paragraph boundaries
    # Be more aggressive with specific known artifact characters
    # After period+space: stray char + space + Telugu word
    text = re.sub(r'(?<=\.)\s+([ఉగమనఈఆశళచఃతదపబలవసహకణజటడభయర])\s+(?=[\u0C05-\u0C39])', ' ', text)
    
    # After newline: stray single char
    text = re.sub(r'(?<=\n)\s*([ఉగమనశళచఃతదపబలవసహఈఆకణజటడభయర])\s+(?=[\u0C05-\u0C39])', '', text)
    
    # 3. Remove "ఎ " at content start (artifact from "ఓెం" mangling)
    text = re.sub(r'^ఎ\s+', '', text)
    
    # 4. Remove stray "ఇ " between words at content start 
    text = re.sub(r'^(\S+\s+\S+\s+)ఇ\s+', r'\1', text)
    
    # 5. Remove specific garbage sequences that survived first pass
    text = re.sub(r'క్షిాకి\.\s*', '', text)
    text = re.sub(r'కిని ంచిాకి\.\s*', '', text)
    text = re.sub(r'జిని వినిల చికి\.\s*', '', text)
    
    # 6. Remove stray "ళ్‌" 
    text = re.sub(r'\s+ళ్‌', '', text)
    
    # 7. Remove "(/." and "/." at start of lines
    text = re.sub(r'(?<=\n)\s*[(/]+\.\s*', '', text)
    text = re.sub(r'^[(/]+\.\s*', '', text)
    
    # 8. Remove stray " at sentence boundaries (not around dialogue)
    text = re.sub(r'\s+"(?=\s+[\u0C05-\u0C39])', ' ', text)
    
    # 9. Remove "30" that appears as page number in middle of sentence
    # "శాశ్వతమైన 30 తృప్తిని" → "శాశ్వతమైన తృప్తిని"
    text = re.sub(r'(?<=[\u0C3E-\u0C56])\s+\d{2}\s+(?=[\u0C05-\u0C39])', ' ', text)
    
    # 10. Clean "న్" prefix at start (from "ఓెం" artifacts)
    text = re.sub(r'^న్\s+', '', text)
    text = re.sub(r'^నే\s+', '', text)
    
    # 11. Remove "పారాయణము సమాప్తము" artifacts
    text = re.sub(r'[\u0C00-\u0C7F]+రోజు పారాయణము సమాప్తము\.?\s*', '', text)
    
    # 12. Remove stray "॥" 
    text = re.sub(r'(?<!\S)॥్?\s*', '', text)
    
    # 13. Clean up formatting
    text = re.sub(r'  +', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    lines = text.split('\n')
    lines = [line.strip() for line in lines]
    text = '\n'.join(lines).strip()
    
    return text


def fix_title(title, ch_num, en_data):
    """Fix title - use English reference if Telugu title is empty or too short."""
    # Remove trailing stray chars
    title = re.sub(r'\s+[ఆఇఉఈళశచఃగమనలతదపబవసహకణ]$', '', title)
    title = re.sub(r'\s+"$', '', title)
    
    # Remove "ల్‌" artifacts
    title = re.sub(r'^ల్‌\s*', '', title)
    title = re.sub(r'\s+ల్‌\s*', ' ', title)
    
    # Remove stray "ని" at end
    title = re.sub(r'\s+ని$', '', title)
    
    # Remove "స " at start
    title = re.sub(r'^స\s+', '', title)
    
    # Remove "న " at start  
    title = re.sub(r'^న\s+', '', title)
    
    # Remove "గ " at start
    title = re.sub(r'^గ\s+', '', title)
    
    # Remove "లి" when it's the whole title
    if title.strip() in ('లి', 'లు', ''):
        title = ''
    
    # Remove "%" prefix
    title = re.sub(r'^%\s*', '', title)
    title = re.sub(r'\s+%\s*', ' ', title)
    
    # Remove "న 122 న సాయిబాబా ఎ జీవిత చరిత్రము" type garbage
    title = re.sub(r'న\s+\d+\s+న\s+సాయిబాబా\s+ఎ\s+జీవిత\s+చరిత్రము', '', title)
    
    # Remove "లు " at start
    title = re.sub(r'^లు\s+', '', title)
    
    # Remove "శ్రీ సాయిబాబా" from title start (it's in heading)
    title = re.sub(r'^శ్రీ\s+సాయిబాబా\s*$', '', title)
    
    # Remove stray "1 ॥ శ్రీ న సాయిబాబా" type text
    title = re.sub(r'\d+\s*॥?\s*శ్రీ\s*న?\s*సాయిబాబా.*$', '', title)
    
    title = title.strip(' .,;:')
    
    return title


def fix_content_start(content, ch_num):
    """Remove chapter header repetition from content start."""
    # Remove "శ్రీ సాయినాధాయ నమః శ్రీ సాయిబాబా జీవిత చరిత్రము మొదటి అధ్యాయము"
    content = re.sub(r'^శ్రీ సాయినాధాయ నమః\s+శ్రీ సాయిబాబా\s+జీవిత చరిత్రము\s+మొదటి అధ్యాయము\s+', '', content)
    
    # Remove generic chapter header pattern from content start
    # "జీవిత చరిత్రము XXXవ అధ్యాయము"
    content = re.sub(r'^.*?అధ్యాయము\s+', '', content, count=1)
    
    return content


def derive_title_from_content(content, ch_num, en_title):
    """Extract a meaningful title from content if title is empty."""
    # The content usually starts with a description line before the first ## heading
    first_line = content.split('\n')[0].strip()
    # Get text before first period or ## heading
    if '##' in first_line:
        first_line = first_line.split('##')[0].strip()
    # Limit to reasonable length
    if len(first_line) > 200:
        first_line = first_line[:200]
    return first_line


def main():
    te_data = load_json(TE_PATH)
    en_data = load_json(EN_PATH)
    
    cleaned = copy.deepcopy(te_data)
    
    for i, ch in enumerate(cleaned):
        en_ch = en_data[i] if i < len(en_data) else {}
        
        # Second pass content cleanup
        ch['content'] = clean_content_pass2(ch['content'])
        
        # Fix titles
        ch['title'] = fix_title(ch['title'], ch['number'], en_data)
        
        # If title is empty, derive from content
        if not ch['title'] or len(ch['title']) < 5:
            ch['title'] = derive_title_from_content(ch['content'], ch['number'], en_ch.get('title', ''))
        
        # Report
        if ch['title'] != te_data[i]['title']:
            print(f"Ch {ch['number']} title: [{ch['title'][:80]}]")
    
    # Save
    with open(TE_PATH, 'w', encoding='utf-8') as f:
        json.dump(cleaned, f, ensure_ascii=False, indent=2)
    
    print(f"\nSaved to {TE_PATH}")
    
    # Final verification
    print("\n=== Final scan ===")
    issues_found = False
    for ch in cleaned:
        content = ch['content']
        stray = re.findall(r'(?:^|\n\n|\.\s+)[\u0C00-\u0C7F]్?\s(?=[\u0C05-\u0C39])', content)
        stray_punct = re.findall(r'\s["_]\s', content)
        
        if stray or stray_punct:
            issues_found = True
            if stray:
                print(f"  Ch {ch['number']}: {len(stray)} stray chars remaining")
                for s in stray[:2]:
                    idx = content.find(s)
                    ctx = content[max(0,idx-15):idx+25]
                    print(f"    ...{ctx.replace(chr(10),' ')}...")
            if stray_punct:
                print(f"  Ch {ch['number']}: {len(stray_punct)} stray punct remaining")
        
        if not ch['title'] or len(ch['title']) < 5:
            issues_found = True
            print(f"  Ch {ch['number']}: title too short: [{ch['title']}]")
    
    if not issues_found:
        print("  All clean!")


if __name__ == '__main__':
    main()
