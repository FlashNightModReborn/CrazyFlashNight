# Intelligence Icon Tools

Utilities for the `outputs/intelligence-icons/` img2 workflow.

## `postprocess_chroma_icon.py`

Removes a flat chroma-key background from generated icon art and clears tiny
alpha noise.

Example:

```powershell
python tools/intelligence-icons/postprocess_chroma_icon.py `
  --input outputs/intelligence-icons/<round>/candidates/foo-raw.png `
  --out outputs/intelligence-icons/<round>/candidates/foo.png `
  --key "#ff00ff"
```

## `build_review_package.py`

Builds a consolidated review package from an explicit TSV manifest. The manifest
is explicit because final picks may come from main rounds or later single-icon
retune folders.

Required TSV columns:

```text
id	slug	title	status	source	note
```

Example:

```powershell
python tools/intelligence-icons/build_review_package.py `
  --manifest outputs/intelligence-icons/final-review-2026-06-30/manifest/final-icons.tsv `
  --remaining outputs/intelligence-icons/final-review-2026-06-30/manifest/remaining-unbuilt.tsv `
  --out outputs/intelligence-icons/final-review-2026-06-30 `
  --clean
```

The output contains:

- `final/`: copied final PNGs with stable filenames
- `review/final-overview-sheet.png`
- `review/final-preview-32-sheet.png`
- `review/final-alpha-stats.tsv`
- `review/final-status.tsv`
- `manifest/final-icons.tsv`
- `manifest/remaining-unbuilt.tsv`
