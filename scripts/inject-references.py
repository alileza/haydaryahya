#!/usr/bin/env python3
"""Parse Rujukan PDF and inject clickable reference popups into the Islam article."""

import json
import re
import sys

def parse_rujukan(text):
    """Parse numbered references from the Rujukan PDF text."""
    refs = {}
    # Split into blocks by double newline
    text = text.replace("\f", "\n")
    # Match entries starting with N) or (N) pattern
    # Each entry: number, surah info, arabic text, translation
    entries = re.split(r'\n(?=\(?(\d{1,2})\)\s)', text)

    current_num = None
    current_lines = []

    for chunk in entries:
        m = re.match(r'\(?(\d{1,2})\)\s*(.*)', chunk, re.DOTALL)
        if m:
            if current_num is not None:
                refs[current_num] = _clean_entry(current_lines)
            current_num = int(m.group(1))
            current_lines = [m.group(2).strip()]
        elif current_num is not None:
            current_lines.append(chunk.strip())

    if current_num is not None:
        refs[current_num] = _clean_entry(current_lines)

    return refs


def _clean_entry(lines):
    """Clean a reference entry to just the surah name and Indonesian translation."""
    full = "\n".join(lines).strip()
    # Remove page separators
    full = re.sub(r'={3,}.*', '', full)

    # Try to extract surah reference and translation
    out_lines = []
    for line in full.split("\n"):
        line = line.strip()
        if not line:
            continue
        # Skip lines that are purely Arabic (RTL characters)
        if re.fullmatch(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF\s\u200F\u200E\u064B-\u065F.,;:\-()​]+', line):
            continue
        out_lines.append(line)

    result = " ".join(out_lines).strip()
    # Collapse whitespace
    result = re.sub(r'\s+', ' ', result)
    # Truncate very long entries
    if len(result) > 500:
        result = result[:497] + "..."
    return result


def inject_refs_into_article(article_md, refs):
    """Replace (N) references in article text with clickable popup spans."""
    def replacer(m):
        num = int(m.group(1))
        if num in refs:
            return f'<span class="ref-link" data-ref="{num}">({num})</span>'
        return m.group(0)

    # Match (N) where N is 1-38, typically at end of sentence or after a verse citation
    result = re.sub(r'\((\d{1,2})\)', replacer, article_md)

    # Append reference data as a script tag
    ref_json = json.dumps(refs, ensure_ascii=False)
    result += f'\n\n<div id="ref-data" data-refs=\'{ref_json}\' style="display:none"></div>\n'

    return result


def main():
    rujukan_file = sys.argv[1]
    article_file = sys.argv[2]

    with open(rujukan_file, "r") as f:
        rujukan_text = f.read()

    refs = parse_rujukan(rujukan_text)

    with open(article_file, "r") as f:
        article = f.read()

    # Split front matter from body
    parts = article.split("+++", 2)
    if len(parts) < 3:
        print("Could not parse front matter", file=sys.stderr)
        sys.exit(1)

    front_matter = parts[1]
    body = parts[2]

    new_body = inject_refs_into_article(body, refs)
    result = f"+++{front_matter}+++{new_body}"

    with open(article_file, "w") as f:
        f.write(result)


if __name__ == "__main__":
    main()
