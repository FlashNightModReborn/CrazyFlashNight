import { sha256Canonical } from '../core/canonical.js';
import type { MapDefinition, MapPresentationDefinitionV1 } from './definitions.js';

export interface MapContractDigests {
  readonly rulesDigest: string;
  readonly presentationDigest: string;
}

export function computeRulesDigest(definition: MapDefinition): Promise<string> {
  return sha256Canonical(definition);
}

export function computePresentationDigest(
  presentation: MapPresentationDefinitionV1,
): Promise<string> {
  return sha256Canonical(presentation);
}

export async function computeMapContractDigests(
  definition: MapDefinition,
  presentation: MapPresentationDefinitionV1,
): Promise<MapContractDigests> {
  const [rulesDigest, presentationDigest] = await Promise.all([
    computeRulesDigest(definition),
    computePresentationDigest(presentation),
  ]);
  return Object.freeze({ rulesDigest, presentationDigest });
}
