#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PDF_DIR="$ROOT_DIR/pdf"
POSTS_DIR="$ROOT_DIR/content/posts"
STATIC_PDF_DIR="$ROOT_DIR/static/pdf"
META_FILE="$ROOT_DIR/article-meta.tsv"

mkdir -p "$POSTS_DIR" "$STATIC_PDF_DIR"
find "$POSTS_DIR" -type f -name '*.md' -delete
rm -f "$STATIC_PDF_DIR"/*.pdf

slugify() {
  local input="$1"
  printf '%s' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\.[Pp][Dd][Ff]$//' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g'
}

escape_toml() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

url_encode() {
  jq -rn --arg v "$1" '$v|@uri'
}

file_mtime_iso() {
  local file_path="$1"
  if stat -f "%Sm" -t "%Y-%m-%d" "$file_path" >/dev/null 2>&1; then
    stat -f "%Sm" -t "%Y-%m-%d" "$file_path"
  else
    stat -c "%y" "$file_path" | cut -d' ' -f1
  fi
}

read_meta_override() {
  local file_name="$1"
  local column="$2"
  [ -f "$META_FILE" ] || return 0
  awk -F'\t' -v f="$file_name" -v c="$column" '$1==f {print $c; exit}' "$META_FILE"
}

RUJUKAN_TEXT=""

while IFS= read -r -d '' pdf_path; do
  file_name="$(basename "$pdf_path")"

  # Skip Rujukan — it's a reference appendix, not a standalone article
  if [[ "$file_name" == "Rujukan Ayat Sesuai Urutan.pdf" ]]; then
    cp "$pdf_path" "$STATIC_PDF_DIR/$file_name"
    RUJUKAN_TEXT="$(pdftotext "$pdf_path" - 2>/dev/null || true)"
    continue
  fi

  title="${file_name%.pdf}"
  slug="$(slugify "$file_name")"
  encoded_name="$(url_encode "$file_name")"

  file_date="$(file_mtime_iso "$pdf_path")"
  meta_author="$(pdfinfo "$pdf_path" 2>/dev/null | awk -F': *' '/^Author:/{print $2; exit}' | sed -E 's/^ +| +$//g')"
  meta_date="$(pdfinfo -isodates "$pdf_path" 2>/dev/null | awk -F': *' '/^(CreationDate|ModDate):/{print $2; exit}' | sed -E 's/^ +| +$//g')"
  meta_date="${meta_date%%T*}"

  override_author="$(read_meta_override "$file_name" 2)"
  override_date="$(read_meta_override "$file_name" 3)"
  override_title="$(read_meta_override "$file_name" 4)"

  author_name="${override_author:-${meta_author:-Haydar Yahya}}"
  authored_date="${override_date:-${meta_date:-$file_date}}"
  [ -n "$author_name" ] || author_name="Haydar Yahya"
  [ -n "$authored_date" ] || authored_date="$file_date"
  [ -n "$override_title" ] && title="$override_title"

  text_content="$(pdftotext "$pdf_path" - 2>/dev/null || true)"

  body_markdown="$({
    printf '%s' "$text_content" | python3 -c '
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
    clean_lines.append(line)

text = "\n".join(clean_lines)
blocks = [b.strip() for b in re.split(r"\n\s*\n+", text) if b.strip()]

def sentence_chunks(block: str):
    block = re.sub(r"\s+", " ", block).strip()
    if not block:
        return []
    if len(block) <= 360:
        return [block]
    # Split long OCR blocks into readable chunks at sentence boundaries.
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9\"“(])", block)
    parts = [p.strip() for p in parts if p.strip()]
    if len(parts) <= 1:
        return [block]
    chunks = []
    buf = ""
    for sentence in parts:
        candidate = f"{buf} {sentence}".strip() if buf else sentence
        if len(candidate) > 360 and buf:
            chunks.append(buf)
            buf = sentence
        else:
            buf = candidate
    if buf:
        chunks.append(buf)
    return chunks

for block in blocks:
    for para in sentence_chunks(block):
        print(para)
        print()
'
  })"

  cp "$pdf_path" "$STATIC_PDF_DIR/$file_name"

  read_stats="$(printf '%s' "$body_markdown" | python3 -c '
import sys, math
lines = [l.strip() for l in sys.stdin if l.strip()]
text = " ".join(lines)
excerpt = " ".join(lines[:3])[:160].strip()
idx = excerpt.rfind(" ")
if idx > 0 and len(" ".join(lines[:3])) > 160:
    excerpt = excerpt[:idx] + "\u2026"
words = len(text.split())
mins = max(1, math.ceil(words / 265))
print(f"{excerpt}\t{mins}")
')"
  excerpt="$(printf '%s' "$read_stats" | cut -f1)"
  read_min="$(printf '%s' "$read_stats" | cut -f2)"

  cat > "$POSTS_DIR/$slug.md" <<POST_MD
+++
title = "$(escape_toml "$title")"
author = "$(escape_toml "$author_name")"
date = "$(escape_toml "$authored_date")"
pdf = "/pdf/${encoded_name}"
excerpt = "$(escape_toml "$excerpt")"
readingTime = $read_min
+++

${body_markdown}
POST_MD

done < <(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' -print0)

# Inject Rujukan references as clickable popups into the Islam article
ISLAM_POST="$POSTS_DIR/islam-nama-generik-semua-agama-samawi.md"
if [[ -n "$RUJUKAN_TEXT" && -f "$ISLAM_POST" ]]; then
  RUJUKAN_TMP="$(mktemp)"
  printf '%s' "$RUJUKAN_TEXT" > "$RUJUKAN_TMP"
  python3 "$ROOT_DIR/scripts/inject-references.py" "$RUJUKAN_TMP" "$ISLAM_POST"
  rm -f "$RUJUKAN_TMP"
fi

echo "Generated Hugo content from PDFs."
