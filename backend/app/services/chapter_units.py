"""Language-independent reading units, retaining Marathi chapter numbering.

Translations combine these ranges. A group schedules the whole range once;
Marathi readers read the original adhyayas together in that same assignment.
Chapter 50 stays separate because the reader falls back to the Marathi text.
"""

TOTAL_CHAPTERS = 53
COMBINED_CHAPTERS = {16: 17, 18: 19, 43: 44, 51: 53}


def chapter_start(number: int) -> int:
    for start, end in COMBINED_CHAPTERS.items():
        if start <= number <= end:
            return start
    return number


def chapter_end(number: int) -> int:
    start = chapter_start(number)
    return COMBINED_CHAPTERS.get(start, start)


def chapter_label(number: int) -> str:
    start, end = chapter_start(number), chapter_end(number)
    return str(start) if start == end else f"{start}-{end}"


def reading_units(total_chapters: int) -> list[int]:
    return [n for n in range(1, total_chapters + 1) if chapter_start(n) == n]


def unit_position(number: int, units: list[int], total_chapters: int) -> int:
    """One-based slot position; preserve out-of-book positions for remainders."""
    if number > total_chapters:
        return len(units) + number - total_chapters
    return units.index(chapter_start(number)) + 1


def unit_number(position: int, units: list[int], total_chapters: int) -> int:
    if 1 <= position <= len(units):
        return units[position - 1]
    return total_chapters + position - len(units)