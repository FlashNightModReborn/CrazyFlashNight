/**
 * @cf7-animate-kit/core — pure TypeScript domain logic (zero I/O).
 *
 * Sub-domains:
 *  - amf:        AMF0 / Flash SharedObject (.sol) lossless codec + JSON projection
 *  - (P1) AnEnv: Animate install layout resolvers + jvm.ini/sidebar transforms (added later)
 *  - (P3) AuthoringModel: linkage / naming / dup-cluster / metadata rules (added later)
 */
export * from './amf/index.js';
export * as amf from './amf/index.js';
export * as anEnv from './an/index.js';
export * as authoring from './authoring/index.js';
export type {
  XflDocument,
  XflSymbolRef,
  XflMediaItem,
  FrameLabel,
  LintFinding,
  LinkageItem,
  DupCluster,
  LintSummary,
} from './authoring/index.js';
// Flat re-export of AnEnv types for ergonomic consumption.
export type {
  EnvSnapshot,
  AnimatePaths,
  JvmEditResult,
  SidebarResult,
  MachineInfo,
  MachineInfoInput,
} from './an/index.js';
