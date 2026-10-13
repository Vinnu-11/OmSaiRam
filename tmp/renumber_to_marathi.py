#!/usr/bin/env python3
"""Renumber the 47-unit (Gunaji-structured) translations to Marathi adhyaya numbering.

Gunaji merges 16-17, 18-19, 43-44; folds Marathi 50 into 39; and his final
unit ("50") is Marathi 51 plus the epilogue (Marathi 52-53).
`number` becomes the first Marathi adhyaya covered; `chapterLabel` the range.
"""

import glob
import json
import os

CONTENT = "/home/vdamarl/pers/OmSaiRam/om_sai_ram/assets/content"

for path in sorted(glob.glob(f"{CONTENT}/satcharita_*.json")):
    if path.endswith("_mr.json"):
        continue
    chapters = json.load(open(path, encoding="utf-8"))
    if chapters[-1]["chapterLabel"] != "50" or len(chapters) != 47:
        print("skip (already converted?)", os.path.basename(path))
        continue
    for c in chapters:
        label = "51-53" if c["chapterLabel"] == "50" else c["chapterLabel"]
        c["number"] = c["id"] = int(label.split("-")[0])
        c["chapterLabel"] = label
        c["heading"] = f'{c["heading"].rsplit(" ", 1)[0]} {label}'
    json.dump(chapters, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("renumbered", os.path.basename(path))
