// Mirrors backend/app/services/chapter_units.py, independent of language/SQL IDs.
const COMBINED = new Map([[16, 17], [18, 19], [43, 44], [51, 53]]);

export function canonicalUnit(chapterNumber) {
    if (!Number.isSafeInteger(chapterNumber) || chapterNumber < 1 || chapterNumber > 53) {
        throw new Error('Chapter number must be an integer from 1 to 53.');
    }
    let start = chapterNumber;
    for (const [first, last] of COMBINED) {
        if (chapterNumber >= first && chapterNumber <= last) start = first;
    }
    const end = COMBINED.get(start) ?? start;
    return Object.freeze({
        unitKey: start === end ? String(start) : `${start}-${end}`,
        chapterStart: start,
        chapterEnd: end,
    });
}

export const CHAPTER_UNITS = Object.freeze(
    Array.from({ length: 53 }, (_, index) => canonicalUnit(index + 1))
        .filter((unit, index) => unit.chapterStart === index + 1),
);