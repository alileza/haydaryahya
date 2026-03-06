# haydaryahya.com

Kumpulan tulisan Haydar Yahya — a Hugo static site that converts PDF articles into a Medium-style reading experience.

**Live site:** [haydaryahya.com](https://haydaryahya.com)

## How it works

### PDF to Article pipeline

1. Place PDF files in the `pdf/` directory
2. Run `bash scripts/build-content.sh` — this:
   - Extracts text from each PDF using `pdftotext`
   - Pipes text through `scripts/pdf-to-markdown.py` which cleans up the text (strips page numbers, separators, timestamps), chunks long paragraphs, and converts inline quotes (`:"..."`) to markdown blockquotes
   - Generates an excerpt (~160 chars) and reading time estimate (words/265)
   - Looks up metadata overrides from `article-meta.tsv` (author, date, title, summary)
   - Writes Hugo markdown to `content/posts/<slug>.md` with TOML front matter
3. **Special case:** `Rujukan Ayat Sesuai Urutan.pdf` is not its own article — instead `scripts/inject-references.py` parses its numbered verse references and injects them as clickable popup spans into the "Islam, Nama Generik" article

### article-meta.tsv

TSV file with 5 columns for overriding PDF metadata:

| Column | Field |
|--------|-------|
| 1 | PDF filename |
| 2 | Author |
| 3 | Date (YYYY-MM-DD) |
| 4 | Title override |
| 5 | Summary (hand-crafted key takeaways) |

### Building the site

```bash
# Regenerate markdown from PDFs
bash scripts/build-content.sh

# Build Hugo site
hugo

# Local preview
hugo server
```

### Deploying

Push to `main` — GitHub Actions (`.github/workflows/pages.yml`) builds Hugo and deploys to GitHub Pages.

## Project structure

```
pdf/                        # Source PDF files
scripts/
  build-content.sh          # Main build script (PDF -> Hugo markdown)
  pdf-to-markdown.py        # Text cleanup, paragraph chunking, quote detection
  inject-references.py      # Injects Rujukan verse popups into Islam article
article-meta.tsv            # Metadata overrides (author, date, title, summary)
content/posts/              # Generated Hugo markdown (do not edit by hand)
layouts/
  _default/baseof.html      # Base template (navbar, fonts, OG tags, analytics)
  _default/single.html      # Article template (summary box, share buttons, nav)
  index.html                # Homepage feed
static/
  css/styles.css            # All styles (Medium-inspired)
  favicon.svg               # HY monogram favicon
  og-image.png              # OpenGraph image
hugo.toml                   # Site config
```
