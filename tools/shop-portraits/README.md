# ShopPortraits asset closure

`launcher/web/assets/shop-portraits/manifest.json` is the only runtime authority. It is independent of DialogueView and supports exact `shopId` lookup only.

## Frozen runtime contract

- schema: `cf7-shop-portraits-v1`
- geometry: transparent `256 x 256` PNG
- entry: `{ uri, width, height, bounds, sha256 }`
- bounds: integer `{ x, y, width, height }` alpha bounds
- URI: `subjects/<lowercase-full-sha256>.png`
- lookup: exact key only; no alias, trimming, case folding, fuzzy match, or placeholder
- failure: an absent or invalid entry/file resolves to no portrait (fail-soft)

The active shop set is derived from `data/shops/list.xml`. The single explicit exclusion is `幸存老兵-暂时停用`; the promoted closure must remain exactly `35/35` entries and `35` content-addressed subject files.

## Sources

The baker reuses the current dialogue portrait extraction helpers but owns a narrow, deterministic ShopPortraits output:

- 32 exact external dialogue SWFs
- 2 exact frames from the current `对话框肖像` XFL/SWF linkage (`爱国青年` and `武器大师`), including a fresh `武器大师` extraction from DefineSprite `981`, frame `257`
- `heeho君` from the exact `地图-彩蛋地图` XFL/SWF chain: map `465` -> outer NPC `270` -> body `268`, neutral frame `1`

The heeho pilot also requires the dedicated hat-head and sunglasses references in all four head tweens. It fails closed if the XFL/SWF placement is ambiguous and never aliases ordinary `杰克霜精`.

`provenance.json` records source and output SHA-256, byte size, dimensions/alpha bounds, selected frames/character IDs, and tool versions. `promotion-receipt.json` records the closure hashes and the subjects-first/manifest-last ordering contract.

## Build and validation

From the repository root:

```powershell
python tools/bake-shop-portraits.py --ffdec-timeout-seconds 240
python tools/test-shop-portrait-assets.py
python tools/bake-shop-portraits.py --check --ffdec-timeout-seconds 240
```

The first command builds in `tmp/` and promotes subjects before sidecars and the runtime manifest last. The fast test validates the already-promoted static closure and current source hashes without launching FFDec. The `--check` command performs a fresh source replay and exact byte-for-byte tree comparison without changing promoted output.

Temporary FFDec exports are removed by default. `--keep-work` is diagnostic-only; its output must not be committed.

On this Windows installation, the EXE wrapper cannot discover the existing Java runtime. Use the installed Animate Java 17 on the current process `PATH` and pass `--ffdec tools/ffdec/ffdec.bat`; the selected CLI file and actual Python/Pillow versions are recorded in provenance. The 2026-09-07 map republish changed the exported map sprite from `381` to `400`; the exact outer/body chain and neutral pose remain `270 -> 268 / frame 1`. Rebuild and compare before updating this frozen assertion; do not merely replace SWF/XFL hashes in provenance.

When only shop document content changes (for example, adding catalog products), run `python tools/refresh-shop-portrait-sources.py`, then the fast asset test. The bound baker consumes only `shopId` from those documents. This refresh requires the same ordered shop identities, list artifact and document paths; it reuses the complete existing validator for every rendering source, recipe, tool and output image. It updates only the shop-source metadata and its receipt, records the refresh tool, and preserves all 35 subject files and the runtime manifest. Changed shop identities or any rendering/input/output drift must use an explicit portrait rebuild.
