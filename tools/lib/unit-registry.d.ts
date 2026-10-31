export interface UnitRecord {
  id: number;
  spritename: string;
  key?: string;
  [field: string]: unknown;
}
export class UnitRegistry {
  constructor(units: unknown);
  byId: Map<number, UnitRecord>;
  byKey: Map<string, number>;
  resolveType(reference: unknown, context?: string): string;
  resolveId(reference: unknown, context?: string): number;
  get(reference: unknown, context?: string): UnitRecord;
}
export function validKey(value: unknown): boolean;
export function extractDirectChildXml(body: string, childName: string, context?: string): string | null;
export const MAX_ID: number;
export const MAX_KEY_LENGTH: number;
