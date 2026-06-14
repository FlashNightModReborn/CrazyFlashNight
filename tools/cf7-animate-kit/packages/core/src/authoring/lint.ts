import type { XflDocument } from './xfl.js';

export type LintLevel = 'error' | 'warn' | 'info';

export interface LintFinding {
  level: LintLevel;
  code: string;
  message: string;
  target?: string | undefined;
}

export interface LinkageItem {
  name: string;
  source: 'symbol' | 'media';
  linkageExportForAS: boolean;
  linkageIdentifier?: string | undefined;
}

/** Flatten a parsed document's symbols + media into linkage-bearing items. */
export function collectLinkageItems(doc: XflDocument): LinkageItem[] {
  return [
    ...doc.symbols.map((s): LinkageItem => ({
      name: s.name,
      source: 'symbol',
      linkageExportForAS: s.linkageExportForAS,
      linkageIdentifier: s.linkageIdentifier,
    })),
    ...doc.media.map((m): LinkageItem => ({
      name: m.name,
      source: 'media',
      linkageExportForAS: m.linkageExportForAS,
      linkageIdentifier: m.linkageIdentifier,
    })),
  ];
}

export interface LintOptions {
  /** Optional naming convention; only reported as a warning when provided. */
  namingPattern?: RegExp | undefined;
}

/**
 * Lint linkage: duplicate identifiers (error), exported-for-AS without an
 * identifier (error), and optional naming-convention warnings. The naming
 * check is OFF unless a pattern is supplied — real CF7 linkage ids are sound
 * filenames / Chinese names, not a single convention.
 */
export function lintLinkage(items: LinkageItem[], opts: LintOptions = {}): LintFinding[] {
  const findings: LintFinding[] = [];
  const byId = new Map<string, LinkageItem[]>();

  for (const it of items) {
    if (it.linkageExportForAS && !it.linkageIdentifier) {
      findings.push({
        level: 'error',
        code: 'exported-no-identifier',
        message: `"${it.name}" is exported for ActionScript but has no linkageIdentifier`,
        target: it.name,
      });
    }
    if (it.linkageIdentifier) {
      const arr = byId.get(it.linkageIdentifier) ?? [];
      arr.push(it);
      byId.set(it.linkageIdentifier, arr);
      if (opts.namingPattern && !opts.namingPattern.test(it.linkageIdentifier)) {
        findings.push({
          level: 'warn',
          code: 'naming',
          message: `linkageIdentifier "${it.linkageIdentifier}" does not match the naming convention`,
          target: it.name,
        });
      }
    }
  }

  for (const [id, arr] of byId) {
    if (arr.length > 1) {
      findings.push({
        level: 'error',
        code: 'duplicate-identifier',
        message: `linkageIdentifier "${id}" is used by ${arr.length} items: ${arr.map((a) => a.name).join(', ')}`,
      });
    }
  }
  return findings;
}

export interface DupCluster {
  key: string;
  members: string[];
}

/** Group items by their canonical key; clusters of size > 1 are duplicates. */
export function clusterDuplicates(items: Array<{ name: string; key: string }>): DupCluster[] {
  const byKey = new Map<string, string[]>();
  for (const it of items) {
    const arr = byKey.get(it.key) ?? [];
    arr.push(it.name);
    byKey.set(it.key, arr);
  }
  const clusters: DupCluster[] = [];
  for (const [key, members] of byKey) {
    if (members.length > 1) clusters.push({ key, members });
  }
  return clusters;
}

export interface LintSummary {
  errors: number;
  warnings: number;
  findings: LintFinding[];
}

export function summarizeLint(findings: LintFinding[]): LintSummary {
  return {
    errors: findings.filter((f) => f.level === 'error').length,
    warnings: findings.filter((f) => f.level === 'warn').length,
    findings,
  };
}
