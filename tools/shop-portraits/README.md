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

The active shop set is derived from `data/shops/list.xml`. The single explicit exclusion is `幸存老兵-暂时停用`; the promoted closure must remain exactly `34/34` entries and `34` content-addressed subject files.

## Sources

The baker reuses the current dialogue portrait extraction helpers but owns a narrow, deterministic ShopPortraits output:

- 25 exact external dialogue SWFs
- 8 exact frames from the current `对话框肖像` XFL/SWF linkage, including a fresh `武器大师` extraction from DefineSprite `981`, frame `257`
- `heeho君` from the exact `地图-彩蛋地图` XFL/SWF chain: map `381` -> outer NPC `270` -> body `268`, neutral frame `1`

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
