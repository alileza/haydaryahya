#!/usr/bin/env python3
"""Convert raw PDF text to clean markdown with blockquote detection."""
import re
import sys

text = sys.stdin.read().replace("\r\n", "\n").replace("\r", "\n").strip()
if not text:
    print("(No extractable text was found in this PDF.)")
    raise SystemExit

# Remove form-feed page markers and obvious standalone page numbers.
text = text.replace("\f", "\n")
clean_lines = []
for raw in text.split("\n"):
    line = raw.strip()
    if not line:
        clean_lines.append("")
        continue
    if re.fullmatch(r"\d{1,3}", line):
        continue
    if line.startswith("Total output lines:"):
        continue
    # Remove timestamp lines like "01.59, February 15 - 2018"
    if re.fullmatch(r"\d{1,2}\.\d{2},?\s+\w+\s+\d{1,2}\s*-?\s*\d{4}", line):
        continue
    # Remove decorative separator lines (=====, ------, etc.)
    if re.fullmatch(r"[=\-_*]{3,}.*", line):
        clean_lines.append("")
        continue
    # Strip leading/trailing separator runs from lines
    line = re.sub(r"^[=\-]{3,}\s*", "", line)
    line = re.sub(r"\s*[=\-]{3,}$", "", line)
    clean_lines.append(line)

text = "\n".join(clean_lines)
blocks = [b.strip() for b in re.split(r"\n\s*\n+", text) if b.strip()]

DQ = '"'
LQ = "\u201c"
RQ = "\u201d"
LA = "\u00ab"
RA = "\u00bb"


def sentence_chunks(block):
    block = re.sub(r"\s+", " ", block).strip()
    if not block:
        return []
    if len(block) <= 360:
        return [block]
    # Split long OCR blocks into readable chunks at sentence boundaries.
    parts = re.split(r'(?<=[.!?])\s+(?=[A-Z0-9""\u201c(])', block)
    parts = [p.strip() for p in parts if p.strip()]
    if len(parts) <= 1:
        return [block]
    chunks = []
    buf = ""
    for sentence in parts:
        candidate = (buf + " " + sentence).strip() if buf else sentence
        if len(candidate) > 360 and buf:
            chunks.append(buf)
            buf = sentence
        else:
            buf = candidate
    if buf:
        chunks.append(buf)
    return chunks


def is_full_quote(para):
    """Check if entire paragraph is a standalone quote."""
    s = para.strip()
    if not s:
        return False
    stripped = s.rstrip(".!?)")
    # Entirely wrapped in smart quotes
    if s.startswith(LQ) and stripped.endswith(RQ):
        return True
    # Entirely wrapped in straight double quotes
    if s.startswith(DQ) and stripped.endswith(DQ) and len(stripped) > 2:
        return True
    return False


# Pattern: intro text :"quoted text" trailing text
# We split: intro as normal paragraph, quoted part as blockquote, trailing as normal
INLINE_QUOTE_RE = re.compile(
    r'(.*?)\s*:\s*'           # prefix before the colon-quote
    r'(["\u201c])'            # opening quote
    r'(.+?)'                  # quoted content
    r'(["\u201d])'            # closing quote
    r'(.*)',                   # trailing text
    re.DOTALL
)


def emit_with_inline_quotes(para):
    """Split paragraph at :"..." patterns, emitting quotes as blockquotes."""
    s = para.strip()
    if not s:
        return

    # Check for :"..." pattern with enough quoted content to be meaningful
    m = INLINE_QUOTE_RE.match(s)
    if m:
        prefix = m.group(1).strip()
        quote_text = m.group(3).strip()
        suffix = m.group(5).strip()

        # Only blockquote if the quoted part is substantial (>40 chars)
        if len(quote_text) > 40:
            if prefix:
                print(prefix)
                print()
            print("> " + quote_text)
            print()
            # Skip trivial suffixes (lone punctuation, very short fragments)
            if suffix and len(suffix.strip(".,;:!? ")) > 3:
                print(suffix)
                print()
            return

    # No inline quote found, print normally
    print(s)
    print()


for block in blocks:
    for para in sentence_chunks(block):
        if is_full_quote(para):
            print("> " + para)
            print()
        else:
            emit_with_inline_quotes(para)
