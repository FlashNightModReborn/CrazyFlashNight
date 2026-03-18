import type { FileEntry, LayerSummary } from "./types.js";

export function applyEstimatedSizes(layers: LayerSummary[], entries: FileEntry[]): LayerSummary[] {
  const layerSizes = new Map<string, number>();
  const layersWithKnownSize = new Set<string>();

  for (const entry of entries) {
    if (typeof entry.size !== "number") continue;
    layerSizes.set(entry.layer, (layerSizes.get(entry.layer) ?? 0) + entry.size);
    layersWithKnownSize.add(entry.layer);
  }

  return layers.map((layer) => {
    if (!layersWithKnownSize.has(layer.name)) {
      return { ...layer };
    }
    return {
      ...layer,
      estimatedSize: layerSizes.get(layer.name) ?? 0
    };
  });
}
