/** Authoring domain: XFL parsing + linkage/dup lint + asset metadata rules. */
export {
  parseXflDocument,
  extractFrameLabels,
  canonicalizeSymbolXml,
} from './xfl.js';
export type {
  XflDocument,
  XflDocumentInfo,
  XflSymbolRef,
  XflMediaItem,
  XflMediaKind,
  FrameLabel,
} from './xfl.js';
export {
  collectLinkageItems,
  lintLinkage,
  clusterDuplicates,
  summarizeLint,
} from './lint.js';
export type {
  LintLevel,
  LintFinding,
  LinkageItem,
  LintOptions,
  DupCluster,
  LintSummary,
} from './lint.js';

/** Standard exported avatar size (ARGB PNG after alpha-bbox crop) for the web UI. */
export const AVATAR_SIZE = 44;
