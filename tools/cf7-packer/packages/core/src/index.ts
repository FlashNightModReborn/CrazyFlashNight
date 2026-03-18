// @cf7-packer/core — barrel export

export type {
  LayerRule,
  PackConfig,
  MinifyConfig,
  FileEntry,
  LayerSummary,
  CollectorResult,
  FilterResult,
  PackerOptions,
  PackResult,
  DiffResult,
  PackerLogEvent,
  PackerProgressEvent
} from "./types.js";
export { OutputDirNotOwnedError } from "./types.js";

export { packConfigSchema, layerRuleSchema } from "./config-schema.js";
export type { PackConfigRaw } from "./config-schema.js";

export { loadConfig, parseConfig } from "./config-loader.js";
export { filterFiles } from "./filter.js";
export { collect } from "./collector.js";
export { pack, validateOutputDir } from "./packer.js";
export { PackerEngine } from "./engine.js";
export { diffFilterResults } from "./diff.js";
export { enrichWithSize } from "./enrich.js";
export { minifyJson, minifyXml, minifyByExtension } from "./minify.js";
export { applyEstimatedSizes } from "./summary.js";
export { resolveOutputDir, renderOutputDirTemplate, sanitizePathToken } from "./output-path.js";
export { normalizeRepoRelativePath, normalizeLayerSource, isPathInsideRoot } from "./path-utils.js";
export { applyExcludeMutation, resolveExcludeMutation, prepareExcludeAction } from "./config-editor.js";
export { getTagBlobInfo, getWorktreeBlobHashes, getModifiedPathsBetweenTags } from "./content-hash.js";
export type { PrepareExcludeActionResult } from "./config-editor.js";
