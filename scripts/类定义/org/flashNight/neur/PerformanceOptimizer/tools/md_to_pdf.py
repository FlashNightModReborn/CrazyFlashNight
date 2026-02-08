#!/usr/bin/env python3
"""
Convert paper_cn.md to PDF via HTML + Chrome headless.
Handles: Chinese text, LaTeX math (MathJax v3), GFM tables, images, code blocks.

Usage:
    python tools/md_to_pdf.py                   # default: paper_cn.md -> paper_cn.pdf
    python tools/md_to_pdf.py paper.md out.pdf  # custom input/output
"""

import re
import os
import sys
import json
import base64
import subprocess
import tempfile
import markdown
from pathlib import Path

# ---------------------------------------------------------------------------
# 1. Math protection: shield $...$ and $$...$$ from the Markdown parser
# ---------------------------------------------------------------------------

_MATH_STORE = []

def _store_math(m):
    idx = len(_MATH_STORE)
    _MATH_STORE.append(m.group(0))
    return f"\x00MATH{idx}MATH\x00"

def protect_math(text):
    """Replace math blocks with placeholders before Markdown conversion."""
    _MATH_STORE.clear()
    # Display math first (greedy across lines)
    text = re.sub(r'\$\$(.+?)\$\$', _store_math, text, flags=re.DOTALL)
    # Inline math (non-greedy, single line)
    text = re.sub(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', _store_math, text)
    return text

def restore_math(html):
    """Put math blocks back, wrapped in MathJax-compatible delimiters."""
    def _restore(m):
        idx = int(m.group(1))
        raw = _MATH_STORE[idx]
        if raw.startswith('$$'):
            inner = raw[2:-2].strip()
            return f'<div class="mathjax-display">$${inner}$$</div>'
        else:
            inner = raw[1:-1]
            return f'<span class="mathjax-inline">\\({inner}\\)</span>'
    return re.sub(r'\x00MATH(\d+)MATH\x00', _restore, html)

# ---------------------------------------------------------------------------
# 2. Image embedding: convert local PNG refs to base64 data URIs
# ---------------------------------------------------------------------------

def embed_images(html, base_dir):
    """Replace local image src with base64 data URIs for self-contained HTML."""
    def _embed(m):
        prefix = m.group(1)
        src = m.group(2)
        suffix = m.group(3)
        img_path = Path(base_dir) / src
        if img_path.exists():
            data = img_path.read_bytes()
            ext = img_path.suffix.lower().lstrip('.')
            mime = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
                    'gif': 'image/gif', 'svg': 'image/svg+xml'}.get(ext, 'image/png')
            b64 = base64.b64encode(data).decode()
            return f'{prefix}data:{mime};base64,{b64}{suffix}'
        return m.group(0)  # leave as-is if file not found
    return re.sub(r'(<img\s[^>]*src=["\'])(\./figures/[^"\']+)(["\'])', _embed, html)

# ---------------------------------------------------------------------------
# 3. Markdown -> HTML conversion
# ---------------------------------------------------------------------------

def md_to_html(md_text):
    """Convert Markdown text to HTML body, preserving math."""
    protected = protect_math(md_text)

    html_body = markdown.markdown(
        protected,
        extensions=[
            'tables',
            'fenced_code',
            'codehilite',
            'toc',
            'attr_list',
            'md_in_html',
        ],
        extension_configs={
            'codehilite': {'css_class': 'highlight', 'guess_lang': False},
        }
    )

    html_body = restore_math(html_body)
    return html_body

# ---------------------------------------------------------------------------
# 4. Full HTML document assembly
# ---------------------------------------------------------------------------

CSS = r"""
@page {
    size: A4;
    margin: 25mm 20mm 25mm 20mm;
}

body {
    font-family: "Source Han Serif SC", "Noto Serif CJK SC", "SimSun", "Songti SC",
                 "Times New Roman", serif;
    font-size: 11pt;
    line-height: 1.75;
    color: #1a1a1a;
    max-width: 170mm;
    margin: 0 auto;
    padding: 20px 0;
    text-align: justify;
    hyphens: auto;
}

/* Title */
h1 {
    font-size: 18pt;
    font-weight: bold;
    text-align: center;
    margin-top: 30px;
    margin-bottom: 10px;
    line-height: 1.4;
}

/* Section headings */
h2 {
    font-size: 14pt;
    font-weight: bold;
    margin-top: 28px;
    margin-bottom: 10px;
    border-bottom: 1px solid #ccc;
    padding-bottom: 4px;
    page-break-after: avoid;
}

h3 {
    font-size: 12pt;
    font-weight: bold;
    margin-top: 20px;
    margin-bottom: 8px;
    page-break-after: avoid;
}

h4 {
    font-size: 11pt;
    font-weight: bold;
    margin-top: 16px;
    margin-bottom: 6px;
    page-break-after: avoid;
}

/* Paragraphs */
p {
    margin: 0.6em 0;
    text-indent: 0;
}

/* Abstract / blockquotes */
blockquote {
    margin: 12px 20px;
    padding: 8px 16px;
    border-left: 3px solid #999;
    background: #f9f9f9;
    font-size: 10pt;
    color: #444;
}
blockquote p {
    margin: 4px 0;
}

/* Tables */
table {
    border-collapse: collapse;
    margin: 12px auto;
    font-size: 10pt;
    page-break-inside: avoid;
}
th, td {
    border: 1px solid #666;
    padding: 5px 10px;
    text-align: left;
}
th {
    background: #f0f0f0;
    font-weight: bold;
}

/* Code */
code {
    font-family: "Consolas", "Source Code Pro", monospace;
    font-size: 9.5pt;
    background: #f4f4f4;
    padding: 1px 4px;
    border-radius: 3px;
}
pre {
    background: #f4f4f4;
    padding: 12px;
    border-radius: 4px;
    overflow-x: auto;
    font-size: 9pt;
    line-height: 1.4;
    page-break-inside: avoid;
}
pre code {
    background: none;
    padding: 0;
}

/* Images */
img {
    max-width: 100%;
    height: auto;
    display: block;
    margin: 12px auto;
}

/* Math */
.mathjax-display {
    text-align: center;
    margin: 12px 0;
    overflow-x: auto;
}

/* Horizontal rules */
hr {
    border: none;
    border-top: 1px solid #ccc;
    margin: 24px 0;
}

/* Lists */
ul, ol {
    margin: 8px 0;
    padding-left: 28px;
}
li {
    margin: 3px 0;
}

/* Strong in paragraph (for labeled paragraphs like "C1. ...") */
strong {
    font-weight: bold;
}

/* Keywords line */
p > strong:first-child {
    font-weight: bold;
}

/* Figure captions */
p > strong:only-child {
    display: block;
    text-align: center;
    font-size: 10pt;
    margin-top: 4px;
}

/* Print tweaks */
@media print {
    body { margin: 0; padding: 0; }
    h2 { page-break-before: auto; }
    table, pre, img, .mathjax-display { page-break-inside: avoid; }
}

/* Footnote-style markers */
sup { font-size: 0.75em; vertical-align: super; }
"""

