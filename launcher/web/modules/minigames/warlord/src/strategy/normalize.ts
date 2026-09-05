export interface NormalizedMapDefinitionInput {
  readonly source: Readonly<Record<string, unknown>>;
  readonly schemaVersion: unknown;
  readonly id: unknown;
  readonly rulesVersion: unknown;
  readonly encounterDefinitionRef: unknown;
  readonly nodes: readonly unknown[];
  readonly edges: readonly unknown[];
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function normalizeOneOrMany(value: unknown): readonly unknown[] {
  if (Array.isArray(value)) return [...value];
  if (value === undefined) return [];
  return [value];
}

export function normalizeMapDefinitionInput(input: unknown): NormalizedMapDefinitionInput | null {
  if (!isRecord(input)) return null;
  return {
    source: input,
    schemaVersion: input.schemaVersion,
    id: input.id,
    rulesVersion: input.rulesVersion,
    encounterDefinitionRef: input.encounterDefinitionRef,
    nodes: normalizeOneOrMany(input.nodes),
    edges: normalizeOneOrMany(input.edges),
  };
}
