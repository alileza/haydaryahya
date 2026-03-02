#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PDF_DIR="$ROOT_DIR/pdf"
POSTS_DIR="$ROOT_DIR/posts"

mkdir -p "$POSTS_DIR"

slugify() {
  local input="$1"
  printf '%s' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\.[Pp][Dd][Ff]$//' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g'
}

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

url_encode() {
  jq -rn --arg v "$1" '$v|@uri'
}

cat > "$ROOT_DIR/index.html" <<'INDEX_HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Haydar Yahya Writings</title>
  <meta name="description" content="A collection of writings by Haydar Yahya." />
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <main class="container">
    <header class="hero">
      <h1>Haydar Yahya</h1>
      <p>Collected writings, available as web pages and original PDFs.</p>
    </header>

    <section>
      <h2>Articles</h2>
      <ul class="cards">
INDEX_HEAD

while IFS= read -r -d '' pdf_path; do
  file_name="$(basename "$pdf_path")"
  title="${file_name%.pdf}"
  slug="$(slugify "$file_name")"
  encoded_name="$(url_encode "$file_name")"

  text_content="$(pdftotext "$pdf_path" - 2>/dev/null || true)"
  if [ -z "$text_content" ]; then
    text_content="(No extractable text was found in this PDF.)"
  fi

  escaped_title="$(printf '%s' "$title" | html_escape)"

  cat > "$POSTS_DIR/$slug.html" <<POST_PAGE
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escaped_title}</title>
  <link rel="stylesheet" href="../styles.css" />
</head>
<body>
  <main class="container article">
    <p><a href="../index.html">Home</a></p>
    <h1>${escaped_title}</h1>
    <p><a href="../pdf/${encoded_name}">Open original PDF</a></p>
    <pre>
$(printf '%s\n' "$text_content" | html_escape)
    </pre>
  </main>
</body>
</html>
POST_PAGE

  cat >> "$ROOT_DIR/index.html" <<INDEX_CARD
        <li class="card">
          <h3>${escaped_title}</h3>
          <p><a href="posts/${slug}.html">Read as webpage</a></p>
          <p><a href="pdf/${encoded_name}">Open PDF</a></p>
        </li>
INDEX_CARD

done < <(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' -print0)

cat >> "$ROOT_DIR/index.html" <<'INDEX_FOOT'
      </ul>
    </section>
  </main>
</body>
</html>
INDEX_FOOT

echo "Site generated: index.html and posts/*.html"