MATHJAX_CONFIG = r"""
<script>
MathJax = {
  tex: {
    inlineMath: [['\\(', '\\)']],
    displayMath: [['$$', '$$']],
    processEscapes: true,
    tags: 'ams'
  },
  svg: {
    fontCache: 'global'
  },
  startup: {
    pageReady: function() {
      return MathJax.startup.defaultPageReady().then(function() {
        // Signal that rendering is done
        document.body.setAttribute('data-mathjax-done', 'true');
      });
    }
  }
};
</script>
<script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js" async></script>
"""

def wrap_html(body, title=""):
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
<style>{CSS}</style>
{MATHJAX_CONFIG}
</head>
<body>
{body}
</body>
</html>
"""

# ---------------------------------------------------------------------------
# 5. Chrome headless PDF generation
# ---------------------------------------------------------------------------

def find_chrome():
    """Find Chrome executable on Windows."""
    candidates = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

def html_to_pdf_chrome(html_path, pdf_path, timeout=60):
    """Use Chrome headless to print HTML to PDF."""
    chrome = find_chrome()
    if not chrome:
        raise RuntimeError("Chrome not found")

    # Convert to file:// URI
    abs_html = os.path.abspath(html_path)
    file_url = 'file:///' + abs_html.replace('\\', '/')

    cmd = [
        chrome,
        '--headless=new',
        '--disable-gpu',
        '--no-sandbox',
        '--disable-extensions',
        '--run-all-compositor-stages-before-draw',
        f'--virtual-time-budget=30000',
        f'--print-to-pdf={os.path.abspath(pdf_path)}',
        '--no-pdf-header-footer',
        file_url,
    ]

    print(f"  Running Chrome headless (timeout={timeout}s)...")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

    if result.returncode != 0:
        stderr = result.stderr.strip()
        if stderr:
            print(f"  Chrome stderr: {stderr[:500]}")

    return os.path.isfile(pdf_path)

# ---------------------------------------------------------------------------
# 6. Main
# ---------------------------------------------------------------------------

def main():
    script_dir = Path(__file__).parent.parent  # PerformanceOptimizer/

    if len(sys.argv) >= 2:
        input_md = Path(sys.argv[1])
    else:
        input_md = script_dir / "paper_cn.md"

    if len(sys.argv) >= 3:
        output_pdf = Path(sys.argv[2])
    else:
        output_pdf = input_md.with_suffix('.pdf')

    print(f"Input:  {input_md}")
    print(f"Output: {output_pdf}")

    # Read markdown
    md_text = input_md.read_text(encoding='utf-8')

    # Extract title from first H1
    title_match = re.search(r'^#\s+(.+)$', md_text, re.MULTILINE)
    title = title_match.group(1) if title_match else "Paper"

    # Convert
    print("Converting Markdown -> HTML...")
    html_body = md_to_html(md_text)

    # Embed images
    html_body = embed_images(html_body, str(script_dir))

    # Assemble full HTML
    full_html = wrap_html(html_body, title)

    # Write intermediate HTML (useful for debugging)
    html_path = input_md.with_suffix('.html')
    html_path.write_text(full_html, encoding='utf-8')
    print(f"  HTML saved: {html_path}")

    # Generate PDF
    print("Generating PDF via Chrome headless...")
    success = html_to_pdf_chrome(str(html_path), str(output_pdf))

    if success and output_pdf.exists():
        size_mb = output_pdf.stat().st_size / (1024 * 1024)
        print(f"  PDF saved: {output_pdf} ({size_mb:.1f} MB)")
    else:
        print("  Chrome PDF generation failed.")
        print(f"  Fallback: open {html_path} in Chrome and use Ctrl+P -> Save as PDF")
        return 1

    return 0

if __name__ == '__main__':
    sys.exit(main())
