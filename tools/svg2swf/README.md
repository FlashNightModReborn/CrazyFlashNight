# svg2swf

Local technical reserve for converting SVG vector icons to SWF assets that Flash CS6 can inspect/import/load without parsing SVG directly.

## Package

- Upstream homepage: <https://svg2swf.sourceforge.net/>
- Downloaded package: `svg2swf-0.5.win32.exe.zip`
- Mirror URL used: <https://master.dl.sourceforge.net/project/svg2swf/svg2swf/0.5/svg2swf-0.5.win32.exe.zip?viasf=1>
- SHA256: `CF9610D8D2B01295B6F55AD5592D4496191747DF39F64D6D25DA840983947976`
- License: LGPL-2.1, copied in `svg2swf-0.5/COPYING.txt`

## Usage

```powershell
chcp.com 65001 | Out-Null
.\tools\svg2swf\svg2swf-0.5\svg2swf.exe input.svg output.swf
```

For SVGs without explicit dimensions, pass `--dsize <width>x<height>`.

## Smoke Test

Tested with:

```powershell
.\tools\svg2swf\svg2swf-0.5\svg2swf.exe `
  outputs\intelligence-icons\final-review-2026-06-30\svg\01-basic-home-recipe.svg `
  outputs\intelligence-icons\final-review-2026-06-30\swf-test\01-basic-home-recipe.swf
```

Observed output:

- SWF header: `FWS`, version `8`
- Output length: `9772` bytes
- Parsed tags: `20` shape tags, `0` bitmap tags

This confirms the tested Vector Magic SVG was converted into SWF vector shapes rather than a raster bitmap container.

## Limits

`svg2swf` supports only the SVG subset exposed by `libsvg`. It is suitable for simple path/fill icon assets, but complex filters, fonts, interactivity, scripting, and animation are not supported. Before using this for production asset replacement, validate representative outputs in Flash CS6 and compare visual fidelity at the target in-game icon size.
